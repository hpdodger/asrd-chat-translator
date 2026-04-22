// Chat Translator — core module, loaded into the worldspawn entity scope.
// Execute via: IncludeScript("chat_translate", hWorld.GetScriptScope())
//
// Player chat commands:
//   !ct_lang <code>       — set translation language  (e.g. !ct_lang ru)
//   !ct_lang              — show current language
//   !ct_translate on/off  — enable/disable translation
//   !ct_langs             — list available languages
//   !ct_help              — show help message

// ── Constants ────────────────────────────────────────────────────────────────

const TRANSLATE_REQ_FILE     = "translate_req"
const TRANSLATE_RESP_FILE    = "translate_resp"
const TRANSLATE_PREFS_FILE   = "translate_prefs"
const TRANSLATE_LANGS_FILE   = "translate_langs"
const TRANSLATE_POLL_SEC     = 0.5
const TRANSLATE_TIMEOUT_SEC  = 20.0
const TRANSLATE_DEFAULT_LANG = "en"
const HUD_PRINTCONSOLE       = 2    // Source Engine: print to player console
const HUD_PRINTCHAT          = 3    // Source Engine: print to chat box
const LANG_CODE_LEN          = 2    // ISO 639-1 two-letter codes
const CMD_LANG_SET_PREFIX    = "!ct_lang "

// ── State ────────────────────────────────────────────────────────────────────

nTranslateNextId  <- 0
TranslateQueue    <- []
bTranslateWaiting <- false
fTranslateSentAt  <- 0.0
PlayerLangPrefs   <- {}   // netid -> lang
PlayerTranslateOn <- {}   // netid -> bool (default true)
PendingWelcome    <- []   // array of {hPlayer, showAt}

// ── Helper functions ─────────────────────────────────────────────────────────

_SplitString <- function( str, sep ) {
    local result = [];
    local start  = 0;
    local idx    = str.find( sep, start );
    while ( idx != null ) {
        result.append( str.slice( start, idx ) );
        start = idx + sep.len();
        idx   = str.find( sep, start );
    }
    if ( start < str.len() )
        result.append( str.slice( start ) );
    return result;
}

// Find the position of the last occurrence of a character in a string
_LastIndexOf <- function( str, ch ) {
    for ( local i = str.len() - 1; i >= 0; i-- )
        if ( str.slice( i, i + 1 ) == ch )
            return i;
    return null;
}

// ── Preferences ──────────────────────────────────────────────────────────────
//
// translate_prefs file format (one record per line):
//   <netid>:<lang>:<1|0>
//   Example: STEAM_0:1:12345678:ru:1
//
// Backwards compatibility: old format <netid>:<lang> (without flag) is read as enabled=1

_LoadPrefs <- function() {
    local raw = FileToString( TRANSLATE_PREFS_FILE );
    if ( raw == null || raw == "" )
        return;

    local lines = _SplitString( raw, "\n" );
    foreach ( line in lines ) {
        if ( line.len() > 0 && line.slice( line.len() - 1 ) == "\r" )
            line = line.slice( 0, line.len() - 1 );
        if ( line.len() == 0 )
            continue;

        // Last segment is either "0"/"1" (new format) or lang code (old format)
        local lastColon = _LastIndexOf( line, ":" );
        if ( lastColon == null || lastColon >= line.len() - 1 )
            continue;

        local lastSeg = line.slice( lastColon + 1 );
        local rest    = line.slice( 0, lastColon );

        local netid   = null;
        local lang    = null;
        local enabled = true;

        if ( lastSeg == "0" || lastSeg == "1" ) {
            // New format: netid:lang:enabled
            enabled = ( lastSeg == "1" );
            local langColon = _LastIndexOf( rest, ":" );
            if ( langColon == null || langColon >= rest.len() - 1 )
                continue;
            lang  = rest.slice( langColon + 1 );
            netid = rest.slice( 0, langColon );
        } else {
            // Old format: netid:lang
            lang  = lastSeg;
            netid = rest;
        }

        if ( netid == null || netid.len() == 0 || lang == null || lang.len() != LANG_CODE_LEN )
            continue;

        PlayerLangPrefs[ netid ]   <- lang;
        PlayerTranslateOn[ netid ] <- enabled;
    }
}

_SavePrefs <- function() {
    local content = "";
    foreach ( netid, lang in PlayerLangPrefs ) {
        local enabled = !( netid in PlayerTranslateOn ) || PlayerTranslateOn[ netid ];
        content += netid + ":" + lang + ":" + ( enabled ? "1" : "0" ) + "\n";
    }
    // Save players that have only a flag but no explicit language
    foreach ( netid, enabled in PlayerTranslateOn ) {
        if ( !( netid in PlayerLangPrefs ) )
            content += netid + ":" + TRANSLATE_DEFAULT_LANG + ":" + ( enabled ? "1" : "0" ) + "\n";
    }
    StringToFile( TRANSLATE_PREFS_FILE, content );
}

// ── Language helpers ─────────────────────────────────────────────────────────

_GetAvailableLangs <- function() {
    local raw = FileToString( TRANSLATE_LANGS_FILE );
    if ( raw == null || raw == "" )
        return [];
    // Strip possible trailing newline
    while ( raw.len() > 0 && ( raw.slice( raw.len() - 1 ) == "\n" || raw.slice( raw.len() - 1 ) == "\r" ) )
        raw = raw.slice( 0, raw.len() - 1 );
    return _SplitString( raw, "," );
}

_AvailableLangsStr <- function() {
    local langs = _GetAvailableLangs();
    if ( langs.len() == 0 )
        return "—";
    local result = "";
    foreach ( i, lang in langs ) {
        if ( i > 0 ) result += ", ";
        result += lang;
    }
    return result;
}

_GetPlayerLang <- function( hPlayer ) {
    local netid = hPlayer.GetNetworkIDString();
    if ( netid in PlayerLangPrefs )
        return PlayerLangPrefs[ netid ];
    return TRANSLATE_DEFAULT_LANG;
}

_IsTranslateEnabled <- function( hPlayer ) {
    local netid = hPlayer.GetNetworkIDString();
    if ( netid in PlayerTranslateOn )
        return PlayerTranslateOn[ netid ];
    return true;   // enabled by default
}

// Collect languages only for players with translation enabled
_GetOnlineLangs <- function() {
    local seen  = {};
    local langs = [];
    local hP = Entities.FindByClassname( null, "player" );
    while ( hP != null ) {
        if ( hP.IsValid() && _IsTranslateEnabled( hP ) ) {
            local lang = _GetPlayerLang( hP );
            if ( !( lang in seen ) ) {
                seen[ lang ] <- true;
                langs.append( lang );
            }
        }
        hP = Entities.FindByClassname( hP, "player" );
    }
    if ( langs.len() == 0 )
        langs.append( TRANSLATE_DEFAULT_LANG );
    return langs;
}

// ── Help / welcome message ───────────────────────────────────────────────────

_PrintHelp <- function( hPlayer ) {
    local lang    = _GetPlayerLang( hPlayer );
    local enabled = _IsTranslateEnabled( hPlayer );

    local status = enabled
        ? ( TextColor( 100, 200, 100 ) + "enabled" + TextColor( 180, 180, 180 ) + ", language: " + TextColor( 255, 220, 80 ) + lang )
        : ( TextColor( 200, 80, 80   ) + "disabled" );

    ClientPrint( hPlayer, HUD_PRINTCHAT,
        TextColor( 100, 160, 255 ) + "[Translate] " +
        TextColor( 180, 180, 180 ) + "Chat translator " + status );
    ClientPrint( hPlayer, HUD_PRINTCHAT,
        TextColor( 180, 180, 180 ) + "  Languages: " +
        TextColor( 255, 220, 80  ) + _AvailableLangsStr() );
    ClientPrint( hPlayer, HUD_PRINTCHAT,
        TextColor( 140, 140, 140 ) + "  !ct_lang <code>          — set translation language | !ct_help - this message" );
    ClientPrint( hPlayer, HUD_PRINTCHAT,
        TextColor( 140, 140, 140 ) + "  !ct_translate on/off — enable/disable  |  !ct_langs — list languages" );
}

// Delay the welcome message so the player's HUD is ready to display it
_OnPlayerActivate <- function( hPlayer ) {
    PendingWelcome.append( { hPlayer = hPlayer, showAt = Time() + 4.0 } );
}

// ── Send the first queue entry to the translator ──────────────────────────────

_TranslateSendNext <- function() {
    if ( TranslateQueue.len() == 0 ) {
        bTranslateWaiting = false;
        return;
    }

    local entry = TranslateQueue[ 0 ];
    bTranslateWaiting = true;
    fTranslateSentAt  = Time();

    local langStr = "";
    foreach ( i, lang in entry.langs ) {
        if ( i > 0 ) langStr += ",";
        langStr += lang;
    }

    StringToFile( TRANSLATE_REQ_FILE, entry.id + "|" + entry.original + "|" + langStr );
}

// ── Think: poll for response every TRANSLATE_POLL_SEC seconds ─────────────────

_TranslateThink <- function() {
    // Process delayed welcome messages
    if ( PendingWelcome.len() > 0 ) {
        local remaining = [];
        local now = Time();
        foreach ( entry in PendingWelcome ) {
            if ( now >= entry.showAt ) {
                if ( entry.hPlayer.IsValid() )
                    _PrintHelp( entry.hPlayer );
            } else {
                remaining.append( entry );
            }
        }
        PendingWelcome = remaining;
    }

    if ( !bTranslateWaiting )
        return TRANSLATE_POLL_SEC;

    if ( Time() - fTranslateSentAt > TRANSLATE_TIMEOUT_SEC ) {
        local entry = TranslateQueue[ 0 ];
        ClientPrint( null, HUD_PRINTCHAT,
            TextColor( 200, 80, 80 ) + "[Translate] Timeout: " +
            TextColor( 180, 180, 180 ) + entry.original );
        TranslateQueue.remove( 0 );
        _TranslateSendNext();
        return TRANSLATE_POLL_SEC;
    }

    local resp = FileToString( TRANSLATE_RESP_FILE );
    if ( resp == "" || resp == null || resp == "0" )
        return TRANSLATE_POLL_SEC;

    local segments = _SplitString( resp, "|" );
    if ( segments.len() < 2 )
        return TRANSLATE_POLL_SEC;

    local respId = segments[ 0 ];

    if ( TranslateQueue.len() == 0 || TranslateQueue[ 0 ].id != respId )
        return TRANSLATE_POLL_SEC;

    local entry = TranslateQueue[ 0 ];

    local translations = {};
    for ( local i = 1; i < segments.len(); i++ ) {
        local seg      = segments[ i ];
        local colonIdx = seg.find( ":" );
        if ( colonIdx == null )
            continue;
        translations[ seg.slice( 0, colonIdx ) ] <- seg.slice( colonIdx + 1 );
    }

    local hP = Entities.FindByClassname( null, "player" );
    while ( hP != null ) {
        // Skip the sender — they already see their own message in chat
        if ( hP.IsValid() && _IsTranslateEnabled( hP ) && hP.GetNetworkIDString() != entry.senderNetid ) {
            local lang = _GetPlayerLang( hP );

            local translated = null;
            if ( lang in translations )
                translated = translations[ lang ];
            else if ( "en" in translations )
                translated = translations[ "en" ];
            else
                foreach ( k, v in translations ) { translated = v; break }

            if ( translated == null )
                translated = entry.original;

            ClientPrint( hP, HUD_PRINTCHAT,
                TextColor( 100, 160, 255 ) + "[" + entry.name + "]: " +
                TextColor( 255, 220, 80  ) + translated );
        }
        hP = Entities.FindByClassname( hP, "player" );
    }

    // Print all translations to the sender's console so they can verify the result
    local hSender = Entities.FindByClassname( null, "player" );
    while ( hSender != null ) {
        if ( hSender.IsValid() && hSender.GetNetworkIDString() == entry.senderNetid ) {
            foreach ( lang, translated in translations )
                ClientPrint( hSender, HUD_PRINTCONSOLE, "[Translate] " + lang + ": " + translated );
            break;
        }
        hSender = Entities.FindByClassname( hSender, "player" );
    }

    StringToFile( TRANSLATE_RESP_FILE, "0" );
    TranslateQueue.remove( 0 );
    _TranslateSendNext();

    return TRANSLATE_POLL_SEC;
}

// ── Chat command handler ─────────────────────────────────────────────────────

_OnPlayerSay <- function( params ) {
    local hPlayer = GetPlayerFromUserID( params[ "userid" ] );
    if ( !hPlayer ) return;

    local text = params[ "text" ];
    if ( text.len() == 0 ) return;

    local netid = hPlayer.GetNetworkIDString();

    // Command !ct_langs — list available languages
    if ( text == "!ct_langs" ) {
        ClientPrint( hPlayer, HUD_PRINTCHAT,
            TextColor( 100, 160, 255 ) + "[Translate] Available languages: " +
            TextColor( 255, 220, 80  ) + _AvailableLangsStr() );
        return;
    }

    // Command !ct_translate on / !ct_translate off
    if ( text == "!ct_translate on" || text == "!ct_translate off" ) {
        local enable = ( text == "!ct_translate on" );
        PlayerTranslateOn[ netid ] <- enable;
        // Record default language if none saved yet, so there is something to persist
        if ( !( netid in PlayerLangPrefs ) )
            PlayerLangPrefs[ netid ] <- TRANSLATE_DEFAULT_LANG;
        _SavePrefs();
        ClientPrint( hPlayer, HUD_PRINTCHAT,
            TextColor( 100, 160, 255 ) + "[Translate] " +
            ( enable
                ? TextColor( 100, 200, 100 ) + "Translation enabled"
                : TextColor( 200, 80,  80  ) + "Translation disabled" ) );
        return;
    }

    // Command !ct_lang (no argument) — show current language
    if ( text == "!ct_lang" ) {
        local lang = _GetPlayerLang( hPlayer );
        ClientPrint( hPlayer, HUD_PRINTCHAT,
            TextColor( 100, 160, 255 ) + "[Translate] Current language: " +
            TextColor( 255, 220, 80  ) + lang );
        return;
    }

    // Command !ct_lang <code> — set language
    if ( text.len() > CMD_LANG_SET_PREFIX.len() && text.slice( 0, CMD_LANG_SET_PREFIX.len() ) == CMD_LANG_SET_PREFIX ) {
        local lang = text.slice( CMD_LANG_SET_PREFIX.len() ).tolower();
        if ( lang.len() == LANG_CODE_LEN ) {
            PlayerLangPrefs[ netid ]  <- lang;
            PlayerTranslateOn[ netid ] <- true;
            _SavePrefs();
            ClientPrint( hPlayer, HUD_PRINTCHAT,
                TextColor( 100, 200, 100 ) + "[Translate] Language set: " + lang );
        } else {
            ClientPrint( hPlayer, HUD_PRINTCHAT,
                TextColor( 200, 80, 80 ) + "[Translate] Usage: !ct_lang <code>  (e.g. !ct_lang ru)" );
        }
        return;
    }

    // Command !ct_help — show help message
    if ( text == "!ct_help" ) {
        _PrintHelp( hPlayer );
        return;
    }

    // Skip other commands
    local firstChar = text.slice( 0, 1 );
    if ( firstChar == "!" || firstChar == "/" || firstChar == "\\" || firstChar == "&" || firstChar == "?" )
        return;

    nTranslateNextId += 1;
    TranslateQueue.append( {
        id          = nTranslateNextId.tostring(),
        name        = hPlayer.GetPlayerName(),
        senderNetid = netid,
        original    = text,
        langs       = _GetOnlineLangs()
    } );

    if ( !bTranslateWaiting )
        _TranslateSendNext();
}

// ── Startup ──────────────────────────────────────────────────────────────────
// Zero out IPC files so messages from a previous session don't appear in chat

StringToFile( TRANSLATE_REQ_FILE,  "0" );
StringToFile( TRANSLATE_RESP_FILE, "0" );
AddThinkToEnt( hWorld, "_TranslateThink" );
_LoadPrefs();

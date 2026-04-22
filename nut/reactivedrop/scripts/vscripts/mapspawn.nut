// Chat Translator — loaded at the start of any map (including lobby)
//
// Requirements:
//   docker compose up --build  (from the asrd-chat-translator root)
//   HOST_GAME_DATA_PATH set in .env
//
// Player chat commands:
//   !ct_lang <code>        — set translation language  (e.g. !ct_lang ru)
//   !ct_lang               — show current language
//   !ct_translate on       — enable translation (enabled by default)
//   !ct_translate off      — disable translation for yourself
//   !ct_langs              — list available languages
//   !ct_help               — show this help message

// Guard against double initialization (in case both files are loaded)
if ( "ChatTranslateLoaded" in getroottable() )
    return;
getroottable().ChatTranslateLoaded <- true;

printl( "─────────────────────────────────────────" );
printl( "  Chat Translator  v1.0" );
printl( "  Author: https://steamcommunity.com/id/w_asd/" );
printl( "─────────────────────────────────────────" );

const TRANSLATE_REQ_FILE     = "translate_req";
const TRANSLATE_RESP_FILE    = "translate_resp";
const TRANSLATE_PREFS_FILE   = "translate_prefs";
const TRANSLATE_LANGS_FILE   = "translate_langs";
const TRANSLATE_POLL_SEC     = 0.5;
const TRANSLATE_TIMEOUT_SEC  = 8.0;
const TRANSLATE_DEFAULT_LANG = "en";

// ── Helper functions ──────────────────────────────────────────────────────────

function SplitString( str, sep ) {
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
function LastIndexOf( str, ch ) {
    for ( local i = str.len() - 1; i >= 0; i-- )
        if ( str.slice( i, i + 1 ) == ch )
            return i;
    return null;
}

// ── State (in entity scope) ───────────────────────────────────────────────────

hWorld <- Entities.FindByClassname( null, "worldspawn" );
hWorld.ValidateScriptScope();
hWorld.GetScriptScope().nTranslateNextId    <- 0;
hWorld.GetScriptScope().TranslateQueue      <- [];
hWorld.GetScriptScope().bTranslateWaiting   <- false;
hWorld.GetScriptScope().fTranslateSentAt    <- 0.0;
hWorld.GetScriptScope().PlayerLangPrefs     <- {};   // netid -> lang
hWorld.GetScriptScope().PlayerTranslateOn   <- {};   // netid -> bool (default true)

// ── Preferences ───────────────────────────────────────────────────────────────
//
// translate_prefs file format (one record per line):
//   <netid>:<lang>:<1|0>
//   Example: STEAM_0:1:12345678:ru:1
//
// Backwards compatibility: old format <netid>:<lang> (without flag) is read as enabled=1

hWorld.GetScriptScope()._LoadPrefs <- function() {
    local raw = FileToString( TRANSLATE_PREFS_FILE );
    if ( raw == null || raw == "" )
        return;

    local lines = SplitString( raw, "\n" );
    foreach ( line in lines ) {
        if ( line.len() > 0 && line.slice( line.len() - 1 ) == "\r" )
            line = line.slice( 0, line.len() - 1 );
        if ( line.len() == 0 )
            continue;

        // Last segment is either "0"/"1" (new format) or lang code (old format)
        local lastColon = LastIndexOf( line, ":" );
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
            local langColon = LastIndexOf( rest, ":" );
            if ( langColon == null || langColon >= rest.len() - 1 )
                continue;
            lang  = rest.slice( langColon + 1 );
            netid = rest.slice( 0, langColon );
        } else {
            // Old format: netid:lang
            lang  = lastSeg;
            netid = rest;
        }

        if ( netid == null || netid.len() == 0 || lang == null || lang.len() != 2 )
            continue;

        PlayerLangPrefs[ netid ]   <- lang;
        PlayerTranslateOn[ netid ] <- enabled;
    }
};

hWorld.GetScriptScope()._SavePrefs <- function() {
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
};

// Get array of available languages from translate_langs file
hWorld.GetScriptScope()._GetAvailableLangs <- function() {
    local raw = FileToString( TRANSLATE_LANGS_FILE );
    if ( raw == null || raw == "" )
        return [];
    // Strip possible trailing newline
    while ( raw.len() > 0 && ( raw.slice( raw.len()-1 ) == "\n" || raw.slice( raw.len()-1 ) == "\r" ) )
        raw = raw.slice( 0, raw.len()-1 );
    return SplitString( raw, "," );
};

// Comma-separated string of available languages for chat output
hWorld.GetScriptScope()._AvailableLangsStr <- function() {
    local langs = _GetAvailableLangs();
    if ( langs.len() == 0 )
        return "—";
    local result = "";
    foreach ( i, lang in langs ) {
        if ( i > 0 ) result += ", ";
        result += lang;
    }
    return result;
};

hWorld.GetScriptScope()._GetPlayerLang <- function( hPlayer ) {
    local netid = hPlayer.GetNetworkIDString();
    if ( netid in PlayerLangPrefs )
        return PlayerLangPrefs[ netid ];
    return TRANSLATE_DEFAULT_LANG;
};

hWorld.GetScriptScope()._IsTranslateEnabled <- function( hPlayer ) {
    local netid = hPlayer.GetNetworkIDString();
    if ( netid in PlayerTranslateOn )
        return PlayerTranslateOn[ netid ];
    return true;   // enabled by default
};

// Collect languages only for players with translation enabled
hWorld.GetScriptScope()._GetOnlineLangs <- function() {
    local seen  = {};
    local langs = [];
    local hP = Entities.FindByClassname( null, "player" );
    while ( hP != null ) {
        if ( hP.IsValid() && _IsTranslateEnabled( hP ) ) {
            local lang = _GetPlayerLang( hP );
            if ( !(lang in seen) ) {
                seen[ lang ] <- true;
                langs.append( lang );
            }
        }
        hP = Entities.FindByClassname( hP, "player" );
    }
    if ( langs.len() == 0 )
        langs.append( TRANSLATE_DEFAULT_LANG );
    return langs;
};

// ── Print help / welcome message to a player ──────────────────────────────────

hWorld.GetScriptScope()._PrintHelp <- function( hPlayer ) {
    local lang    = _GetPlayerLang( hPlayer );
    local enabled = _IsTranslateEnabled( hPlayer );

    local status = enabled
        ? ( TextColor( 100, 200, 100 ) + "enabled" + TextColor( 180, 180, 180 ) + ", language: " + TextColor( 255, 220, 80 ) + lang )
        : ( TextColor( 200, 80, 80  ) + "disabled" );

    ClientPrint( hPlayer, 3,
        TextColor( 100, 160, 255 ) + "[Translate] " +
        TextColor( 180, 180, 180 ) + "Chat translator " + status );
    ClientPrint( hPlayer, 3,
        TextColor( 180, 180, 180 ) + "  Languages: " +
        TextColor( 255, 220, 80  ) + _AvailableLangsStr() );
    ClientPrint( hPlayer, 3,
        TextColor( 140, 140, 140 ) + "  !ct_lang <code>          — set translation language | !ct_help - this message" );
    ClientPrint( hPlayer, 3,
        TextColor( 140, 140, 140 ) + "  !ct_translate on/off — enable/disable  |  !ct_langs — list languages" );
};

// ── Send the first queue entry to the translator ──────────────────────────────

hWorld.GetScriptScope()._TranslateSendNext <- function() {
    if ( TranslateQueue.len() == 0 ) {
        bTranslateWaiting = false;
        return;
    }

    local entry = TranslateQueue[0];
    bTranslateWaiting = true;
    fTranslateSentAt  = Time();

    local langStr = "";
    foreach ( i, lang in entry.langs ) {
        if ( i > 0 ) langStr += ",";
        langStr += lang;
    }

    StringToFile( TRANSLATE_REQ_FILE, entry.id + "|" + entry.original + "|" + langStr );
};

// ── Think: poll for response every TRANSLATE_POLL_SEC seconds ─────────────────

hWorld.GetScriptScope()._TranslateThink <- function() {
    if ( !bTranslateWaiting )
        return TRANSLATE_POLL_SEC;

    if ( Time() - fTranslateSentAt > TRANSLATE_TIMEOUT_SEC ) {
        local entry = TranslateQueue[0];
        ClientPrint( null, 3,
            TextColor( 200, 80, 80 ) + "[Translate] Timeout: " +
            TextColor( 180, 180, 180 ) + entry.original );
        TranslateQueue.remove( 0 );
        _TranslateSendNext();
        return TRANSLATE_POLL_SEC;
    }

    local resp = FileToString( TRANSLATE_RESP_FILE );
    if ( resp == "" || resp == null || resp == "0" )
        return TRANSLATE_POLL_SEC;

    local segments = SplitString( resp, "|" );
    if ( segments.len() < 2 )
        return TRANSLATE_POLL_SEC;

    local respId = segments[0];

    if ( TranslateQueue.len() == 0 || TranslateQueue[0].id != respId )
        return TRANSLATE_POLL_SEC;

    local entry = TranslateQueue[0];

    local translations = {};
    for ( local i = 1; i < segments.len(); i++ ) {
        local seg      = segments[i];
        local colonIdx = seg.find( ":" );
        if ( colonIdx == null )
            continue;
        translations[ seg.slice( 0, colonIdx ) ] <- seg.slice( colonIdx + 1 );
    }

    local hP = Entities.FindByClassname( null, "player" );
    while ( hP != null ) {
        if ( hP.IsValid() && _IsTranslateEnabled( hP ) ) {
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

            ClientPrint( hP, 3,
                TextColor( 100, 160, 255 ) + "[" + entry.name + "]: " +
                TextColor( 255, 220, 80  ) + translated );
        }
        hP = Entities.FindByClassname( hP, "player" );
    }

    StringToFile( TRANSLATE_RESP_FILE, "0" );
    TranslateQueue.remove( 0 );
    _TranslateSendNext();

    return TRANSLATE_POLL_SEC;
};

AddThinkToEnt( hWorld, "_TranslateThink" );

// ── Reset IPC files on startup ────────────────────────────────────────────────
// Zero out so messages from a previous session don't appear in chat

StringToFile( TRANSLATE_REQ_FILE,  "0" );
StringToFile( TRANSLATE_RESP_FILE, "0" );

// ── Load preferences on startup ───────────────────────────────────────────────

hWorld.GetScriptScope()._LoadPrefs();

// ── Welcome message on player connect ────────────────────────────────────────

function OnGameEvent_player_activate( params ) {
    local hPlayer = GetPlayerFromUserID( params["userid"] );
    if ( !hPlayer )
        return;

    local sc = hWorld.GetScriptScope();
    sc._PrintHelp( hPlayer );
}

// ── Chat intercept ────────────────────────────────────────────────────────────

function OnGameEvent_player_say( params ) {
    local hPlayer = GetPlayerFromUserID( params["userid"] );
    if ( !hPlayer )
        return;

    local text = params["text"];
    if ( text.len() == 0 )
        return;

    local sc    = hWorld.GetScriptScope();
    local netid = hPlayer.GetNetworkIDString();

    // Command !ct_langs — list available languages
    if ( text == "!ct_langs" ) {
        ClientPrint( hPlayer, 3,
            TextColor( 100, 160, 255 ) + "[Translate] Available languages: " +
            TextColor( 255, 220, 80  ) + sc._AvailableLangsStr() );
        return;
    }

    // Command !ct_translate on / !ct_translate off
    if ( text == "!ct_translate on" || text == "!ct_translate off" ) {
        local enable = ( text == "!ct_translate on" );
        sc.PlayerTranslateOn[ netid ] <- enable;
        // Record default language if none saved yet, so there is something to persist
        if ( !( netid in sc.PlayerLangPrefs ) )
            sc.PlayerLangPrefs[ netid ] <- TRANSLATE_DEFAULT_LANG;
        sc._SavePrefs();
        ClientPrint( hPlayer, 3,
            TextColor( 100, 160, 255 ) + "[Translate] " +
            ( enable
                ? TextColor( 100, 200, 100 ) + "Translation enabled"
                : TextColor( 200, 80,  80  ) + "Translation disabled" ) );
        return;
    }

    // Command !ct_lang (no argument) — show current language
    if ( text == "!ct_lang" ) {
        local lang = sc._GetPlayerLang( hPlayer );
        ClientPrint( hPlayer, 3,
            TextColor( 100, 160, 255 ) + "[Translate] Current language: " +
            TextColor( 255, 220, 80  ) + lang );
        return;
    }

    // Command !ct_lang <code> — set language
    if ( text.len() >= 9 && text.slice( 0, 9 ) == "!ct_lang " ) {
        local lang = text.slice( 9 ).tolower();
        if ( lang.len() == 2 ) {
            sc.PlayerLangPrefs[ netid ] <- lang;
            // Enable translation if it was disabled
            sc.PlayerTranslateOn[ netid ] <- true;
            sc._SavePrefs();
            ClientPrint( hPlayer, 3,
                TextColor( 100, 200, 100 ) + "[Translate] Language set: " + lang );
        } else {
            ClientPrint( hPlayer, 3,
                TextColor( 200, 80, 80 ) + "[Translate] Usage: !ct_lang <code>  (e.g. !ct_lang ru)" );
        }
        return;
    }

    // Command !ct_help — show help message
    if ( text == "!ct_help" ) {
        sc._PrintHelp( hPlayer );
        return;
    }

    // Skip other commands
    local firstChar = text.slice( 0, 1 );
    if ( firstChar == "!" || firstChar == "/" || firstChar == "\\" || firstChar == "&" || firstChar == "?" )
        return;

    sc.nTranslateNextId += 1;
    sc.TranslateQueue.append( {
        id       = sc.nTranslateNextId.tostring(),
        name     = hPlayer.GetPlayerName(),
        original = text,
        langs    = sc._GetOnlineLangs()
    } );

    if ( !sc.bTranslateWaiting )
        sc._TranslateSendNext();
}

// Chat Translator — загружается при старте любой карты (включая лобби)
//
// Требования:
//   docker compose up --build  (из корня asrd-chat-translator)
//   HOST_GAME_DATA_PATH задан в .env
//
// Команды игрока в чате:
//   !lang <код>       — установить язык перевода  (напр. !lang ru)
//   !translate on     — включить перевод (по умолчанию включён)
//   !translate off    — отключить перевод для себя

// Guard от двойной инициализации (на случай если оба файла будут загружены)
if ( "ChatTranslateLoaded" in getroottable() )
    return
getroottable().ChatTranslateLoaded <- true

printl( "─────────────────────────────────────────" )
printl( "  Chat Translator  v1.0" )
printl( "  Author: https://steamcommunity.com/id/w_asd/" )
printl( "─────────────────────────────────────────" )

const TRANSLATE_REQ_FILE     = "translate_req"
const TRANSLATE_RESP_FILE    = "translate_resp"
const TRANSLATE_PREFS_FILE   = "translate_prefs"
const TRANSLATE_LANGS_FILE   = "translate_langs"
const TRANSLATE_POLL_SEC     = 0.5
const TRANSLATE_TIMEOUT_SEC  = 8.0
const TRANSLATE_DEFAULT_LANG = "en"

// ── Вспомогательные функции ───────────────────────────────────────────────────

function SplitString( str, sep )
{
    local result = []
    local start  = 0
    local idx    = str.find( sep, start )
    while ( idx != null )
    {
        result.append( str.slice( start, idx ) )
        start = idx + sep.len()
        idx   = str.find( sep, start )
    }
    if ( start < str.len() )
        result.append( str.slice( start ) )
    return result
}

// Найти позицию последнего вхождения символа в строке
function LastIndexOf( str, ch )
{
    for ( local i = str.len() - 1; i >= 0; i-- )
        if ( str.slice( i, i + 1 ) == ch )
            return i
    return null
}

// ── Состояние (в scope сущности) ─────────────────────────────────────────────

hWorld <- Entities.FindByClassname( null, "worldspawn" )
hWorld.ValidateScriptScope()
hWorld.GetScriptScope().nTranslateNextId    <- 0
hWorld.GetScriptScope().TranslateQueue      <- []
hWorld.GetScriptScope().bTranslateWaiting   <- false
hWorld.GetScriptScope().fTranslateSentAt    <- 0.0
hWorld.GetScriptScope().PlayerLangPrefs     <- {}   // netid -> lang
hWorld.GetScriptScope().PlayerTranslateOn   <- {}   // netid -> bool (default true)

// ── Предпочтения ──────────────────────────────────────────────────────────────
//
// Формат файла translate_prefs (по одной записи на строку):
//   <netid>:<lang>:<1|0>
//   Пример: STEAM_0:1:12345678:ru:1
//
// Обратная совместимость: старый формат <netid>:<lang> (без флага) читается как enabled=1

hWorld.GetScriptScope()._LoadPrefs <- function()
{
    local raw = FileToString( TRANSLATE_PREFS_FILE )
    if ( raw == null || raw == "" )
        return

    local lines = SplitString( raw, "\n" )
    foreach ( line in lines )
    {
        if ( line.len() > 0 && line.slice( line.len() - 1 ) == "\r" )
            line = line.slice( 0, line.len() - 1 )
        if ( line.len() == 0 )
            continue

        // Последний сегмент — либо "0"/"1" (новый формат), либо lang-код (старый)
        local lastColon = LastIndexOf( line, ":" )
        if ( lastColon == null || lastColon >= line.len() - 1 )
            continue

        local lastSeg = line.slice( lastColon + 1 )
        local rest    = line.slice( 0, lastColon )

        local netid   = null
        local lang    = null
        local enabled = true

        if ( lastSeg == "0" || lastSeg == "1" )
        {
            // Новый формат: netid:lang:enabled
            enabled = ( lastSeg == "1" )
            local langColon = LastIndexOf( rest, ":" )
            if ( langColon == null || langColon >= rest.len() - 1 )
                continue
            lang  = rest.slice( langColon + 1 )
            netid = rest.slice( 0, langColon )
        }
        else
        {
            // Старый формат: netid:lang
            lang  = lastSeg
            netid = rest
        }

        if ( netid == null || netid.len() == 0 || lang == null || lang.len() != 2 )
            continue

        PlayerLangPrefs[ netid ]   <- lang
        PlayerTranslateOn[ netid ] <- enabled
    }
}

hWorld.GetScriptScope()._SavePrefs <- function()
{
    local content = ""
    foreach ( netid, lang in PlayerLangPrefs )
    {
        local enabled = !( netid in PlayerTranslateOn ) || PlayerTranslateOn[ netid ]
        content += netid + ":" + lang + ":" + ( enabled ? "1" : "0" ) + "\n"
    }
    // Сохранить игроков у которых только флаг но нет явного языка
    foreach ( netid, enabled in PlayerTranslateOn )
    {
        if ( !( netid in PlayerLangPrefs ) )
            content += netid + ":" + TRANSLATE_DEFAULT_LANG + ":" + ( enabled ? "1" : "0" ) + "\n"
    }
    StringToFile( TRANSLATE_PREFS_FILE, content )
}

// Получить массив доступных языков из файла translate_langs
hWorld.GetScriptScope()._GetAvailableLangs <- function()
{
    local raw = FileToString( TRANSLATE_LANGS_FILE )
    if ( raw == null || raw == "" )
        return []
    // Убрать возможный перевод строки
    while ( raw.len() > 0 && ( raw.slice( raw.len()-1 ) == "\n" || raw.slice( raw.len()-1 ) == "\r" ) )
        raw = raw.slice( 0, raw.len()-1 )
    return SplitString( raw, "," )
}

// Строка доступных языков для вывода в чат
hWorld.GetScriptScope()._AvailableLangsStr <- function()
{
    local langs = _GetAvailableLangs()
    if ( langs.len() == 0 )
        return "—"
    local result = ""
    foreach ( i, lang in langs )
    {
        if ( i > 0 ) result += ", "
        result += lang
    }
    return result
}

hWorld.GetScriptScope()._GetPlayerLang <- function( hPlayer )
{
    local netid = hPlayer.GetNetworkIDString()
    if ( netid in PlayerLangPrefs )
        return PlayerLangPrefs[ netid ]
    return TRANSLATE_DEFAULT_LANG
}

hWorld.GetScriptScope()._IsTranslateEnabled <- function( hPlayer )
{
    local netid = hPlayer.GetNetworkIDString()
    if ( netid in PlayerTranslateOn )
        return PlayerTranslateOn[ netid ]
    return true   // по умолчанию включён
}

// Собрать языки только тех игроков у кого перевод включён
hWorld.GetScriptScope()._GetOnlineLangs <- function()
{
    local seen  = {}
    local langs = []
    local hP = Entities.FindByClassname( null, "player" )
    while ( hP != null )
    {
        if ( hP.IsValid() && _IsTranslateEnabled( hP ) )
        {
            local lang = _GetPlayerLang( hP )
            if ( !(lang in seen) )
            {
                seen[ lang ] <- true
                langs.append( lang )
            }
        }
        hP = Entities.FindByClassname( hP, "player" )
    }
    if ( langs.len() == 0 )
        langs.append( TRANSLATE_DEFAULT_LANG )
    return langs
}

// ── Отправить первый элемент очереди переводчику ──────────────────────────────

hWorld.GetScriptScope()._TranslateSendNext <- function()
{
    if ( TranslateQueue.len() == 0 )
    {
        bTranslateWaiting = false
        return
    }

    local entry = TranslateQueue[0]
    bTranslateWaiting = true
    fTranslateSentAt  = Time()

    local langStr = ""
    foreach ( i, lang in entry.langs )
    {
        if ( i > 0 ) langStr += ","
        langStr += lang
    }

    StringToFile( TRANSLATE_REQ_FILE, entry.id + "|" + entry.original + "|" + langStr )
}

// ── Think: опрос ответа каждые TRANSLATE_POLL_SEC секунд ─────────────────────

hWorld.GetScriptScope()._TranslateThink <- function()
{
    if ( !bTranslateWaiting )
        return TRANSLATE_POLL_SEC

    if ( Time() - fTranslateSentAt > TRANSLATE_TIMEOUT_SEC )
    {
        local entry = TranslateQueue[0]
        ClientPrint( null, 3,
            TextColor( 200, 80, 80 ) + "[Translate] Timeout: " +
            TextColor( 180, 180, 180 ) + entry.original )
        TranslateQueue.remove( 0 )
        _TranslateSendNext()
        return TRANSLATE_POLL_SEC
    }

    local resp = FileToString( TRANSLATE_RESP_FILE )
    if ( resp == "" || resp == null || resp == "0" )
        return TRANSLATE_POLL_SEC

    local segments = SplitString( resp, "|" )
    if ( segments.len() < 2 )
        return TRANSLATE_POLL_SEC

    local respId = segments[0]

    if ( TranslateQueue.len() == 0 || TranslateQueue[0].id != respId )
        return TRANSLATE_POLL_SEC

    local entry = TranslateQueue[0]

    local translations = {}
    for ( local i = 1; i < segments.len(); i++ )
    {
        local seg      = segments[i]
        local colonIdx = seg.find( ":" )
        if ( colonIdx == null )
            continue
        translations[ seg.slice( 0, colonIdx ) ] <- seg.slice( colonIdx + 1 )
    }

    local hP = Entities.FindByClassname( null, "player" )
    while ( hP != null )
    {
        if ( hP.IsValid() && _IsTranslateEnabled( hP ) )
        {
            local lang = _GetPlayerLang( hP )

            local translated = null
            if ( lang in translations )
                translated = translations[ lang ]
            else if ( "en" in translations )
                translated = translations[ "en" ]
            else
                foreach ( k, v in translations ) { translated = v; break }

            if ( translated == null )
                translated = entry.original

            ClientPrint( hP, 3,
                TextColor( 100, 160, 255 ) + "[" + entry.name + "]: " +
                TextColor( 255, 220, 80  ) + translated )
        }
        hP = Entities.FindByClassname( hP, "player" )
    }

    StringToFile( TRANSLATE_RESP_FILE, "0" )
    TranslateQueue.remove( 0 )
    _TranslateSendNext()

    return TRANSLATE_POLL_SEC
}

AddThinkToEnt( hWorld, "_TranslateThink" )

// ── Сброс IPC-файлов при старте ──────────────────────────────────────────────
// Обнуляем чтобы сообщения из предыдущей сессии не попали в чат

StringToFile( TRANSLATE_REQ_FILE,  "0" )
StringToFile( TRANSLATE_RESP_FILE, "0" )

// ── Загрузить предпочтения при старте ────────────────────────────────────────

hWorld.GetScriptScope()._LoadPrefs()

// ── Приветственное сообщение при подключении игрока ──────────────────────────

function OnGameEvent_player_activate( params )
{
    local hPlayer = GetPlayerFromUserID( params["userid"] )
    if ( !hPlayer )
        return

    local sc      = hWorld.GetScriptScope()
    local netid   = hPlayer.GetNetworkIDString()
    local lang    = sc._GetPlayerLang( hPlayer )
    local enabled = sc._IsTranslateEnabled( hPlayer )

    local status = enabled
        ? ( TextColor( 100, 200, 100 ) + "включён" + TextColor( 180, 180, 180 ) + ", язык: " + TextColor( 255, 220, 80 ) + lang )
        : ( TextColor( 200, 80, 80  ) + "отключён" )

    ClientPrint( hPlayer, 3,
        TextColor( 100, 160, 255 ) + "[Translate] " +
        TextColor( 180, 180, 180 ) + "Переводчик чата " + status )
    ClientPrint( hPlayer, 3,
        TextColor( 180, 180, 180 ) + "  Языки: " +
        TextColor( 255, 220, 80  ) + sc._AvailableLangsStr() )
    ClientPrint( hPlayer, 3,
        TextColor( 140, 140, 140 ) + "  !lang <код>       — сменить язык" )
    ClientPrint( hPlayer, 3,
        TextColor( 140, 140, 140 ) + "  !translate on/off — вкл/выкл перевод  |  !langs — список языков" )
}

// ── Перехват чата ─────────────────────────────────────────────────────────────

function OnGameEvent_player_say( params )
{
    local hPlayer = GetPlayerFromUserID( params["userid"] )
    if ( !hPlayer )
        return

    local text = params["text"]
    if ( text.len() == 0 )
        return

    local sc    = hWorld.GetScriptScope()
    local netid = hPlayer.GetNetworkIDString()

    // Команда !langs — список доступных языков
    if ( text == "!langs" )
    {
        ClientPrint( hPlayer, 3,
            TextColor( 100, 160, 255 ) + "[Translate] Доступные языки: " +
            TextColor( 255, 220, 80  ) + sc._AvailableLangsStr() )
        return
    }

    // Команда !translate on / !translate off
    if ( text == "!translate on" || text == "!translate off" )
    {
        local enable = ( text == "!translate on" )
        sc.PlayerTranslateOn[ netid ] <- enable
        // Если нет сохранённого языка — записать дефолтный чтобы было что сохранять
        if ( !( netid in sc.PlayerLangPrefs ) )
            sc.PlayerLangPrefs[ netid ] <- TRANSLATE_DEFAULT_LANG
        sc._SavePrefs()
        ClientPrint( hPlayer, 3,
            TextColor( 100, 160, 255 ) + "[Translate] " +
            ( enable
                ? TextColor( 100, 200, 100 ) + "Перевод включён"
                : TextColor( 200, 80,  80  ) + "Перевод отключён" ) )
        return
    }

    // Команда !lang <код>
    if ( text.len() >= 6 && text.slice( 0, 6 ) == "!lang " )
    {
        local lang = text.slice( 6 ).tolower()
        if ( lang.len() == 2 )
        {
            sc.PlayerLangPrefs[ netid ] <- lang
            // Включить перевод если был выключен
            sc.PlayerTranslateOn[ netid ] <- true
            sc._SavePrefs()
            ClientPrint( hPlayer, 3,
                TextColor( 100, 200, 100 ) + "[Translate] Язык установлен: " + lang )
        }
        else
        {
            ClientPrint( hPlayer, 3,
                TextColor( 200, 80, 80 ) + "[Translate] Использование: !lang <код>  (например: !lang ru)" )
        }
        return
    }

    // Пропускаем прочие команды
    local firstChar = text.slice( 0, 1 )
    if ( firstChar == "!" || firstChar == "/" || firstChar == "\\" || firstChar == "&" || firstChar == "?" )
        return

    sc.nTranslateNextId += 1
    sc.TranslateQueue.append( {
        id       = sc.nTranslateNextId.tostring(),
        name     = hPlayer.GetPlayerName(),
        original = text,
        langs    = sc._GetOnlineLangs()
    } )

    if ( !sc.bTranslateWaiting )
        sc._TranslateSendNext()
}

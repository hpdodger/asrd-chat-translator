// Chat Translator Challenge
// Переводит сообщения чата через companion Node.js процесс и LibreTranslate
//
// Требования:
//   1. Запущен LibreTranslate: docker run -p 5000:5000 libretranslate/libretranslate
//   2. Запущен переводчик:     node chat_translator/translator.js
//   3. Задана переменная GAME_DATA_PATH в chat_translator/.env
//
// Формат IPC файлов (папка GAME_DATA_PATH):
//   translate_req  — запрос:  "<id>|<текст сообщения>"
//   translate_resp — ответ:   "<id>|<переведённый текст>"

const TRANSLATE_REQ_FILE    = "translate_req"
const TRANSLATE_RESP_FILE   = "translate_resp"
const TRANSLATE_POLL_SEC    = 0.5
const TRANSLATE_TIMEOUT_SEC = 8.0

// Всё состояние — в scope сущности (паттерн из some_code.nut)
// Тогда _TranslateThink и _TranslateSendNext обращаются к ним через this напрямую
hWorld <- Entities.FindByClassname( null, "worldspawn" )
hWorld.ValidateScriptScope()
hWorld.GetScriptScope().nTranslateNextId  <- 0
hWorld.GetScriptScope().TranslateQueue    <- []
hWorld.GetScriptScope().bTranslateWaiting <- false
hWorld.GetScriptScope().fTranslateSentAt  <- 0.0

// -------------------------------------------------------------------------
// Отправить первый элемент очереди переводчику
// Вызывается из scope сущности — все переменные доступны через this
// -------------------------------------------------------------------------
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

    StringToFile( TRANSLATE_REQ_FILE, entry.id + "|" + entry.original )
}

// -------------------------------------------------------------------------
// Think: опрос ответа каждые TRANSLATE_POLL_SEC секунд
// -------------------------------------------------------------------------
hWorld.GetScriptScope()._TranslateThink <- function()
{
    if ( !bTranslateWaiting )
        return TRANSLATE_POLL_SEC

    // Таймаут: если переводчик не отвечает
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

    local sepIdx = resp.find( "|" )
    if ( sepIdx == null )
        return TRANSLATE_POLL_SEC

    local respId     = resp.slice( 0, sepIdx )
    local translated = resp.slice( sepIdx + 1 )

    if ( TranslateQueue.len() > 0 && TranslateQueue[0].id == respId )
    {
        local entry = TranslateQueue[0]

        if ( translated != entry.original && translated != "" )
        {
            ClientPrint( null, 3,
                TextColor( 100, 160, 255 ) + "[" + entry.name + "] " +
                TextColor( 200, 200, 200 ) + entry.original +
                TextColor( 120, 120, 120 ) + " -> " +
                TextColor( 255, 220, 80  ) + translated )
        }

        StringToFile( TRANSLATE_RESP_FILE, "0" )
        TranslateQueue.remove( 0 )
        _TranslateSendNext()
    }

    return TRANSLATE_POLL_SEC
}
AddThinkToEnt( hWorld, "_TranslateThink" )

// -------------------------------------------------------------------------
// Перехват чата — выполняется в глобальном scope,
// обращение к состоянию через hWorld.GetScriptScope()
// -------------------------------------------------------------------------
function OnGameEvent_player_say( params )
{
    local hPlayer = GetPlayerFromUserID( params["userid"] )
    if ( !hPlayer )
        return

    local text = params["text"]
    if ( text.len() == 0 )
        return

    // Пропускаем команды
    local firstChar = text.slice( 0, 1 )
    if ( firstChar == "!" || firstChar == "/" || firstChar == "\\" || firstChar == "&" || firstChar == "?" )
        return

    local sc = hWorld.GetScriptScope()

    sc.nTranslateNextId += 1
    sc.TranslateQueue.append( {
        id       = sc.nTranslateNextId.tostring(),
        name     = hPlayer.GetPlayerName(),
        original = text
    } )

    if ( !sc.bTranslateWaiting )
        sc._TranslateSendNext()
}

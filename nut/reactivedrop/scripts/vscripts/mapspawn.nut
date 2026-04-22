// Chat Translator — loaded at the start of any map (including lobby)
//
// Requirements:
//   docker compose up --build  (from the asrd-chat-translator root)
//   HOST_GAME_DATA_PATH set in .env

// Guard against double initialization (in case both files are loaded)
if ( "ChatTranslateLoaded" in getroottable() )
    return;
getroottable().ChatTranslateLoaded <- true;

printl( "─────────────────────────────────────────" );
printl( "  Chat Translator  v1.0" );
printl( "  Author: https://steamcommunity.com/id/w_asd/" );
printl( "─────────────────────────────────────────" );

hWorld <- Entities.FindByClassname( null, "worldspawn" );
hWorld.ValidateScriptScope();
IncludeScript( "chat_translate", hWorld.GetScriptScope() );

// ── Event handlers ────────────────────────────────────────────────────────────
// Thin wrappers — all logic lives in chat_translate.nut (entity scope).
// Keeping mapspawn.nut minimal reduces conflicts when merging with other addons.
// hWorld is in the root table so it's accessible from any function scope.

OnGameEvent_player_activate <- function( params ) {
    local hPlayer = GetPlayerFromUserID( params[ "userid" ] );
    if ( !hPlayer ) return;
    hWorld.GetScriptScope()._OnPlayerActivate( hPlayer );
}

OnGameEvent_player_say <- function( params ) {
    hWorld.GetScriptScope()._OnPlayerSay( params );
}

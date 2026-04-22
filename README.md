# asrd-chat-translator

## Table of Contents
- [How it works](#how-it-works)
- [Game script installation](#game-script-installation)
- [Script structure](#script-structure)
- [Configuration](#configuration)
- [Running the service (Docker)](#running-the-service-docker)
- [Running the service (without Docker)](#running-the-service-without-docker)
- [In-game chat commands](#in-game-chat-commands)
- [Project structure](#project-structure)
- [Adding a custom translator](#adding-a-custom-translator)

## How it works

```
Game (Squirrel)  →  translate_req  →  Node.js  →  Translator Instance
                 ←  translate_resp  ←
```

The Squirrel script intercepts chat messages and writes them to a file.  
The Node.js service reads the file, sends the text to a Translator Instance, and writes the result back.  
Each player receives the translation in their own language.

---

↑ [Table of Contents](#table-of-contents)

## Game script installation

Copy the contents of `nut/reactivedrop/` into the game's mod folder:

**Windows:**
```
C:\...\Steam\steamapps\common\Alien Swarm Reactive Drop\reactivedrop\
```
**Linux:**
```
~/.steam/steam/steamapps/common/Alien Swarm Reactive Drop/reactivedrop/
```

The following files are copied:
- `scripts/vscripts/mapspawn.nut` — minimal lobby script (loaded on every map)
- `scripts/vscripts/chat_translate.nut` — core module with all translator logic
- `scripts/vscripts/challenge_chat_translate.nut` — mission script (loaded via challenge)
- `resource/challenges/chat_translate.txt` — challenge descriptor
- `cfg/autoexec.cfg` — enables auto-loading of `mapspawn.nut`

> **If `mapspawn.nut` already exists** — append the contents of the new `mapspawn.nut` to the end of the existing file, removing the `ChatTranslateLoaded` guard line. Thanks to the modular structure, the addition is minimal (~15 lines).
>
> **If `cfg/autoexec.cfg` already exists** — append `sv_mapspawn_nut_exec 1` to the end of the existing file.

---

↑ [Table of Contents](#table-of-contents)

## Script structure

There are three VScript files:

| File | Role |
|------|------|
| `chat_translate.nut` | Core module — all logic, state, and chat commands |
| `mapspawn.nut` | Minimal loader for the lobby; loads `chat_translate.nut` into the worldspawn entity scope and registers two thin event handler wrappers |
| `challenge_chat_translate.nut` | Loaded during missions via the challenge system; the built-in `ChatTranslateLoaded` guard prevents double initialization if `mapspawn.nut` already ran |

`mapspawn.nut` is disabled in ASRD by default (cvar `sv_mapspawn_nut_exec 0`). The `cfg/autoexec.cfg` file enables it, after which it is loaded on every map including the lobby (`rd_lobby`).

---

↑ [Table of Contents](#table-of-contents)

## Configuration

All application settings are stored in a single file `app-config.json`.

```bash
cp app-config.example.json app-config.json
```

`app-config.json` fields:

| Field | Description |
|-------|-------------|
| `gameDataPath` | Path to the game's vscripts folder (for standalone; overridden automatically in Docker) |
| `targetLang` | Default translation language if the player has not set their own |
| `translatorConfig.translatorId` | Translator implementation ID (currently only `"libre"`) |
| `translatorConfig.url` | LibreTranslate server URL |
| `translatorConfig.apiKey` | LibreTranslate API key (leave empty if no auth required) |
| `translatorConfig.loadOnly` | List of languages to load and use |

Language codes (ISO 639-1): `en` English, `ru` Russian, `zh` Chinese, `de` German, `fr` French, `es` Spanish, `pt` Portuguese, `ar` Arabic, `ja` Japanese, `ko` Korean.

> `en` is required — used as a fallback if the requested language is unavailable.

---

↑ [Table of Contents](#table-of-contents)

## Running the service (Docker)

### 1. Create `app-config.json`

```bash
cp app-config.example.json app-config.json
```

`translatorConfig.url` already contains the correct value `"http://libretranslate:5000"` — the service name within the Docker network.  
`gameDataPath` is not relevant for Docker — it is automatically overridden by `GAME_DATA_PATH=/gamedata`.

### 2. Create `.env`

```bash
cp .env.example .env
```

Open `.env` and set the variables:

```ini
# Path to the game's vscripts folder on the host
HOST_GAME_DATA_PATH=D:\soft\Steam\steamapps\common\Alien Swarm Reactive Drop\reactivedrop\save\vscripts

# Languages to load in LibreTranslate — must match loadOnly in app-config.json
LT_LOAD_ONLY=en,ru,zh,de
```

### 3. Start

```bash
docker compose up --build
```

On first run LibreTranslate will download language models — this takes a few minutes.  
The translator service starts automatically once LibreTranslate is ready (healthcheck).  
Models are stored in a Docker volume and are not re-downloaded on subsequent runs.

### 4. Stop

```bash
docker compose down
```

---

↑ [Table of Contents](#table-of-contents)

## Running the service (without Docker)

Requirements: Node.js 20+, a running LibreTranslate instance.

### 1. Create `node/app-config.json`

```bash
cp app-config.example.json node/app-config.json
```

Set the real `gameDataPath` and change `translatorConfig.url` to `"http://localhost:5000"` (for running without Docker).

### 2. Start LibreTranslate separately

```bash
docker run -p 5000:5000 libretranslate/libretranslate --load-only en,ru,zh,de
```

### 3. Start the service

```bash
cd node
npm install
npm run build
npm start
```

---

↑ [Table of Contents](#table-of-contents)

## In-game chat commands

| Command | Description |
|---------|-------------|
| `!ct_lang <code>` | Set your translation language. Example: `!ct_lang ru`, `!ct_lang zh` |
| `!ct_translate on` | Enable translation (enabled by default) |
| `!ct_translate off` | Disable translation |
| `!ct_langs` | Show the list of languages available on the server |
| `!ct_help` | Show this help message |

When joining a lobby or game each player sees their current status, active language, and the list of available languages in chat.  
Preferences are saved between sessions. Translation is enabled by default; the default language is English.

> **Note:** the message sender does not receive the translation in chat to avoid duplicating their own message. Instead, all translations are printed to their developer console (`~`) in the form `[Translate] <lang>: <text>`.

---

↑ [Table of Contents](#table-of-contents)

## Project structure

```
asrd-chat-translator/
├── app-config.example.json       # Application config template
├── app-config.json               # Real config (gitignored)
├── .env.example                  # Docker environment template
├── .env                          # Docker environment (gitignored)
├── docker-compose.yml            # Runs LibreTranslate + Node.js service
│
├── node/                         # Node.js service (TypeScript)
│   ├── src/
│   │   ├── index.ts              # Entry point: watcher, queue, startup
│   │   ├── app-config.ts         # Load and validate app-config.json
│   │   ├── translation-files.ts  # Read/write IPC files
│   │   ├── queue.ts              # Async translation queue
│   │   └── translators/
│   │       ├── base-translator.ts    # Abstract class + interfaces
│   │       └── libre-translator.ts   # LibreTranslate implementation
│   ├── dist/                     # Compiled JS (gitignored)
│   ├── Dockerfile
│   ├── tsconfig.json
│   └── package.json
│
└── nut/reactivedrop/             # Copied into the game folder
    ├── cfg/
    │   └── autoexec.cfg
    ├── scripts/vscripts/
    │   ├── mapspawn.nut              — minimal loader + event handler wrappers
    │   ├── chat_translate.nut        — core module (all logic, state, commands)
    │   └── challenge_chat_translate.nut
    └── resource/challenges/
        └── chat_translate.txt
```

IPC files are created automatically in the `gameDataPath` folder:

| File | Description |
|------|-------------|
| `translate_req` | Request: `id\|text\|lang1,lang2,...` |
| `translate_resp` | Response: `id\|lang1:translation1\|lang2:translation2\|...` |
| `translate_langs` | Available language list (updated on startup) |
| `translate_prefs` | Player language preferences |

---

↑ [Table of Contents](#table-of-contents)

## Adding a custom translator

The service supports plugging in third-party implementations without rebuilding the project.

1. Create a file exporting a class with `public static readonly id = "my-translator"` that implements `IBaseTranslator` from `base-translator.ts`
2. Place the compiled `.js` file in `dist/translators/`
3. Set `translatorConfig.translatorId: "my-translator"` in `app-config.json`

On startup the service automatically scans the `translators/` folder and picks the implementation by matching `id`.

---

↑ [Table of Contents](#table-of-contents)
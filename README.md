# asrd-chat-translator

Автоматический перевод игрового чата в Alien Swarm: Reactive Drop.  
Работает в лобби и во время миссий.

## Как это работает

```
Игра (Squirrel)  →  translate_req  →  Node.js  →  LibreTranslate
                 ←  translate_resp  ←
```

Squirrel-скрипт перехватывает сообщения чата и записывает их в файл.  
Node.js-сервис читает файл, отправляет текст в LibreTranslate, записывает результат обратно.  
Каждый игрок получает перевод на своём языке.

---

## Установка игрового скрипта

Скопировать содержимое папки `nut/reactivedrop/` в папку мода игры:

**Windows:**
```
C:\...\Steam\steamapps\common\Alien Swarm Reactive Drop\reactivedrop\
```
**Linux:**
```
~/.steam/steam/steamapps/common/Alien Swarm Reactive Drop/reactivedrop/
```

Копируются следующие файлы:
- `scripts/vscripts/mapspawn.nut` — скрипт для лобби (загружается на каждой карте)
- `scripts/vscripts/challenge_chat_translate.nut` — скрипт для миссий (загружается через challenge)
- `resource/challenges/chat_translate.txt` — описание challenge
- `cfg/autoexec.cfg` — включает автозагрузку `mapspawn.nut`

> **Если `mapspawn.nut` уже существует** — добавить содержимое файла в конец существующего, убрав строку с guard-проверкой `ChatTranslateLoaded`.
>
> **Если `cfg/autoexec.cfg` уже существует** — добавить строку `sv_mapspawn_nut_exec 1` в конец существующего файла.

### Почему два скрипта

`mapspawn.nut` в ASRD по умолчанию отключён (конвар `sv_mapspawn_nut_exec 0`). Файл `cfg/autoexec.cfg` включает его, после чего скрипт загружается на каждой карте включая лобби (`rd_lobby`). Во время миссий дополнительно срабатывает `challenge_chat_translate.nut` — встроенный guard предотвращает двойную инициализацию.

---

## Запуск сервиса (Docker)

### 1. Создать `.env`

```bash
cp .env.example .env
```

Открыть `.env` и задать переменные:

```ini
# Путь к папке скриптов игры на хосте
HOST_GAME_DATA_PATH=D:\soft\Steam\steamapps\common\Alien Swarm Reactive Drop\reactivedrop\save\vscripts

# Языки для загрузки в LibreTranslate (через запятую)
# en обязателен — используется как fallback
LT_LOAD_ONLY=en,ru

# API ключ LibreTranslate (оставить пустым если без авторизации)
LIBRETRANSLATE_API_KEY=
```

Коды языков (ISO 639-1): `en` английский, `ru` русский, `zh` китайский, `de` немецкий, `fr` французский, `es` испанский, `pt` португальский, `ar` арабский, `ja` японский, `ko` корейский.

### 2. Запустить

```bash
docker compose up --build
```

При первом запуске LibreTranslate скачает языковые модели — это занимает несколько минут.  
Модели сохраняются в Docker volume и при следующих запусках не скачиваются повторно.

### 3. Остановить

```bash
docker compose down
```

---

## Запуск сервиса (без Docker)

Требования: Node.js 18+, запущенный LibreTranslate.

```bash
cd node
cp .env.example .env
# Заполнить GAME_DATA_PATH в .env
npm install
node translator.js
```

LibreTranslate запустить отдельно:

```bash
docker run -p 5000:5000 libretranslate/libretranslate --load-only en,ru
```

---

## Команды в игровом чате

| Команда | Описание |
|---------|----------|
| `!lang <код>` | Установить язык перевода для себя. Пример: `!lang ru`, `!lang zh` |
| `!translate on` | Включить перевод (включён по умолчанию) |
| `!translate off` | Отключить перевод — сообщения чата переводиться не будут |
| `!langs` | Показать список языков, доступных на сервере |

При подключении к лобби или игре каждый игрок видит в чате:
- текущий статус переводчика (включён/выключен) и активный язык
- список доступных языков
- напоминание о командах

Предпочтения сохраняются между сессиями.  
По умолчанию перевод включён для всех, язык — английский (`en`).

---

## Структура файлов

```
asrd-chat-translator/
├── .env.example                          # Шаблон конфига для Docker
├── docker-compose.yml                    # Запуск LibreTranslate + Node.js
├── node/
│   ├── Dockerfile
│   ├── translator.js                     # Node.js сервис
│   ├── package.json
│   └── .env.example                      # Шаблон конфига для standalone
└── nut/reactivedrop/                     # Копируется в папку игры
    ├── cfg/
    │   └── autoexec.cfg                  # sv_mapspawn_nut_exec 1
    ├── scripts/vscripts/
    │   ├── mapspawn.nut                  # Скрипт для лобби (все карты)
    │   └── challenge_chat_translate.nut  # Скрипт для миссий (через challenge)
    └── resource/challenges/
        └── chat_translate.txt
```

IPC-файлы создаются автоматически в папке `GAME_DATA_PATH`:

| Файл | Описание |
|------|----------|
| `translate_req` | Запрос на перевод: `id\|текст\|lang1,lang2,...` |
| `translate_resp` | Ответ: `id\|lang1:перевод1\|lang2:перевод2\|...` |
| `translate_prefs` | Языковые предпочтения игроков |

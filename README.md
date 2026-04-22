# asrd-chat-translator

Автоматический перевод игрового чата в Alien Swarm: Reactive Drop.  
Работает в лобби и во время миссий.

## Как это работает

```
Игра (Squirrel)  →  translate_req  →  Node.js  →  Translator Instance
                 ←  translate_resp  ←
```

Squirrel-скрипт перехватывает сообщения чата и записывает их в файл.  
Node.js-сервис читает файл, отправляет текст в Translator Instance, записывает результат обратно.  
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

## Конфигурация

Все настройки приложения хранятся в одном файле `app-config.json`.

```bash
cp app-config.example.json app-config.json
```

Поля `app-config.json`:

| Поле | Описание |
|------|----------|
| `gameDataPath` | Путь к папке vscripts игры (для standalone; в Docker перекрывается автоматически) |
| `targetLang` | Язык перевода по умолчанию, если игрок не выбрал свой |
| `translatorConfig.translatorId` | ID реализации переводчика (сейчас только `"libre"`) |
| `translatorConfig.url` | URL LibreTranslate сервера |
| `translatorConfig.apiKey` | API-ключ LibreTranslate (оставить пустым если без авторизации) |
| `translatorConfig.loadOnly` | Список языков для загрузки и использования |

Коды языков (ISO 639-1): `en` английский, `ru` русский, `zh` китайский, `de` немецкий, `fr` французский, `es` испанский, `pt` португальский, `ar` арабский, `ja` японский, `ko` корейский.

> `en` обязателен — используется как fallback если запрошенный язык недоступен.

---

## Запуск сервиса (Docker)

### 1. Создать `app-config.json`

```bash
cp app-config.example.json app-config.json
```

`translatorConfig.url` уже содержит правильное значение `"http://libretranslate:5000"` — имя сервиса внутри Docker-сети.  
`gameDataPath` для Docker не важен — он перекрывается автоматически переменной `GAME_DATA_PATH=/gamedata`.

### 2. Создать `.env`

```bash
cp .env.example .env
```

Открыть `.env` и задать переменные:

```ini
# Путь к папке vscripts игры на хосте
HOST_GAME_DATA_PATH=D:\soft\Steam\steamapps\common\Alien Swarm Reactive Drop\reactivedrop\save\vscripts

# Языки для загрузки в LibreTranslate — должно совпадать с loadOnly в app-config.json
LT_LOAD_ONLY=en,ru,zh,de
```

### 3. Запустить

```bash
docker compose up --build
```

При первом запуске LibreTranslate скачает языковые модели — это занимает несколько минут.  
Сервис-переводчик запустится автоматически после того как LibreTranslate будет готов (healthcheck).  
Модели сохраняются в Docker volume и при следующих запусках не скачиваются повторно.

### 4. Остановить

```bash
docker compose down
```

---

## Запуск сервиса (без Docker)

Требования: Node.js 20+, запущенный LibreTranslate.

### 1. Создать `node/app-config.json`

```bash
cp app-config.example.json node/app-config.json
```

Указать реальный `gameDataPath` и вернуть `translatorConfig.url: "http://localhost:5000"` (для запуска без Docker).

### 2. Запустить LibreTranslate отдельно

```bash
docker run -p 5000:5000 libretranslate/libretranslate --load-only en,ru,zh,de
```

### 3. Запустить сервис

```bash
cd node
npm install
npm run build
npm start
```

---

## Команды в игровом чате

| Команда | Описание |
|---------|----------|
| `!lang <код>` | Установить язык перевода для себя. Пример: `!lang ru`, `!lang zh` |
| `!translate on` | Включить перевод (включён по умолчанию) |
| `!translate off` | Отключить перевод |
| `!langs` | Показать список языков, доступных на сервере |

При подключении к лобби или игре каждый игрок видит в чате текущий статус, активный язык и список доступных языков.  
Предпочтения сохраняются между сессиями. По умолчанию перевод включён, язык — английский.

---

## Структура проекта

```
asrd-chat-translator/
├── app-config.example.json       # Шаблон конфига приложения
├── app-config.json               # Реальный конфиг (gitignored)
├── .env.example                  # Шаблон переменных для Docker
├── .env                          # Переменные для Docker (gitignored)
├── docker-compose.yml            # Запуск LibreTranslate + Node.js сервиса
│
├── node/                         # Node.js сервис (TypeScript)
│   ├── src/
│   │   ├── index.ts              # Точка входа: watcher, очередь, запуск
│   │   ├── app-config.ts         # Загрузка и валидация app-config.json
│   │   ├── translation-files.ts  # Чтение/запись IPC-файлов
│   │   ├── queue.ts              # Асинхронная очередь переводов
│   │   └── translators/
│   │       ├── base-translator.ts    # Абстрактный класс + интерфейсы
│   │       └── libre-translator.ts   # Реализация для LibreTranslate
│   ├── dist/                     # Скомпилированный JS (gitignored)
│   ├── Dockerfile
│   ├── tsconfig.json
│   └── package.json
│
└── nut/reactivedrop/             # Копируется в папку игры
    ├── cfg/
    │   └── autoexec.cfg
    ├── scripts/vscripts/
    │   ├── mapspawn.nut
    │   └── challenge_chat_translate.nut
    └── resource/challenges/
        └── chat_translate.txt
```

IPC-файлы создаются автоматически в папке `gameDataPath`:

| Файл | Описание |
|------|----------|
| `translate_req` | Запрос: `id\|текст\|lang1,lang2,...` |
| `translate_resp` | Ответ: `id\|lang1:перевод1\|lang2:перевод2\|...` |
| `translate_langs` | Список доступных языков (обновляется при старте) |
| `translate_prefs` | Языковые предпочтения игроков |

---

## Добавление своего переводчика

Сервис поддерживает подключение сторонних реализаций без пересборки проекта.

1. Создать файл, экспортирующий класс с `public static readonly id = "my-translator"` и реализующий `IBaseTranslator` из `base-translator.ts`
2. Положить скомпилированный `.js` файл в `dist/translators/`
3. В `app-config.json` указать `translatorConfig.translatorId: "my-translator"`

При старте сервис автоматически сканирует папку `translators/` и выбирает реализацию по совпадению `id`.

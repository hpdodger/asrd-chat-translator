/**
 * ASRD Chat Translator — companion процесс для challenge_chat_translate.nut
 *
 * Слушает файл translate_req в папке игры, переводит текст через LibreTranslate,
 * записывает результат в translate_resp.
 *
 * Запуск:
 *   npm install
 *   cp .env.example .env   # и заполнить GAME_DATA_PATH
 *   node translator.js
 */

require('dotenv').config();
const path    = require('path');
const fs      = require('fs');
const axios   = require('axios');
const chokidar = require('chokidar');

// ── Конфиг ──────────────────────────────────────────────────────────────────

const GAME_DATA_PATH       = process.env.GAME_DATA_PATH;
const LIBRETRANSLATE_URL   = (process.env.LIBRETRANSLATE_URL   || 'http://localhost:5000').replace(/\/$/, '');
const TARGET_LANG          = process.env.TARGET_LANG           || 'en';
const LIBRETRANSLATE_API_KEY = process.env.LIBRETRANSLATE_API_KEY || '';

if (!GAME_DATA_PATH) {
    console.error('[ERROR] GAME_DATA_PATH не задан в .env файле');
    console.error('        Скопируйте .env.example в .env и заполните путь к папке игры');
    process.exit(1);
}

const REQ_FILE  = path.join(GAME_DATA_PATH, 'translate_req');
const RESP_FILE = path.join(GAME_DATA_PATH, 'translate_resp');

console.log(`[Translator] Старт`);
console.log(`[Translator] Папка игры:  ${GAME_DATA_PATH}`);
console.log(`[Translator] LibreTranslate: ${LIBRETRANSLATE_URL}`);
console.log(`[Translator] Целевой язык: ${TARGET_LANG}`);
console.log(`[Translator] Слежу за: ${REQ_FILE}`);

// ── Очередь ──────────────────────────────────────────────────────────────────

const queue = [];       // { id, text }
let busy    = false;

async function processNext() {
    if (busy || queue.length === 0) return;
    busy = true;

    const { id, text } = queue.shift();
    console.log(`[Translator] Перевожу [${id}]: ${text}`);

    try {
        const translated = await translate(text);
        console.log(`[Translator] Результат [${id}]: ${translated}`);
        fs.writeFileSync(RESP_FILE, `${id}|${translated}`, 'utf8');
    } catch (err) {
        console.error(`[Translator] Ошибка перевода [${id}]:`, err.message);
        // Записываем оригинал как fallback чтобы Squirrel не завис
        fs.writeFileSync(RESP_FILE, `${id}|${text}`, 'utf8');
    }

    busy = false;
    processNext();
}

// ── LibreTranslate ────────────────────────────────────────────────────────────

async function translate(text) {
    const body = {
        q:      text,
        source: 'auto',
        target: TARGET_LANG,
        format: 'text',
    };
    if (LIBRETRANSLATE_API_KEY) {
        body.api_key = LIBRETRANSLATE_API_KEY;
    }

    const response = await axios.post(`${LIBRETRANSLATE_URL}/translate`, body, {
        timeout: 7000,
        headers: { 'Content-Type': 'application/json' },
    });

    return response.data.translatedText || text;
}

// ── Чтение запроса ────────────────────────────────────────────────────────────

let lastReqId = null;    // не обрабатывать один и тот же запрос дважды

function handleReqFile(filePath) {
    let raw;
    try {
        raw = fs.readFileSync(filePath, 'utf8').trim();
    } catch {
        return;
    }

    if (!raw || raw === '0') return;

    const pipeIdx = raw.indexOf('|');
    if (pipeIdx === -1) return;

    const id   = raw.slice(0, pipeIdx);
    const text = raw.slice(pipeIdx + 1).trim();

    if (!id || !text)  return;
    if (id === lastReqId) return;   // уже обработали этот запрос

    lastReqId = id;
    queue.push({ id, text });
    processNext();
}

// ── Инициализация файлов ──────────────────────────────────────────────────────

// Создаём/обнуляем файлы если их нет
if (!fs.existsSync(REQ_FILE))  fs.writeFileSync(REQ_FILE,  '0', 'utf8');
if (!fs.existsSync(RESP_FILE)) fs.writeFileSync(RESP_FILE, '0', 'utf8');

// Проверить не лежит ли уже запрос в файле (с прошлой сессии)
handleReqFile(REQ_FILE);

// ── Watcher ───────────────────────────────────────────────────────────────────

chokidar.watch(REQ_FILE, {
    persistent:          true,
    usePolling:          true,   // надёжнее на Windows и сетевых дисках
    interval:            300,    // мс
    awaitWriteFinish:    { stabilityThreshold: 100, pollInterval: 100 },
    ignoreInitial:       false,
}).on('change', handleReqFile)
  .on('error',  err => console.error('[Watcher] Ошибка:', err));

// ── Проверка доступности LibreTranslate при старте ────────────────────────────

axios.get(`${LIBRETRANSLATE_URL}/languages`, { timeout: 5000 })
    .then(r => {
        const langs = r.data.map(l => l.code).join(', ');
        console.log(`[Translator] LibreTranslate доступен. Языки: ${langs}`);
    })
    .catch(err => {
        console.warn(`[Translator] LibreTranslate недоступен (${err.message})`);
        console.warn(`             Убедитесь что контейнер запущен: docker run -p 5000:5000 libretranslate/libretranslate`);
    });

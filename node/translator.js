/**
 * ASRD Chat Translator — companion процесс для challenge_chat_translate.nut
 *
 * Слушает файл translate_req в папке игры, переводит текст через LibreTranslate
 * на все запрошенные языки, записывает результат в translate_resp.
 *
 * Формат IPC файлов:
 *   translate_req  — запрос:  "<id>|<текст>|<lang1>,<lang2>,..."
 *   translate_resp — ответ:   "<id>|<lang1>:<перевод1>|<lang2>:<перевод2>|..."
 *
 * Запуск без Docker:
 *   npm install
 *   cp .env.example .env   # заполнить GAME_DATA_PATH
 *   node translator.js
 *
 * Запуск через Docker:
 *   cp ../.env.example ../.env   # заполнить HOST_GAME_DATA_PATH
 *   docker compose up --build
 */

require('dotenv').config();
const path     = require('path');
const fs       = require('fs');
const axios    = require('axios');
const chokidar = require('chokidar');

// ── Конфиг ──────────────────────────────────────────────────────────────────

const GAME_DATA_PATH         = process.env.GAME_DATA_PATH;
const LIBRETRANSLATE_URL     = (process.env.LIBRETRANSLATE_URL || 'http://localhost:5000').replace(/\/$/, '');
const TARGET_LANG            = process.env.TARGET_LANG || 'en';   // fallback для standalone-режима
const LIBRETRANSLATE_API_KEY = process.env.LIBRETRANSLATE_API_KEY || '';

if (!GAME_DATA_PATH) {
    console.error('[ERROR] GAME_DATA_PATH не задан в .env файле');
    console.error('        Скопируйте .env.example в .env и заполните путь к папке игры');
    process.exit(1);
}

const REQ_FILE   = path.join(GAME_DATA_PATH, 'translate_req');
const RESP_FILE  = path.join(GAME_DATA_PATH, 'translate_resp');
const LANGS_FILE = path.join(GAME_DATA_PATH, 'translate_langs');

console.log(`[Translator] Старт`);
console.log(`[Translator] Папка игры:     ${GAME_DATA_PATH}`);
console.log(`[Translator] LibreTranslate: ${LIBRETRANSLATE_URL}`);
console.log(`[Translator] Слежу за:       ${REQ_FILE}`);

// ── Очередь ──────────────────────────────────────────────────────────────────

const queue = [];   // { id, text, langs[] }
let busy    = false;

async function processNext() {
    if (busy || queue.length === 0) return;
    busy = true;

    const { id, text, langs } = queue.shift();
    console.log(`[Translator] Перевожу [${id}] → [${langs.join(',')}]: ${text}`);

    try {
        // Переводим на все языки параллельно
        const results = await Promise.all(
            langs.map(async (lang) => {
                const translated = await translateWithFallback(text, lang);
                // Пайп зарезервирован для IPC-протокола — заменяем
                return `${lang}:${translated.replace(/\|/g, ' ')}`;
            })
        );

        const responseStr = `${id}|${results.join('|')}`;
        console.log(`[Translator] Ответ   [${id}]: ${responseStr}`);
        fs.writeFileSync(RESP_FILE, responseStr, 'utf8');
    } catch (err) {
        console.error(`[Translator] Критическая ошибка [${id}]:`, err.message);
        // Fallback: для каждого языка отдаём оригинал чтобы Squirrel не завис
        const fallbacks = langs.map(lang => `${lang}:${text.replace(/\|/g, ' ')}`).join('|');
        fs.writeFileSync(RESP_FILE, `${id}|${fallbacks}`, 'utf8');
    }

    busy = false;
    processNext();
}

// ── LibreTranslate ────────────────────────────────────────────────────────────

async function translateToLang(text, targetLang) {
    const body = {
        q:      text,
        source: 'auto',
        target: targetLang,
        format: 'text',
    };
    if (LIBRETRANSLATE_API_KEY) body.api_key = LIBRETRANSLATE_API_KEY;

    const response = await axios.post(`${LIBRETRANSLATE_URL}/translate`, body, {
        timeout: 7000,
        headers: { 'Content-Type': 'application/json' },
    });

    return response.data.translatedText || text;
}

// Если запрошенный язык недоступен в LT — пробуем en, затем оригинал
async function translateWithFallback(text, targetLang) {
    try {
        return await translateToLang(text, targetLang);
    } catch (err) {
        console.warn(`[Translator] Язык '${targetLang}' недоступен: ${err.message}`);
        if (targetLang !== 'en') {
            try {
                return await translateToLang(text, 'en');
            } catch (fallbackErr) {
                console.warn(`[Translator] Fallback 'en' тоже недоступен: ${fallbackErr.message}`);
            }
        }
        return text;
    }
}

// ── Чтение запроса ────────────────────────────────────────────────────────────

let lastReqId = null;

function handleReqFile(filePath) {
    let raw;
    try {
        raw = fs.readFileSync(filePath, 'utf8').trim();
    } catch {
        return;
    }

    if (!raw || raw === '0') return;

    // Формат: id|text|lang1,lang2,...
    const firstPipe  = raw.indexOf('|');
    const secondPipe = raw.indexOf('|', firstPipe + 1);

    if (firstPipe === -1 || secondPipe === -1) return;

    const id    = raw.slice(0, firstPipe);
    const text  = raw.slice(firstPipe + 1, secondPipe).trim();
    const langs = raw.slice(secondPipe + 1).split(',').map(l => l.trim()).filter(Boolean);

    if (!id || !text) return;
    if (id === lastReqId) return;   // уже обработали этот запрос

    // Fallback для старого формата без списка языков
    if (langs.length === 0) langs.push(TARGET_LANG);

    lastReqId = id;
    queue.push({ id, text, langs });
    processNext();
}

// ── Инициализация файлов ──────────────────────────────────────────────────────

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
        const codes = r.data.map(l => l.code);
        console.log(`[Translator] LibreTranslate доступен. Языки: ${codes.join(', ')}`);
        fs.writeFileSync(LANGS_FILE, codes.join(','), 'utf8');
    })
    .catch(err => {
        console.warn(`[Translator] LibreTranslate недоступен (${err.message})`);
        console.warn(`             Убедитесь что контейнер запущен: docker compose up`);
    });

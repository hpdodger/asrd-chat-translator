"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TranslationQueue = void 0;
const translation_files_1 = require("./translation-files");
class TranslationQueue {
    _translator;
    _respFile;
    _items = [];
    _busy = false;
    constructor(_translator, _respFile) {
        this._translator = _translator;
        this._respFile = _respFile;
    }
    enqueue(req) {
        this._items.push(req);
        this._processNext();
    }
    async _processNext() {
        if (this._busy || this._items.length === 0)
            return;
        this._busy = true;
        const { id, text, langs } = this._items.shift();
        console.log(`[Translator] Translating [${id}] → [${langs.join(",")}]: ${text}`);
        try {
            const results = await Promise.all(langs.map(async (lang) => {
                const translated = await this._translator.translateWithFallback(text, lang);
                // Pipe is the IPC delimiter — must not appear inside translated content
                return `${lang}:${translated.replace(/\|/g, " ")}`;
            }));
            const responseStr = `${id}|${results.join("|")}`;
            console.log(`[Translator] Response [${id}]: ${responseStr}`);
            (0, translation_files_1.writeResponse)(this._respFile, id, results);
        }
        catch (err) {
            console.error(`[Translator] Critical error [${id}]:`, err.message);
            // Return originals so the Squirrel client does not hang waiting for a response
            const fallbacks = langs.map(lang => `${lang}:${text.replace(/\|/g, " ")}`);
            (0, translation_files_1.writeResponse)(this._respFile, id, fallbacks);
        }
        this._busy = false;
        this._processNext();
    }
}
exports.TranslationQueue = TranslationQueue;

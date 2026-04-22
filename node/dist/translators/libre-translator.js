"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.LibreTranslator = void 0;
const axios_1 = __importDefault(require("axios"));
const base_translator_1 = require("./base-translator");
class LibreTranslator extends base_translator_1.BaseTranslator {
    static id = "libre";
    _url;
    _apiKey;
    _loadOnly;
    id = LibreTranslator.id;
    constructor(config) {
        super(config);
        this._url = config.url;
        this._apiKey = config.apiKey ?? "";
        this._loadOnly = config.loadOnly ?? [];
    }
    async translate(text, targetLang) {
        // Reject early so translateWithFallback() can try the next candidate
        if (this._loadOnly.length > 0 && !this._loadOnly.includes(targetLang)) {
            throw new Error(`Language "${targetLang}" is not in loadOnly list`);
        }
        const body = {
            q: text,
            source: "auto",
            target: targetLang,
            format: "text",
        };
        if (this._apiKey)
            body.api_key = this._apiKey;
        const response = await axios_1.default.post(`${this._url}/translate`, body, {
            timeout: 15000,
            headers: { "Content-Type": "application/json" },
        });
        return response.data.translatedText || text;
    }
    async getLanguages() {
        const response = await axios_1.default.get(`${this._url}/languages`, { timeout: 5000 });
        const all = response.data.map(l => l.code);
        if (this._loadOnly.length === 0)
            return all;
        // LibreTranslate may report extended codes (e.g. "zh-Hans") for languages
        // configured with their base code ("zh"). Return the base code from loadOnly
        // so downstream consumers (game scripts) always see the short form.
        return this._loadOnly.filter(configured => all.some(lt => lt === configured || lt.startsWith(configured + "-")));
    }
}
exports.LibreTranslator = LibreTranslator;

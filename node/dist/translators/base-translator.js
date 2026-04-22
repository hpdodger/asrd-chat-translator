"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BaseTranslator = void 0;
class BaseTranslator {
    _config;
    constructor(_config) {
        this._config = _config;
    }
    id = null;
    async translateWithFallback(text, targetLang) {
        try {
            return await this.translate(text, targetLang);
        }
        catch (err) {
            console.warn(`[Translator] Language "${targetLang}" unavailable: ${err.message}`);
            // Try English as a universal fallback before giving up
            if (targetLang !== "en") {
                try {
                    return await this.translate(text, "en");
                }
                catch (fallbackErr) {
                    console.warn(`[Translator] Fallback "en" also unavailable: ${fallbackErr.message}`);
                }
            }
            return text;
        }
    }
}
exports.BaseTranslator = BaseTranslator;

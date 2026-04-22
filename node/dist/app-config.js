"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.LANGS_FILE = exports.RESP_FILE = exports.REQ_FILE = exports.config = void 0;
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const c_default_encoding_1 = require("./c-default-encoding");
function loadConfig() {
    const configPath = path_1.default.join(process.cwd(), "app-config.json");
    if (!fs_1.default.existsSync(configPath)) {
        console.error(`[ERROR] Config file not found: ${configPath}`);
        console.error("        Copy app-config.example.json to app-config.json and fill in the values");
        process.exit(1);
    }
    let parsed;
    try {
        parsed = JSON.parse(fs_1.default.readFileSync(configPath, c_default_encoding_1.CDefaultEncoding));
    }
    catch (err) {
        console.error(`[ERROR] Failed to parse app-config.json: ${err.message}`);
        process.exit(1);
    }
    if (!parsed.gameDataPath) {
        console.error("[ERROR] gameDataPath is required in app-config.json");
        process.exit(1);
    }
    if (!parsed.translatorConfig?.translatorId) {
        console.error("[ERROR] translatorConfig.translatorId is required in app-config.json");
        process.exit(1);
    }
    // Allow Docker (or CI) to override the path without maintaining a separate config file
    if (process.env.GAME_DATA_PATH) {
        parsed.gameDataPath = process.env.GAME_DATA_PATH;
    }
    return parsed;
}
exports.config = loadConfig();
exports.REQ_FILE = path_1.default.join(exports.config.gameDataPath, "translate_req");
exports.RESP_FILE = path_1.default.join(exports.config.gameDataPath, "translate_resp");
exports.LANGS_FILE = path_1.default.join(exports.config.gameDataPath, "translate_langs");

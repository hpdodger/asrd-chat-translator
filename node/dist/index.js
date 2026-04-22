"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const chokidar_1 = __importDefault(require("chokidar"));
const app_config_1 = require("./app-config");
const translation_files_1 = require("./translation-files");
const queue_1 = require("./queue");
const c_default_encoding_1 = require("./c-default-encoding");
function loadTranslator() {
    const translatorsDir = path_1.default.join(__dirname, "translators");
    // ts-node runs .ts sources; compiled output uses .js
    const ext = __filename.endsWith(".ts") ? ".ts" : ".js";
    const targetId = app_config_1.config.translatorConfig.translatorId;
    for (const file of fs_1.default.readdirSync(translatorsDir).filter(f => f.endsWith(ext))) {
        const mod = require(path_1.default.join(translatorsDir, file));
        for (const candidate of Object.values(mod)) {
            if (typeof candidate === "function" && candidate.id === targetId) {
                return new candidate(app_config_1.config.translatorConfig);
            }
        }
    }
    console.error(`[ERROR] No translator found with id "${targetId}"`);
    process.exit(1);
}
const translator = loadTranslator();
const queue = new queue_1.TranslationQueue(translator, app_config_1.RESP_FILE);
console.log("[Translator] Starting");
console.log(`[Translator] Game data:      ${app_config_1.config.gameDataPath}`);
console.log(`[Translator] Translator:     ${app_config_1.config.translatorConfig.translatorId}`);
console.log(`[Translator] Watching:       ${app_config_1.REQ_FILE}`);
(0, translation_files_1.initFiles)(app_config_1.REQ_FILE, app_config_1.RESP_FILE);
let lastReqId = null;
function handleReqFile(filePath) {
    const req = (0, translation_files_1.parseRequest)(filePath, app_config_1.config.targetLang);
    if (!req)
        return;
    if (req.id === lastReqId)
        return;
    lastReqId = req.id;
    queue.enqueue(req);
}
// Process any request left over from a previous session before the watcher starts
handleReqFile(app_config_1.REQ_FILE);
chokidar_1.default.watch(app_config_1.REQ_FILE, {
    persistent: true,
    usePolling: true, // more reliable on Windows and network drives
    interval: 300,
    awaitWriteFinish: { stabilityThreshold: 100, pollInterval: 100 },
    ignoreInitial: false,
}).on("change", handleReqFile)
    .on("error", err => console.error("[Watcher] Error:", err));
translator.getLanguages()
    .then(codes => {
    console.log(`[Translator] LibreTranslate ready. Languages: ${codes.join(", ")}`);
    fs_1.default.writeFileSync(app_config_1.LANGS_FILE, codes.join(","), c_default_encoding_1.CDefaultEncoding);
})
    .catch(err => {
    console.warn(`[Translator] LibreTranslate unavailable (${err.message})`);
    console.warn("             Make sure the container is running: docker compose up");
});

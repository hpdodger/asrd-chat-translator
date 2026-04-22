import fs from "fs";
import path from "path";
import chokidar from "chokidar";
import { config, REQ_FILE, RESP_FILE, LANGS_FILE } from "./app-config";
import { initFiles, parseRequest } from "./translation-files";
import { IBaseTranslator, ITranslatorClass } from "./translators/base-translator";
import { TranslationQueue } from "./queue";
import { CDefaultEncoding } from "./c-default-encoding";

function loadTranslator(): IBaseTranslator {
  const translatorsDir = path.join(__dirname, "translators");
  // ts-node runs .ts sources; compiled output uses .js
  const ext  = __filename.endsWith(".ts") ? ".ts" : ".js";
  const targetId = config.translatorConfig.translatorId;

  for (const file of fs.readdirSync(translatorsDir).filter(f => f.endsWith(ext))) {
    const mod = require(path.join(translatorsDir, file)) as Record<string, unknown>;
    for (const candidate of Object.values(mod)) {
      if (typeof candidate === "function" && (candidate as ITranslatorClass).id === targetId) {
        return new (candidate as ITranslatorClass)(config.translatorConfig);
      }
    }
  }

  console.error(`[ERROR] No translator found with id "${targetId}"`);
  process.exit(1);
}

const translator = loadTranslator();
const queue      = new TranslationQueue(translator, RESP_FILE);

console.log("[Translator] Starting");
console.log(`[Translator] Game data:      ${config.gameDataPath}`);
console.log(`[Translator] Translator:     ${config.translatorConfig.translatorId}`);
console.log(`[Translator] Watching:       ${REQ_FILE}`);

initFiles(REQ_FILE, RESP_FILE);

let lastReqId: string | null = null;

function handleReqFile(filePath: string): void {
  const req = parseRequest(filePath, config.targetLang);
  if (!req) return;
  if (req.id === lastReqId) return;

  lastReqId = req.id;
  queue.enqueue(req);
}

// Process any request left over from a previous session before the watcher starts
handleReqFile(REQ_FILE);

chokidar.watch(REQ_FILE, {
  persistent:       true,
  usePolling:       true,   // more reliable on Windows and network drives
  interval:         300,
  awaitWriteFinish: { stabilityThreshold: 100, pollInterval: 100 },
  ignoreInitial:    false,
}).on("change", handleReqFile)
  .on("error",  err => console.error("[Watcher] Error:", err));

translator.getLanguages()
  .then(codes => {
    console.log(`[Translator] LibreTranslate ready. Languages: ${codes.join(", ")}`);
    fs.writeFileSync(LANGS_FILE, codes.join(","), CDefaultEncoding);
  })
  .catch(err => {
    console.warn(`[Translator] LibreTranslate unavailable (${(err as Error).message})`);
    console.warn("             Make sure the container is running: docker compose up");
  });

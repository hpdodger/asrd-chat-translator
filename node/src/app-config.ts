import fs from "fs";
import path from "path";
import { IBaseTranslatorConfig } from "./translators/base-translator";
import { CDefaultEncoding } from "./c-default-encoding";

export interface IAppConfig {
  gameDataPath: string;
  targetLang: string;
  translatorConfig: IBaseTranslatorConfig;
}

function loadConfig(): IAppConfig {
  const configPath = path.join(process.cwd(), "app-config.json");

  if (!fs.existsSync(configPath)) {
    console.error(`[ERROR] Config file not found: ${configPath}`);
    console.error("        Copy app-config.example.json to app-config.json and fill in the values");
    process.exit(1);
  }

  let parsed: IAppConfig;
  try {
    parsed = JSON.parse(fs.readFileSync(configPath, CDefaultEncoding)) as IAppConfig;
  } catch (err) {
    console.error(`[ERROR] Failed to parse app-config.json: ${(err as Error).message}`);
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

export const config = loadConfig();

export const REQ_FILE   = path.join(config.gameDataPath, "translate_req");
export const RESP_FILE  = path.join(config.gameDataPath, "translate_resp");
export const LANGS_FILE = path.join(config.gameDataPath, "translate_langs");

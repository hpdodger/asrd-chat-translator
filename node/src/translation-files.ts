import fs from "fs";
import { CDefaultEncoding } from "./c-default-encoding";

export interface ITranslationRequest {
  id: string;
  text: string;
  langs: string[];
}

export function parseRequest(filePath: string, fallbackLang: string): ITranslationRequest | null {
  let raw: string;
  try {
    raw = fs.readFileSync(filePath, CDefaultEncoding).trim();
  } catch {
    return null;
  }

  if (!raw || raw === "0") return null;

  // Format: id|text|lang1,lang2,...
  const firstPipe  = raw.indexOf("|");
  const secondPipe = raw.indexOf("|", firstPipe + 1);

  if (firstPipe === -1 || secondPipe === -1) return null;

  const id    = raw.slice(0, firstPipe);
  const text  = raw.slice(firstPipe + 1, secondPipe).trim();
  const langs = raw.slice(secondPipe + 1).split(",").map(l => l.trim()).filter(Boolean);

  if (!id || !text) return null;

  // Old format omits the language list — fall back to the configured default
  if (langs.length === 0) langs.push(fallbackLang);

  return { id, text, langs };
}

export function writeResponse(filePath: string, id: string, results: string[]): void {
  fs.writeFileSync(filePath, `${id}|${results.join("|")}`, CDefaultEncoding);
}

export function initFiles(reqFile: string, respFile: string): void {
  if (!fs.existsSync(reqFile))  fs.writeFileSync(reqFile,  "0", CDefaultEncoding);
  if (!fs.existsSync(respFile)) fs.writeFileSync(respFile, "0", CDefaultEncoding);
}

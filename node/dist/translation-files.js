"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseRequest = parseRequest;
exports.writeResponse = writeResponse;
exports.initFiles = initFiles;
const fs_1 = __importDefault(require("fs"));
const c_default_encoding_1 = require("./c-default-encoding");
function parseRequest(filePath, fallbackLang) {
    let raw;
    try {
        raw = fs_1.default.readFileSync(filePath, c_default_encoding_1.CDefaultEncoding).trim();
    }
    catch {
        return null;
    }
    if (!raw || raw === "0")
        return null;
    // Format: id|text|lang1,lang2,...
    const firstPipe = raw.indexOf("|");
    const secondPipe = raw.indexOf("|", firstPipe + 1);
    if (firstPipe === -1 || secondPipe === -1)
        return null;
    const id = raw.slice(0, firstPipe);
    const text = raw.slice(firstPipe + 1, secondPipe).trim();
    const langs = raw.slice(secondPipe + 1).split(",").map(l => l.trim()).filter(Boolean);
    if (!id || !text)
        return null;
    // Old format omits the language list — fall back to the configured default
    if (langs.length === 0)
        langs.push(fallbackLang);
    return { id, text, langs };
}
function writeResponse(filePath, id, results) {
    fs_1.default.writeFileSync(filePath, `${id}|${results.join("|")}`, c_default_encoding_1.CDefaultEncoding);
}
function initFiles(reqFile, respFile) {
    if (!fs_1.default.existsSync(reqFile))
        fs_1.default.writeFileSync(reqFile, "0", c_default_encoding_1.CDefaultEncoding);
    if (!fs_1.default.existsSync(respFile))
        fs_1.default.writeFileSync(respFile, "0", c_default_encoding_1.CDefaultEncoding);
}

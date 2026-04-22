import { IBaseTranslator } from "./translators/base-translator";
import { ITranslationRequest, writeResponse } from "./translation-files";

export class TranslationQueue {
  private readonly _items: ITranslationRequest[] = [];
  private _busy = false;

  constructor(
    private readonly _translator: IBaseTranslator,
    private readonly _respFile: string,
  ) {}

  public enqueue(req: ITranslationRequest): void {
    this._items.push(req);
    this._processNext();
  }

  private async _processNext(): Promise<void> {
    if (this._busy || this._items.length === 0) return;
    this._busy = true;

    const { id, text, langs } = this._items.shift()!;
    console.log(`[Translator] Translating [${id}] → [${langs.join(",")}]: ${text}`);

    try {
      const results = await Promise.all(
        langs.map(async (lang) => {
          const translated = await this._translator.translateWithFallback(text, lang);
          // Pipe is the IPC delimiter — must not appear inside translated content
          return `${lang}:${translated.replace(/\|/g, " ")}`;
        })
      );

      const responseStr = `${id}|${results.join("|")}`;
      console.log(`[Translator] Response [${id}]: ${responseStr}`);
      writeResponse(this._respFile, id, results);
    } catch (err) {
      console.error(`[Translator] Critical error [${id}]:`, (err as Error).message);
      // Return originals so the Squirrel client does not hang waiting for a response
      const fallbacks = langs.map(lang => `${lang}:${text.replace(/\|/g, " ")}`);
      writeResponse(this._respFile, id, fallbacks);
    }

    this._busy = false;
    this._processNext();
  }
}

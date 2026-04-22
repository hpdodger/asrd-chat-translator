import axios from "axios";
import { IBaseTranslatorConfig, BaseTranslator } from "./base-translator";

export interface ILibreTranslatorConfig extends IBaseTranslatorConfig {
  translatorId: "libre";
  url: string;
  apiKey?: string;
  loadOnly: string[];
}

export class LibreTranslator extends BaseTranslator {
  public static readonly id = "libre";

  private readonly _url: string;
  private readonly _apiKey: string;
  private readonly _loadOnly: string[];

  public id: string | null = LibreTranslator.id;

  constructor(config: ILibreTranslatorConfig) {
    super(config);
    this._url = config.url;
    this._apiKey = config.apiKey ?? "";
    this._loadOnly = config.loadOnly ?? [];
  }

  public async translate(text: string, targetLang: string): Promise<string> {
    // Reject early so translateWithFallback() can try the next candidate
    if (this._loadOnly.length > 0 && !this._loadOnly.includes(targetLang)) {
      throw new Error(`Language "${targetLang}" is not in loadOnly list`);
    }

    const body: Record<string, string> = {
      q: text,
      source: "auto",
      target: targetLang,
      format: "text",
    };
    if (this._apiKey) body.api_key = this._apiKey;

    const response = await axios.post(`${this._url}/translate`, body, {
      timeout: 15000,
      headers: { "Content-Type": "application/json" },
    });

    return response.data.translatedText || text;
  }

  public async getLanguages(): Promise<string[]> {
    const response = await axios.get(`${this._url}/languages`, { timeout: 5000 });
    const all = (response.data as Array<{ code: string }>).map(l => l.code);

    if (this._loadOnly.length === 0) return all;

    // LibreTranslate may report extended codes (e.g. "zh-Hans") for languages
    // configured with their base code ("zh"). Return the base code from loadOnly
    // so downstream consumers (game scripts) always see the short form.
    return this._loadOnly.filter(configured =>
      all.some(lt => lt === configured || lt.startsWith(configured + "-"))
    );
  }
}

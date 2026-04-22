export interface IBaseTranslatorConfig {
  translatorId: string;
}

export interface IBaseTranslator {
  id: string | null;
  translate(text: string, targetLang: string): Promise<string>;
  getLanguages(): Promise<string[]>;
  translateWithFallback(text: string, targetLang: string): Promise<string>;
}

// Contract for the plugin system: each concrete translator module must export
// a class that satisfies this interface so the runtime scanner can discover it.
export interface ITranslatorClass {
  readonly id: string;
  new(config: IBaseTranslatorConfig): IBaseTranslator;
}

export abstract class BaseTranslator implements IBaseTranslator {
  constructor(protected readonly _config: IBaseTranslatorConfig) {}
  
  public id: string | null = null;

  public abstract translate(text: string, targetLang: string): Promise<string>;
  public abstract getLanguages(): Promise<string[]>;

  public async translateWithFallback(text: string, targetLang: string): Promise<string> {
    try {
      return await this.translate(text, targetLang);
    } catch (err) {
      console.warn(`[Translator] Language "${targetLang}" unavailable: ${(err as Error).message}`);
      // Try English as a universal fallback before giving up
      if (targetLang !== "en") {
        try {
          return await this.translate(text, "en");
        } catch (fallbackErr) {
          console.warn(`[Translator] Fallback "en" also unavailable: ${(fallbackErr as Error).message}`);
        }
      }
      return text;
    }
  }
}

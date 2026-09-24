import { Injectable, signal } from '@angular/core';

export type DisplayLanguage = 'ur' | 'en';

// Controls whether Menu Setup and the Sales screen show dish names in Urdu
// (Dish.name) or English (Dish.printName) — a display-only preference, kept
// per-browser/till via localStorage. Doesn't affect what's stored on orders
// or printed on receipts, which already have their own English-fallback logic.
@Injectable({ providedIn: 'root' })
export class LanguageService {
  private readonly storageKey = 'tehzeeb-pos-display-lang';
  readonly lang = signal<DisplayLanguage>(this.loadInitial());

  private loadInitial(): DisplayLanguage {
    const saved = localStorage.getItem(this.storageKey);
    return saved === 'en' ? 'en' : 'ur';
  }

  set(lang: DisplayLanguage) {
    this.lang.set(lang);
    localStorage.setItem(this.storageKey, lang);
  }

  // Returns the display name for a dish/cart item: prefers printName (English)
  // when in English mode, otherwise the (Urdu) name — falling back to
  // whichever is available if the other one is blank.
  displayName(name: string, printName?: string | null): string {
    if (this.lang() === 'en') return printName?.trim() ? printName : name;
    return name?.trim() ? name : (printName ?? '');
  }
}

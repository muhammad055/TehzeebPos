import { Injectable, effect, signal } from '@angular/core';

export type ThemeId =
  | 'midnight' | 'lavender' | 'slate' | 'emerald'
  | 'sapphire' | 'rose' | 'teal' | 'amber' | 'cobalt' | 'terracotta' | 'sky';

export interface ThemeOption {
  id: ThemeId;
  label: string;
}

export const THEMES: ThemeOption[] = [
  { id: 'midnight',    label: 'Midnight (Dark)' },
  { id: 'lavender',    label: 'Lavender' },
  { id: 'slate',       label: 'Slate' },
  { id: 'emerald',     label: 'Emerald' },
  { id: 'sapphire',    label: 'Sapphire & Ice' },
  { id: 'rose',        label: 'Rose & Pearl' },
  { id: 'teal',        label: 'Teal & Ivory' },
  { id: 'amber',       label: 'Amber & Charcoal' },
  { id: 'cobalt',      label: 'Cobalt & Cloud' },
  { id: 'terracotta',  label: 'Terracotta & Cream' },
  { id: 'sky',         label: 'Slate & Sky' },
];

const STORAGE_KEY = 'tehzeeb-pos-theme';
const DEFAULT_THEME: ThemeId = 'lavender';

@Injectable({ providedIn: 'root' })
export class ThemeService {
  readonly theme = signal<ThemeId>(this.loadInitial());

  constructor() {
    // Applies on init and whenever set() changes the signal — same
    // signal-driven pattern as LanguageService.
    effect(() => {
      const id = this.theme();
      document.documentElement.setAttribute('data-theme', id);
      try {
        localStorage.setItem(STORAGE_KEY, id);
      } catch {
        // localStorage unavailable (private mode etc.) — theme just won't persist
      }
    });
  }

  set(id: ThemeId) {
    this.theme.set(id);
  }

  private loadInitial(): ThemeId {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored && THEMES.some((t) => t.id === stored)) return stored as ThemeId;
    } catch {
      // ignore
    }
    return DEFAULT_THEME;
  }
}

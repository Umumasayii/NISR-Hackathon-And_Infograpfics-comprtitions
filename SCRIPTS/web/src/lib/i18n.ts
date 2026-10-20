import type { I18n } from '../data/types';

export type Lang = 'en' | 'rw' | 'fr';
export const LANGS: Record<Lang, string> = { en: 'English', rw: 'Kinyarwanda', fr: 'Français' };
export type Tr = (key: string, ...args: (string | number)[]) => string;

/** sprintf for the wording file: %s, %d and %% only (same file as the Shiny app) */
export function sprintf(txt: string, args: (string | number)[]) {
  let i = 0;
  return txt.replace(/%%|%[sd]/g, (m) => (m === '%%' ? '%' : String(args[i++] ?? '')));
}

export function makeTr(dict: I18n, lang: Lang): Tr {
  return (key, ...args) => {
    const e = dict[key];
    const txt = (e && (e[lang] || e.en)) || key;
    return args.length ? sprintf(txt, args) : txt.replace(/%%/g, '%');
  };
}

/** a translated label when the key exists, else the raw value */
export const labOr = (dict: I18n, tr: Tr, prefix: string, v: string) => (dict[prefix + v] ? tr(prefix + v) : v);

export function initialLang(): Lang {
  const q = new URLSearchParams(window.location.search).get('lang');
  const h = new URLSearchParams(window.location.hash.split('?')[1] || '').get('lang');
  let saved: string | null = null;
  try { saved = localStorage.getItem('si-lang'); } catch { /* private mode */ }
  const l = (q || h || saved || 'en') as Lang;
  return l in LANGS ? l : 'en';
}

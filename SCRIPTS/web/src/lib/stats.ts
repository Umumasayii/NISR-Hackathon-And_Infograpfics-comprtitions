// Data helpers shared by the pages. Same rules as SCRIPTS/app/R/fct_data.R, so the
// web app and the Shiny app show the same numbers.
import type { AppData, Est, Reliability, Totals, Crop, AhsRow, Season } from '../data/types';

/** Every filter, resolved (built in store.tsx). Empty crop lists mean "all crops". */
export interface Filters {
  years: number[]; seasons: Season[];
  areaLevel: 'national' | 'province' | 'district';
  areas: string[];          // the selected names at that level ("Rwanda" when national)
  districts: string[];      // every district inside the selection
  provinces: string[];
  area: string;             // short label for text: "Rwanda", "Kirehe", "East + 1"
  district: string;         // the district when exactly one is selected, else ""
  cropGroups: string[]; crops: string[];
}

// ---- small array helpers ---------------------------------------------------------
export function groupBy<T>(rows: T[], key: (r: T) => string): Map<string, T[]> {
  const m = new Map<string, T[]>();
  for (const r of rows) { const k = key(r); const a = m.get(k); if (a) a.push(r); else m.set(k, [r]); }
  return m;
}
export const sum = (x: (number | null | undefined)[]) => x.reduce<number>((a, b) => a + (Number.isFinite(b as number) ? (b as number) : 0), 0);
export const mean = (x: (number | null | undefined)[]) => { const v = x.filter((y): y is number => Number.isFinite(y as number)); return v.length ? sum(v) / v.length : NaN; };
export const median = (x: number[]) => { const v = x.filter(Number.isFinite).sort((a, b) => a - b); if (!v.length) return NaN; const m = v.length >> 1; return v.length % 2 ? v[m] : (v[m - 1] + v[m]) / 2; };
/** weighted mean that drops missing values and missing / zero weights */
export function wm(x: (number | null | undefined)[], w: (number | null | undefined)[]) {
  let s = 0, sw = 0;
  for (let i = 0; i < x.length; i++) {
    const xi = x[i], wi = w[i];
    if (Number.isFinite(xi as number) && Number.isFinite(wi as number) && (wi as number) > 0) { s += (xi as number) * (wi as number); sw += wi as number; }
  }
  return sw > 0 ? s / sw : NaN;
}
export const uniq = <T,>(x: T[]) => Array.from(new Set(x));
/** most common value (the Shiny app's names(sort(table(x), decreasing = TRUE))[1]) */
export function mode<T extends string>(x: (T | null)[]): T | null {
  const c = new Map<T, number>();
  for (const v of x) if (v != null) c.set(v, (c.get(v) || 0) + 1);
  let best: T | null = null, bn = -1;
  for (const [k, n] of [...c.entries()].sort((a, b) => (a[0] < b[0] ? -1 : 1))) if (n > bn) { best = k; bn = n; }
  return best;
}
export const seasonOrder = (s: string) => ({ A: 0, B: 1, C: 2 } as Record<string, number>)[s] ?? 3;
export const last = <T,>(x: T[]) => x[x.length - 1];

/**
 * Same rule as reliability() in SCRIPTS/00_Config.R: the unweighted sample (n), the number
 * of survey clusters it comes from (n_psu) and the design-based CV. Without a standard
 * error there is nothing to judge ("Not assessed"); without the cluster count an estimate
 * can be "Use with caution" at best, never "Good".
 */
export function reliabilityLab(n: number | null, cv: number | null, nPsu?: number | null, hasSe = true): Reliability {
  if (!hasSe) return 'Not assessed';
  if (n == null || n < 30 || (nPsu != null && nPsu < 5)) return 'Unreliable';
  if (cv != null && cv <= 0.2 && n >= 50 && nPsu != null && nPsu >= 12) return 'Good';
  if (cv != null && cv <= 0.35) return 'Use with caution';
  return 'Unreliable';
}
const psuSum = (x: (number | null | undefined)[]) => (x.every((v) => v != null && Number.isFinite(v)) ? sum(x) : null);

/**
 * Several districts or provinces -> one estimate. Districts are survey strata, so the
 * combined share is the weighted-count average and its variance is the sum of the
 * stratum variances, sum((W_d / W)^2 * se_d^2).
 */
export function combineEst(d: Est[], label: string): Est[] {
  const out: Est[] = [];
  for (const g of groupBy(d, (r) => `${r.sas_year}|${r.sas_season}|${r.indicator}`).values()) {
    const W = sum(g.map((r) => r.wsum));
    const estimate = sum(g.map((r) => r.wsum * r.estimate)) / W;
    const pub = g.every((r) => r.source === 'nisr');
    const se = pub ? null : Math.sqrt(sum(g.map((r) => (r.wsum / W) ** 2 * (r.se ?? 0) ** 2)));
    const n = sum(g.map((r) => r.n));
    const cv = estimate > 0 && se != null ? se / estimate : null;
    const nPsu = psuSum(g.map((r) => r.n_psu));
    // a survey area with no standard error cannot be judged, and neither can the sum
    const noSe = g.some((r) => r.source === 'survey' && r.se == null);
    out.push({
      ...g[0], level: 'combined', area: label, wsum: W, estimate, se: noSe ? null : se, n, n_psu: nPsu,
      source: pub ? 'nisr' : 'survey', survey_estimate: null, nisr_table: pub ? g.map((r) => r.nisr_table).filter(Boolean).join('; ') : null,
      // districts are strata, so 1.96 is used: the combined design df runs into the hundreds
      ci_low: se == null || noSe ? null : Math.max(estimate - 1.96 * se, 0), ci_high: se == null || noSe ? null : estimate + 1.96 * se,
      cv: noSe ? null : cv, reliability: pub ? 'Published' : reliabilityLab(n, cv, nPsu, !noSe),
    });
  }
  return out;
}

/** Averages over several years use survey seasons; a NISR published season is used
 *  on its own only when the selection has no survey season for that group. */
export function surveyFirst<T extends { source: string }>(d: T[], key: (r: T) => string): T[] {
  const out: T[] = [];
  for (const g of groupBy(d, key).values()) {
    const hasSurvey = g.some((r) => r.source === 'survey');
    out.push(...(hasSurvey ? g.filter((r) => r.source === 'survey') : g));
  }
  return out;
}

/** Survey estimates for the selected area(s), combined into one series */
export function estFor(D: AppData, f: Filters, inds: string[] | string, years = f.years, seasons: string[] = f.seasons): Est[] {
  const I = new Set(Array.isArray(inds) ? inds : [inds]);
  const A = new Set(f.areas), Y = new Set(years), S = new Set(seasons);
  const d = D.est.filter((r) => r.level === f.areaLevel && A.has(r.area) && I.has(r.indicator) && Y.has(r.sas_year) && S.has(r.sas_season));
  return f.areas.length > 1 ? combineEst(d, f.area) : d;
}

export interface YearRow { sas_year: number; seasons: string; estimate: number; n: number; rel: Reliability | null; source: 'survey' | 'nisr' }
/** Several seasons -> one value per year (weighted by the weighted plot count) */
export function byYear(d: Est[]): YearRow[] {
  return [...groupBy(d, (r) => String(r.sas_year)).values()].map((g) => ({
    sas_year: g[0].sas_year,
    seasons: [...g].sort((a, b) => seasonOrder(a.sas_season) - seasonOrder(b.sas_season)).map((r) => `${r.sas_season} ${r.estimate.toFixed(1)}%`).join(' · '),
    estimate: wm(g.map((r) => r.estimate), g.map((r) => r.wsum)),
    n: sum(g.map((r) => r.n)),
    rel: mode(g.map((r) => r.reliability)),
    source: g.every((r) => r.source === 'nisr') ? 'nisr' as const : 'survey' as const,
  })).sort((a, b) => a.sas_year - b.sas_year);
}

const TOT_COLS = ['cultivated_area_ha', 'irrigated_area_ha', 'production_t', 'crop_area_ha', 'sold_t', 'sales_value_mrwf', 'modern_irrig_area_ha'] as const;
/** Totals (ha, t) for the selection: districts summed */
export function totalsFor(D: AppData, f: Filters): Totals[] {
  const Y = new Set(f.years), S = new Set<string>(f.seasons);
  const t = D.totals.filter((r) => Y.has(r.sas_year) && S.has(r.sas_season));
  if (f.areaLevel === 'national') return t.filter((r) => r.level === 'national');
  const Ds = new Set(f.districts);
  return [...groupBy(t.filter((r) => r.level === 'district' && Ds.has(r.area)), (r) => `${r.sas_year}|${r.sas_season}`).values()].map((g) => {
    const row = { ...g[0], level: 'combined' as const, area: f.area } as Totals;
    for (const c of TOT_COLS) {
      const v = g.map((r) => r[c]);
      (row as unknown as Record<string, number | null>)[c] = v.every((x) => x == null) ? null : sum(v);
    }
    row.irrigated_area_pct = row.irrigated_area_ha != null && row.cultivated_area_ha ? (100 * row.irrigated_area_ha) / row.cultivated_area_ha : null;
    return row;
  });
}

/** Crop table for the selection. For a sub-national selection the district rows are kept. */
export function cropsFor(D: AppData, f: Filters): Crop[] {
  const Y = new Set(f.years), S = new Set<string>(f.seasons), G = new Set(f.cropGroups), C = new Set(f.crops), Ds = new Set(f.districts);
  const base = f.areaLevel === 'national' ? D.crop : D.crop_dist.filter((r) => Ds.has(r.district_std!));
  return base.filter((r) => Y.has(r.sas_year) && S.has(r.sas_season) && (!G.size || G.has(r.crop_group)) && (!C.size || C.has(r.crop_name)));
}

/** AHS estimates for the selected area; several areas combined as in combineEst() */
export function ahsFor(D: AppData, f: Filters, inds?: string[]): AhsRow[] {
  if (!D.ahs) return [];
  const I = inds ? new Set(inds) : null, A = new Set(f.areas);
  const d = D.ahs.indicators.filter((r) => (!I || I.has(r.indicator)) && r.level === f.areaLevel && A.has(r.area));
  if (f.areas.length <= 1 || !d.length) return d;
  return [...groupBy(d, (r) => `${r.year}|${r.indicator}|${r.population}|${r.series_break}`).values()].map((g) => {
    const W = sum(g.map((r) => r.wsum));
    const estimate = sum(g.map((r) => r.wsum * r.estimate)) / W;
    const se = Math.sqrt(sum(g.map((r) => (r.wsum / W) ** 2 * (r.se ?? 0) ** 2)));
    const n = sum(g.map((r) => r.n));
    const cv = estimate > 0 ? se / estimate : null;
    // AHS 2020 has no cluster identifiers: its SEs ignore clustering, so no label (see 10_AHS_Preparation.R)
    const na = g.some((r) => r.reliability === 'Not assessed');
    return { ...g[0], level: 'combined' as const, area: f.area, wsum: W, estimate, se, n,
      ci_low: Math.max(estimate - 1.96 * se, 0), ci_high: estimate + 1.96 * se, cv,
      reliability: na ? 'Not assessed' as const : reliabilityLab(n, cv, psuSum(g.map((r) => r.n_psu))) };
  });
}
export const ahsVal = (d: AhsRow[], ind: string, yr: number) => d.find((r) => r.indicator === ind && r.year === yr)?.estimate ?? NaN;

/** "27 in every 100" */
export const in100 = (x: number | null | undefined, tr: (k: string, ...a: (string | number)[]) => string) =>
  x == null || !Number.isFinite(x) ? '–' : x < 1 ? tr('lt1in100') : tr('in100', Math.round(x).toLocaleString('en-US'));

/** a CSV file from rows, downloaded by the browser */
export function downloadCsv(rows: Record<string, unknown>[], filename: string) {
  if (!rows.length) return;
  const cols = Object.keys(rows[0]);
  const esc = (v: unknown) => { const s = v == null ? '' : String(v); return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
  const csv = '﻿' + [cols.join(','), ...rows.map((r) => cols.map((c) => esc(r[c])).join(','))].join('\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
  a.download = filename; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

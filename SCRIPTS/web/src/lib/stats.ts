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

// Same rule as reliability() in SCRIPTS/00_Config.R: unweighted n, segments (n_psu) and CV.
// A missing standard error is never read as zero: the estimate is then 'Unreliable'.
export const MIN_N = 30, MIN_PSU = 5;
export function reliabilityLab(n: number | null, cv: number | null, nPsu: number | null = null): Reliability {
  if (n == null || n < MIN_N) return 'Unreliable';
  if (nPsu != null && nPsu < MIN_PSU) return 'Unreliable';
  if (cv != null && cv <= 0.2 && n >= 50 && (nPsu == null || nPsu >= 12)) return 'Good';
  if (cv != null && cv <= 0.35) return 'Use with caution';
  return 'Unreliable';
}

/** two-sided 97.5% Student t quantile (Cornish-Fisher expansion; exact enough for CIs) */
export function tq975(df: number | null | undefined): number {
  const z = 1.959963984540054;
  if (df == null || !Number.isFinite(df) || df <= 0) return z;
  const d = Math.max(df, 1), z3 = z ** 3, z5 = z ** 5, z7 = z ** 7;
  return z + (z3 + z) / (4 * d) + (5 * z5 + 16 * z3 + 3 * z) / (96 * d * d) + (3 * z7 + 19 * z5 + 17 * z3 - 15 * z) / (384 * d ** 3);
}

/**
 * Several districts or provinces -> one estimate for the same season. Districts are
 * separate survey strata within a season, so the combined share is the weighted-count
 * average and its variance is sum((W_d / W)^2 * se_d^2); segments and design degrees
 * of freedom add up. If any part has no standard error the combination has none
 * either (shown without an interval and labelled 'Unreliable'), never se = 0.
 */
export function combineParts<T extends { wsum: number; estimate: number; se: number | null; n: number; n_psu?: number | null; df?: number | null }>(g: T[]) {
  const W = sum(g.map((r) => r.wsum));
  const estimate = sum(g.map((r) => r.wsum * r.estimate)) / W;
  const seKnown = g.every((r) => r.se != null && Number.isFinite(r.se));
  const se = seKnown ? Math.sqrt(sum(g.map((r) => (r.wsum / W) ** 2 * (r.se as number) ** 2))) : null;
  const n = sum(g.map((r) => r.n));
  const n_psu = g.every((r) => r.n_psu != null) ? sum(g.map((r) => r.n_psu)) : null;
  const df = g.every((r) => r.df != null) ? sum(g.map((r) => r.df)) : null;
  const cv = se != null && estimate > 0 ? se / estimate : null;
  const t = tq975(df);
  return { wsum: W, estimate, se, n, n_psu, df, cv,
    ci_low: se == null ? null : Math.max(estimate - t * se, 0), ci_high: se == null ? null : estimate + t * se,
    reliability: se == null ? 'Unreliable' as Reliability : reliabilityLab(n, cv, n_psu) };
}
export function combineEst(d: Est[], label: string): Est[] {
  return [...groupBy(d, (r) => `${r.sas_year}|${r.sas_season}|${r.indicator}`).values()]
    .map((g) => ({ ...g[0], level: 'combined' as const, area: label, source: 'survey' as const, ...combineParts(g) }));
}

/** Survey estimates for the selected area(s), combined into one series */
export function estFor(D: AppData, f: Filters, inds: string[] | string, years = f.years, seasons: string[] = f.seasons): Est[] {
  const I = new Set(Array.isArray(inds) ? inds : [inds]);
  const A = new Set(f.areas), Y = new Set(years), S = new Set(seasons);
  const d = D.est.filter((r) => r.level === f.areaLevel && A.has(r.area) && I.has(r.indicator) && Y.has(r.sas_year) && S.has(r.sas_season));
  return f.areas.length > 1 ? combineEst(d, f.area) : d;
}

export interface YearRow { sas_year: number; seasons: string; estimate: number; n: number; rel: Reliability | null }
/** Several seasons -> one value per year (weighted by the weighted plot count) */
export function byYear(d: Est[]): YearRow[] {
  return [...groupBy(d, (r) => String(r.sas_year)).values()].map((g) => ({
    sas_year: g[0].sas_year,
    seasons: [...g].sort((a, b) => seasonOrder(a.sas_season) - seasonOrder(b.sas_season)).map((r) => `${r.sas_season} ${r.estimate.toFixed(1)}%`).join(' · '),
    estimate: wm(g.map((r) => r.estimate), g.map((r) => r.wsum)),
    n: sum(g.map((r) => r.n)),
    rel: mode(g.map((r) => r.reliability)),
  })).sort((a, b) => a.sas_year - b.sas_year);
}

const TOT_COLS = ['cultivated_area_ha', 'irrigated_area_ha', 'production_t', 'crop_area_ha', 'sold_t', 'sales_value_mrwf', 'modern_irrig_area_ha'] as const;
/** Totals (ha, t) for the selection: districts summed. A total is kept only when every
 *  selected district has a value, so a missing district is never counted as zero. */
export function totalsFor(D: AppData, f: Filters): Totals[] {
  const Y = new Set(f.years), S = new Set<string>(f.seasons);
  const t = D.totals.filter((r) => Y.has(r.sas_year) && S.has(r.sas_season));
  if (f.areaLevel === 'national') return t.filter((r) => r.level === 'national');
  const Ds = new Set(f.districts);
  return [...groupBy(t.filter((r) => r.level === 'district' && Ds.has(r.area)), (r) => `${r.sas_year}|${r.sas_season}`).values()].map((g) => {
    const row = { ...g[0], level: 'combined' as const, area: f.area } as Totals;
    const complete = g.length === Ds.size;
    for (const c of TOT_COLS) {
      const v = g.map((r) => r[c]);
      (row as unknown as Record<string, number | null>)[c] = complete && v.every((x) => x != null && Number.isFinite(x)) ? sum(v) : null;
    }
    row.irrigated_area_pct = row.irrigated_area_ha != null && row.cultivated_area_ha ? (100 * row.irrigated_area_ha) / row.cultivated_area_ha : null;
    return row;
  });
}

/** Seasons whose yields can be used (crop area measured for at least 80% of plots) */
export function yieldSeasons(D: AppData): Set<string> {
  return new Set(D.meta.season_quality.filter((r) => r.yield_usable).map((r) => `${r.sas_year}${r.sas_season}`));
}

export interface YieldAgg { all: number; irr: number; rf: number; nIrr: number; exact: boolean; excluded: number }
/**
 * Yield of a set of crop rows (kg/ha), with one eligibility rule for every chart:
 * seasons with unusable area measurement are left out, and a yield is summed harvest
 * over summed area of the eligible plots, never an average of yields. Data built
 * before these sums were exported: one row is shown as it is, and a combination of
 * rows stays empty rather than being averaged with the wrong weights.
 */
export function yieldOf(D: AppData, rows: Crop[]): YieldAgg {
  const ok = yieldSeasons(D);
  const d = rows.filter((r) => ok.has(`${r.sas_year}${r.sas_season}`));
  const excluded = rows.length - d.length;
  const nIrr = sum(d.map((r) => r.n_irrigated_yield));
  const ratio = (h: (number | null | undefined)[], a: (number | null | undefined)[]) => { const A = sum(a); return A > 0 ? sum(h) / A : NaN; };
  if (d.length && d.every((r) => r.yield_area_ha !== undefined)) return {
    all: ratio(d.map((r) => r.yield_harvest_kg), d.map((r) => r.yield_area_ha)),
    irr: ratio(d.map((r) => r.yield_harvest_irr_kg), d.map((r) => r.yield_area_irr_ha)),
    rf: ratio(d.map((r) => r.yield_harvest_rf_kg), d.map((r) => r.yield_area_rf_ha)),
    nIrr, exact: true, excluded,
  };
  if (d.length === 1) return { all: d[0].yield_kg_ha ?? NaN, irr: d[0].yield_irrigated_kg_ha ?? NaN, rf: d[0].yield_rainfed_kg_ha ?? NaN, nIrr, exact: true, excluded };
  return { all: NaN, irr: NaN, rf: NaN, nIrr, exact: false, excluded };
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
  return [...groupBy(d, (r) => `${r.year}|${r.indicator}|${r.population}|${r.series_break}`).values()]
    .map((g) => ({ ...g[0], level: 'combined' as const, area: f.area, ...combineParts(g) }) as AhsRow);
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

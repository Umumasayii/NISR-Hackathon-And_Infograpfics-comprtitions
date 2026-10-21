// Published NISR figures (official.json): looked up by indicator, season, place and crop,
// cited down to the table and cell. Where NISR publishes a figure with the same
// definition as one of ours, the pages show the NISR figure and build the chart, the
// sentence, the table and the CSV from that one value. Ours stays beside it as a
// cross-check. NISR publishes national and district figures only, so a selection of
// several districts or a province gets "Published breakdown unavailable", never a
// national value copied down and never an average of district percentages.
import type { OfficialFile, PubDef, PubRow, PubSource, Season } from '../data/types';
import type { Filters } from './stats';
import { seasonOrder } from './stats';
import type { Tr } from './i18n';
import { fmtNum, fmtPct } from './format';

export interface Official {
  rows: PubRow[];
  src: Map<number, PubSource>;
  def: Map<string, PubDef>;
  built: string;
  get(ind: string, y: number, s: string, area: string, crop?: string | null): PubRow | undefined;
  of(ind: string): PubRow[];
}

const key = (ind: string, y: number, s: string, area: string, crop?: string | null) => `${ind}|${y}${s}|${area}|${crop ?? ''}`;

export function indexOfficial(o: OfficialFile | null): Official | null {
  if (!o || !o.rows?.length) return null;
  const by = new Map<string, PubRow>(), ofInd = new Map<string, PubRow[]>();
  for (const r of o.rows) {
    by.set(key(r.indicator, r.sas_year, r.sas_season, r.area, r.crop_name), r);
    const a = ofInd.get(r.indicator); if (a) a.push(r); else ofInd.set(r.indicator, [r]);
  }
  return {
    rows: o.rows, built: o.built,
    src: new Map(o.sources.map((s) => [s.src_id, s])),
    def: new Map(o.definitions.map((d) => [d.indicator, d])),
    get: (ind, y, s, area, crop) => by.get(key(ind, y, s, area, crop)),
    of: (ind) => ofInd.get(ind) ?? [],
  };
}

/** NISR indicators that answer the same question as one of our estimates (same definition) */
export const PUB_FOR_OURS: Record<string, string> = {
  irrig_any_farmer: 'irrig_any_farmer', inorganic_fert: 'inorganic_fert', organic_fert: 'organic_fert', pesticide: 'pesticide',
};

/** the place NISR publishes for this selection: Rwanda, one district, or none */
export const pubArea = (f: Filters): string | null => (f.areaLevel === 'national' ? 'Rwanda' : f.district || null);

export interface YS { y: number; s: Season }
export const ysKey = (x: YS) => `${x.y}${x.s}`;
/** the selected seasons, oldest first */
export function seasonsOf(f: Filters, only?: Season[]): YS[] {
  const S = only ? f.seasons.filter((s) => only.includes(s)) : f.seasons;
  return f.years.flatMap((y) => S.map((s) => ({ y, s }))).sort((a, b) => a.y - b.y || seasonOrder(a.s) - seasonOrder(b.s));
}

/** the newest selected season with a published figure */
export function latest(O: Official | null, ind: string, area: string | null, ss: YS[], crop?: string): PubRow | undefined {
  if (!O || !area) return undefined;
  for (let i = ss.length - 1; i >= 0; i--) {
    const r = O.get(ind, ss[i].y, ss[i].s, area, crop);
    if (r && r.value != null) return r;
  }
  return undefined;
}

/** the same season one year earlier (a change is only ever shown season against same season) */
export const yearBefore = (O: Official, r: PubRow) => O.get(r.indicator, r.sas_year - 1, r.sas_season, r.area, r.crop_name);

/** "NISR SAS 2025, Table 40" */
export function citeShort(O: Official, r: PubRow) {
  const s = O.src.get(r.src_id);
  if (!s) return 'NISR';
  const yr = s.source_file.match(/20\d\d/)?.[0] ?? '';
  return `NISR ${s.survey === 'SAS' ? (/USAS/.test(s.source_file) ? 'USAS' : 'SAS') : s.survey} ${yr}, ${s.nisr_table.replace(/^Table\s*/i, 'Table ')}`;
}
/** the full citation: publication, table and title, sheet and cell, the column NISR prints */
export function cite(O: Official, r: PubRow) {
  const s = O.src.get(r.src_id);
  if (!s) return 'NISR';
  return `${s.source_title} (file “${s.source_file}”, sheet “${s.sheet}”, cell ${r.cell})${s.measure_label ? `. Column: “${s.measure_label}”` : ''}.`;
}
/** who the figure describes, as NISR defines it */
export const popOf = (O: Official | null, ind: string) => O?.def.get(ind)?.population ?? '';
export const unitOf = (O: Official | null, ind: string) => O?.def.get(ind)?.unit ?? '';

/** a published value in its unit */
export function fmtPub(O: Official | null, r: PubRow | undefined | null, d = 1) {
  if (!r || r.value == null) return '–';
  const u = unitOf(O, r.indicator);
  return u === '%' ? fmtPct(r.value, d) : u === 'ha' ? `${fmtNum(r.value)} ha` : u === 't' ? `${fmtNum(r.value)} t` : u === 'kg/ha' ? `${fmtNum(r.value)} kg/ha` : fmtNum(r.value, d);
}

/** the source line under a chart built from published figures */
export function pubSource(O: Official, rows: (PubRow | undefined)[], tr: Tr) {
  const ok = rows.filter((r): r is PubRow => !!r);
  if (!ok.length) return tr('pub_unavailable');
  const tabs = [...new Set(ok.map((r) => citeShort(O, r)))];
  return tr('src_pub', tabs.length > 3 ? `${tabs.slice(0, 3).join('; ')} + ${tabs.length - 3}` : tabs.join('; '), popOf(O, ok[0].indicator));
}

/** CSV rows that keep the provenance of every published figure */
export function pubCsv(O: Official, rows: PubRow[]): Record<string, unknown>[] {
  return rows.map((r) => {
    const s = O.src.get(r.src_id), d = O.def.get(r.indicator);
    return {
      indicator: r.indicator, sas_year: r.sas_year, sas_season: r.sas_season, level: r.level, area: r.area, crop_name: r.crop_name ?? '',
      is_group_subtotal: r.is_group, value: r.value, unit: d?.unit, population: d?.population, definition: d?.definition,
      layer: 'published NISR figure', publication: s?.source_title, file: s?.source_file, sheet: s?.sheet, cell: r.cell, column_label: s?.measure_label,
      project_estimate: r.project_value, decision: DECISION[r.d ?? ''] ?? '',
    };
  });
}
export const DECISION: Record<string, string> = {
  cross_check: 'NISR value shown; project estimate kept as cross-check',
  own_label: 'NISR value shown under its own label; not compared (different definition)',
  no_project: 'NISR value shown; no project estimate',
  blank: 'Published cell blank: shown as unavailable',
};

/** NISR upgraded the survey in 2020 (USAS 2020): a published series is not drawn as one
 *  line across 2019 and 2020. A gap (null) goes between the two years. */
export const FIRST_UPGRADED = 2020;
export function splitAtUpgrade<T>(xs: number[], ys: T[]): { x: (number | null)[]; y: (T | null)[] } {
  const x: (number | null)[] = [], y: (T | null)[] = [];
  xs.forEach((v, i) => { if (i > 0 && xs[i - 1] < FIRST_UPGRADED && v >= FIRST_UPGRADED) { x.push(null); y.push(null); } x.push(v); y.push(ys[i]); });
  return { x, y };
}

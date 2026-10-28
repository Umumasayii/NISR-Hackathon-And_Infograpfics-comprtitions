import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import type { AppData, GeoJSON, I18n, OfficialFile, Season } from './types';
import { initialLang, makeTr, type Lang, type Tr } from '../lib/i18n';
import { shortSet } from '../lib/format';
import { uniq, type Filters } from '../lib/stats';
import { indexOfficial, type Official } from '../lib/official';

// ---- loading ------------------------------------------------------------------------
// Tables come column by column as {"__df": {col: [values]}} (see 12_Export_Web_Data.R)
function revive(x: unknown): unknown {
  if (Array.isArray(x)) return x.map(revive);
  if (x && typeof x === 'object') {
    const o = x as Record<string, unknown>;
    if ('__df' in o && Object.keys(o).length === 1) {
      const cols = o.__df as Record<string, unknown>;
      const names = Object.keys(cols);
      const arr = names.map((k) => (Array.isArray(cols[k]) ? (cols[k] as unknown[]) : [cols[k]]));
      const n = arr.length ? Math.max(...arr.map((a) => a.length)) : 0;
      return Array.from({ length: n }, (_, i) => Object.fromEntries(names.map((k, j) => [k, arr[j][i] ?? null])));
    }
    return Object.fromEntries(Object.entries(o).map(([k, v]) => [k, revive(v)]));
  }
  return x;
}

// Statistics end with 2025 (SAS 2019-2025, AHS 2017-2024): a later season or survey
// round in a data file is dropped here, whatever the file holds.
const LAST_YEAR = 2025;
function inScope(x: unknown): unknown {
  if (Array.isArray(x)) {
    const out = x.map(inScope);
    return out.filter((r) => !(r && typeof r === 'object' && !Array.isArray(r) && ['sas_year', 'year'].some((k) => {
      const v = (r as Record<string, unknown>)[k];
      return typeof v === 'number' && v > LAST_YEAR;
    })));
  }
  if (x && typeof x === 'object') return Object.fromEntries(Object.entries(x as Record<string, unknown>).map(([k, v]) => [k, inScope(v)]));
  return x;
}

/** O: the published NISR figures (null when official.json is missing: pages then show our estimates only) */
export interface Loaded { D: AppData; O: Official | null; geo: GeoJSON; dict: I18n; dataSource: string }

export async function loadAll(): Promise<Loaded> {
  const base = import.meta.env.BASE_URL;
  const get = (f: string) => fetch(`${base}data/${f}`).then((r) => { if (!r.ok) throw new Error(`${f}: ${r.status}`); return r; });
  const [raw, geo, dict, ds, off] = await Promise.all([
    get('app_data.json').then((r) => r.json()), get('districts.json').then((r) => r.json()),
    get('i18n.json').then((r) => r.json()), get('data_source.md').then((r) => r.text()).catch(() => ''),
    get('official.json').then((r) => r.json()).catch(() => null),
  ]);
  const D = inScope(revive(raw)) as AppData;
  const O = indexOfficial(off ? (inScope(revive(off)) as OfficialFile) : null);
  // same guards as the Shiny app: never show "Other (specify)" categories
  const isOther = (s: string | null) => !!s && /^other|specify|unclassified/i.test(s);
  D.crop = D.crop.filter((r) => !isOther(r.crop_name) && !isOther(r.crop_group));
  D.crop_dist = D.crop_dist.filter((r) => !isOther(r.crop_name) && !isOther(r.crop_group));
  return { D, O, geo, dict, dataSource: ds.replace(/<!--[\s\S]*?-->/g, '').trim() };
}

// ---- the selection --------------------------------------------------------------------
export interface Selection { years: number[]; seasons: Season[]; provinces: string[]; districts: string[]; cropGroups: string[]; crops: string[] }

interface Ctx extends Loaded {
  lang: Lang; setLang: (l: Lang) => void; tr: Tr;
  YEARS: number[]; CROP_GRPS: string[]; ALL_CROPS: string[]; ALL_D: string[]; ALL_P: string[];
  sel: Selection; setSel: (s: Partial<Selection>) => void; resetSel: () => void;
  /** a click on any map selects that district only */
  pickDistrict: (d: string) => void;
  f: Filters;
}
const AppCtx = createContext<Ctx | null>(null);
export const useApp = () => { const c = useContext(AppCtx); if (!c) throw new Error('no app context'); return c; };

// v2: the defaults changed to Kayonza (East), so selections saved under the old key are not reused
const SKEY = 'si-selection-v2';
const DEF_PROVINCE = 'East';
const DEF_DISTRICT = 'Kayonza';

export function AppProvider({ data, children }: { data: Loaded; children: ReactNode }) {
  const { D } = data;
  const [lang, setLangState] = useState<Lang>(initialLang);
  const setLang = useCallback((l: Lang) => {
    setLangState(l);
    try { localStorage.setItem('si-lang', l); } catch { /* ignore */ }
    document.documentElement.lang = l === 'rw' ? 'rw' : l;
  }, []);
  useEffect(() => { document.documentElement.lang = lang; }, [lang]);
  const tr = useMemo(() => makeTr(data.dict, lang), [data.dict, lang]);

  const consts = useMemo(() => {
    const YEARS = uniq(D.est.map((r) => r.sas_year)).sort();
    const CROP_GRPS = uniq(D.crop.map((r) => r.crop_group).filter(Boolean)).sort();
    const ALL_CROPS = uniq(D.crop.map((r) => r.crop_name)).sort();
    const ALL_D = D.lookup.map((r) => r.district);
    const ALL_P = uniq(D.lookup.map((r) => r.province)).sort();
    return { YEARS, CROP_GRPS, ALL_CROPS, ALL_D, ALL_P };
  }, [D]);
  const { YEARS, CROP_GRPS, ALL_CROPS, ALL_D, ALL_P } = consts;

  // the app opens on one district (Kayonza, East) so every page starts with a concrete example;
  // falls back to the whole country if the data ever lacks them
  const fresh = useCallback((): Selection => ({
    years: YEARS, seasons: ['A', 'B'],
    provinces: ALL_P.includes(DEF_PROVINCE) ? [DEF_PROVINCE] : ALL_P,
    districts: ALL_D.includes(DEF_DISTRICT) ? [DEF_DISTRICT] : ALL_D,
    cropGroups: CROP_GRPS, crops: ALL_CROPS,
  }), [YEARS, ALL_P, ALL_D, CROP_GRPS, ALL_CROPS]);
  const [sel, setSelState] = useState<Selection>(() => {
    try { const s = sessionStorage.getItem(SKEY); if (s) return { ...fresh(), ...JSON.parse(s) }; } catch { /* ignore */ }
    return fresh();
  });
  useEffect(() => { try { sessionStorage.setItem(SKEY, JSON.stringify(sel)); } catch { /* ignore */ } }, [sel]);

  const setSel = useCallback((p: Partial<Selection>) => setSelState((s) => {
    const next = { ...s, ...p };
    // province -> district list: keep what is still valid; a full list follows the provinces
    if (p.provinces) {
      const scopeOld = D.lookup.filter((r) => (s.provinces.length ? s.provinces : ALL_P).includes(r.province)).map((r) => r.district);
      const scope = D.lookup.filter((r) => (p.provinces!.length ? p.provinces! : ALL_P).includes(r.province)).map((r) => r.district);
      const wasAll = !s.districts.length || scopeOld.every((d) => s.districts.includes(d));
      const keep = wasAll ? scope : s.districts.filter((d) => scope.includes(d));
      next.districts = keep.length ? keep : scope;
    }
    // crop group -> crop list
    if (p.cropGroups) {
      const G = p.cropGroups.length ? p.cropGroups : CROP_GRPS;
      next.crops = uniq(D.crop.filter((r) => G.includes(r.crop_group)).map((r) => r.crop_name)).sort();
    }
    return next;
  }), [D, ALL_P, CROP_GRPS]);
  const resetSel = useCallback(() => setSelState(fresh()), [fresh]);
  const pickDistrict = useCallback((d: string) => {
    if (!ALL_D.includes(d)) return;
    setSelState((s) => ({ ...s, provinces: ALL_P, districts: [d] }));
  }, [ALL_D, ALL_P]);

  // one object with every filter (the Shiny app's f())
  const f = useMemo<Filters>(() => {
    const pick = <T,>(x: T[], all: T[]) => (x.length ? all.filter((v) => x.includes(v)) : all);
    const years = pick(sel.years, YEARS);
    const seasons = sel.seasons.length ? (['A', 'B', 'C'] as Season[]).filter((s) => sel.seasons.includes(s)) : (['A', 'B'] as Season[]);
    const provs = pick(sel.provinces, ALL_P);
    const scope = D.lookup.filter((r) => provs.includes(r.province)).map((r) => r.district);
    const dists = pick(sel.districts, scope).length ? pick(sel.districts, scope) : scope;
    const areaLevel = dists.length < scope.length ? 'district' : provs.length < ALL_P.length ? 'province' : 'national';
    const areas = areaLevel === 'district' ? dists : areaLevel === 'province' ? provs : ['Rwanda'];
    const grps = pick(sel.cropGroups, CROP_GRPS);
    const cropScope = uniq(D.crop.filter((r) => grps.includes(r.crop_group)).map((r) => r.crop_name));
    const crops = sel.crops.filter((c) => cropScope.includes(c));
    return {
      years, seasons, areaLevel, areas, districts: dists,
      provinces: uniq(D.lookup.filter((r) => dists.includes(r.district)).map((r) => r.province)).sort(),
      area: areaLevel === 'national' ? 'Rwanda' : shortSet(areas),
      district: areaLevel === 'district' && dists.length === 1 ? dists[0] : '',
      cropGroups: grps.length < CROP_GRPS.length ? grps : [],
      crops: crops.length && crops.length < cropScope.length ? crops : [],
    };
  }, [sel, D, YEARS, ALL_P, CROP_GRPS]);

  const value: Ctx = { ...data, lang, setLang, tr, ...consts, sel, setSel, resetSel, pickDistrict, f };
  return <AppCtx.Provider value={value}>{children}</AppCtx.Provider>;
}

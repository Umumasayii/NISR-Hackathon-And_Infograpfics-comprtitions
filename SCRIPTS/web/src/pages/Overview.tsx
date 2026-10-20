import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  Droplet, Sprout, Users, Trophy, Wheat, HandCoins, Waves, Cog, UserCheck, FlaskConical, Sun, ChartLine, Layers,
  Database, Landmark, Scale,
} from 'lucide-react';
import type { Data } from 'plotly.js';
import { useApp } from '../data/store';
import { ChartCard, FiltersUsed, Grid, Insight, InsightGrid, Kpi, KpiRow, RelBadge, SectionTitle, Select, relLabel, type AltTable } from '../components/ui';
import { Plot, simpleLines, std, type Fig } from '../components/Plot';
import { ahsFor, ahsVal, byYear, cropsFor, estFor, groupBy, in100, last, sum, totalsFor, wm, mean, seasonOrder, type YearRow } from '../lib/stats';
import { fmtNum, fmtPct, seasonLabel } from '../lib/format';
import { brand, colMuted, seasonCols, seriesCols } from '../lib/theme';
import { SOURCES, pubSrc, type Prov, type SrcId } from '../lib/sources';
import type { Est, Official, Season } from '../data/types';

const TREND_INDS = ['irrigated', 'irrig_modern', 'irrig_any_farmer', 'inorganic_fert', 'organic_fert', 'anti_erosion'];
const STAPLES = ['Maize', 'Bush bean', 'Climbing bean', 'Small red bean', 'Irish potato', 'Paddy rice', 'Cassava', 'Wheat', 'Cooking banana', 'Dessert banana', 'Banana for beer'];
/** what each trend indicator counts, and over whom */
const UNIT: Record<string, string> = {
  irrigated: 'u_pct_plots', irrig_modern: 'u_pct_irr_plots', irrig_any_farmer: 'u_pct_farmers',
  inorganic_fert: 'u_pct_plots', organic_fert: 'u_pct_plots', anti_erosion: 'u_pct_plots',
};
// published production for 2024B–2026B comes from the crop tables of the 2026 workbooks (SCRIPTS/11_NISR_Published_Tables.R)
const PROD_SRC: SrcId[] = ['sas2026a', 'sas2026b'];
// a marker shape per season as well as a colour
const SEASON_SYM: Record<string, string> = { A: 'circle', B: 'square', C: 'triangle-up' };
const seasonKey = (r: { sas_year: number; sas_season: string }) => r.sas_year * 10 + seasonOrder(r.sas_season);

export default function Overview() {
  const { D, f, tr } = useApp();
  const [trendInd, setTrendInd] = useState('irrigated');
  const ab = (fb: Season[] = ['A', 'B']) => { const s = f.seasons.filter((x) => fb.includes(x)); return s.length ? s : fb; };
  // yearly series for an indicator (weighted mean of the chosen main seasons)
  const yearly = (ind: string, seasons: Season[] = ['A', 'B']) =>
    byYear(estFor(D, f, ind, f.years, seasons.length === 1 && seasons[0] === 'C' ? ['C'] : ab(seasons)));
  const official: Official[] = D.meta.official ?? [];
  const national = f.areaLevel === 'national';
  const period = (d: { sas_year: number }[]) => (!d.length ? undefined : d.length === 1 ? String(d[0].sas_year) : `${d[0].sas_year}–${last(d).sas_year}`);

  // ---- number cards ----------------------------------------------------------------
  const tiles = useMemo(() => {
    const irr = yearly('irrigated'), mod = yearly('irrig_modern'), anyf = yearly('irrig_any_farmer');
    const fert = yearly('inorganic_fert'), sc = yearly('irrigated', ['C']);
    const tt = totalsFor(D, f).filter((r) => r.sas_season !== 'C');
    // areas: average per main season (A and B farm the same land); harvests: added up
    const totAll = [...groupBy(tt, (r) => String(r.sas_year)).values()].map((g) => ({
      sas_year: g[0].sas_year, ha: mean(g.map((r) => r.irrigated_area_ha)), t: sum(g.map((r) => r.production_t)), cult: mean(g.map((r) => r.cultivated_area_ha)),
      src: g.every((r) => r.totals_source === 'nisr') ? 'nisr' : g.some((r) => r.totals_source === 'nisr') ? 'mixed' : 'survey',
    })).sort((a, b) => a.sas_year - b.sas_year);
    const tot = totAll.filter((r) => Number.isFinite(r.ha));
    const maize = D.model_yield.table.find((r) => r.crop_name === 'Maize');
    return { irr, mod, anyf, fert, sc, tot, totAll, maize };
  }, [D, f]);

  // A published year is never averaged across seasons: the card shows the latest published season as published
  const latestPub = (ind: string): Est | null => {
    const e = estFor(D, f, ind, f.years, ab()).filter((r) => r.source === 'nisr').sort((a, b) => seasonKey(a) - seasonKey(b));
    return e.length ? last(e) : null;
  };
  const isPub = (d: YearRow[]) => d.length > 0 && last(d).source === 'nisr';
  const lst = (d: YearRow[], ind: string) => (!d.length ? NaN : isPub(d) ? latestPub(ind)?.estimate ?? NaN : last(d).estimate);
  // change since the first selected year, survey years only (published figures are another source)
  const dlt = (d: YearRow[]) => { const s = d.filter((r) => r.source === 'survey'); return isPub(d) || s.length < 2 ? null : last(s).estimate - s[0].estimate; };
  const yr = (d: YearRow[], ind: string) => {
    if (!d.length) return '';
    if (!isPub(d)) return <span>{last(d).sas_year} · {tr('kind_survey')}</span>;
    const p = latestPub(ind);
    return <span className="st-pub"><Landmark size={12} aria-hidden="true" /> {tr('rb_published')} {p ? seasonLabel(p.sas_year, p.sas_season) : last(d).sas_year}{p?.nisr_table ? ` · ${p.nisr_table}` : ''}</span>;
  };
  const kpiProv = (d: YearRow[], ind: string, unit: string, note?: string): Prov => {
    const p = isPub(d) ? latestPub(ind) : null;
    return p
      ? { unit: tr(unit), period: seasonLabel(p.sas_year, p.sas_season), kind: 'official', src: pubSrc(`${p.sas_year}${p.sas_season}`), tables: p.nisr_table ? [p.nisr_table] : undefined, note }
      : { unit: tr(unit), period: period(d), kind: 'survey', src: ['sas_micro'], note };
  };
  const { irr, mod, anyf, fert, sc, tot, totAll, maize } = tiles;
  const lastTot = tot.length ? last(tot) : null, lastAll = totAll.length ? last(totAll) : null;

  // ---- NISR published vs project estimate --------------------------------------------
  const recon = useMemo(() => {
    const off = official.filter((o) => o.indicator === 'irrig_any_farmer' && o.level === 'national').sort((a, b) => seasonKey(a) - seasonKey(b));
    const sv = D.est.filter((r) => r.level === 'national' && r.indicator === 'irrig_any_farmer' && r.source === 'survey');
    const rows = off.map((o) => {
      const s = sv.find((r) => r.sas_year === o.sas_year && r.sas_season === o.sas_season);
      return { o, s, diff: s ? s.estimate - o.value : NaN };
    });
    const both = rows.filter((r) => Number.isFinite(r.diff));
    return { rows, maxDiff: both.length ? Math.max(...both.map((r) => Math.abs(r.diff))) : NaN };
  }, [D, official]);
  const reconSrc = (o: Official): SrcId[] => pubSrc(`${o.sas_year}${o.sas_season}`);
  const defs = useMemo(() => {
    const sv = D.est.filter((r) => r.level === 'national' && r.indicator === 'irrig_modern' && r.source === 'survey' && r.sas_season !== 'C').sort((a, b) => seasonKey(a) - seasonKey(b));
    const ly = sv.length ? last(sv).sas_year : null;
    const fmtSeasons = (x: { sas_year: number; sas_season: string; v: number }[]) => x.map((r) => `${seasonLabel(r.sas_year, r.sas_season)}: ${fmtPct(r.v)}`).join(' · ');
    const pick = (ind: string) => official.filter((o) => o.indicator === ind).sort((a, b) => seasonKey(a) - seasonKey(b));
    return [
      { label: tr('recon_def_survey'), unit: tr('u_pct_irr_plots'), val: fmtSeasons(sv.filter((r) => r.sas_year === ly).map((r) => ({ ...r, v: r.estimate }))), src: [] as Official[], kind: 'survey' as const },
      { label: tr('def_nisr_modern'), unit: tr('u_pct_irr_plots'), val: fmtSeasons(pick('modern_irrig_share').map((o) => ({ ...o, v: o.value }))), src: pick('modern_irrig_share'), kind: 'official' as const },
      { label: tr('def_dsp'), unit: tr('u_pct_irr_plots'), val: fmtSeasons(pick('irrig_dsp_nisr').map((o) => ({ ...o, v: o.value }))), src: pick('irrig_dsp_nisr'), kind: 'official' as const },
      { label: tr('def_farmers_modern'), unit: tr('u_pct_irr_farmers'), val: fmtSeasons(pick('modern_irrig_farmers').map((o) => ({ ...o, v: o.value }))), src: pick('modern_irrig_farmers'), kind: 'official' as const },
    ];
  }, [D, official, tr]);

  // ---- findings ------------------------------------------------------------------------
  const findings = useMemo(() => {
    const a = yearly('irrigated');
    if (a.length < 2) return null;
    const eq = D.equity.equity.filter((r) => r.dimension === 'gender');
    const cs = D.equity.equity.filter((r) => r.dimension === 'consolidated');
    const top = [...D.screen.table].sort((x, y) => x.rank - y.rank).slice(0, 3);
    const ya = D.model_yield.table.filter((r) => r.adjusted_low > 0).sort((x, y) => y.adjusted_pct - x.adjusted_pct);
    const hd = ahsFor(D, f);
    const hv = (ind: string, y: number) => ahsVal(hd, ind, y);
    // main food crops: harvest change between survey-only years, so both ends come from one source
    const rows = cropsFor(D, { ...f, seasons: ab(), crops: [], cropGroups: [] }).filter((r) => STAPLES.includes(r.crop_name));
    const pc = [...groupBy(rows, (r) => String(r.sas_year)).values()]
      .filter((g) => g.every((r) => (r.production_source ?? 'survey') === 'survey') && new Set(g.map((r) => r.sas_season)).size === ab().length)
      .map((g) => ({ y: g[0].sas_year, t: sum(g.map((r) => r.production_t)) / 1000 })).sort((x, y) => x.y - y.y);
    const ch = pc.length >= 2 ? 100 * (last(pc).t / pc[0].t - 1) : NaN;
    return { a, eq, cs, top, ya, hv, pc, ch };
  }, [D, f]);

  // ---- charts --------------------------------------------------------------------------
  const trendE = useMemo(() => estFor(D, f, trendInd), [D, f, trendInd]);
  // NISR published farmer figures for seasons that also have survey microdata (national only)
  const trendOff = useMemo(() => (national && trendInd === 'irrig_any_farmer'
    ? official.filter((o) => o.indicator === 'irrig_any_farmer' && o.level === 'national' && f.years.includes(o.sas_year) && f.seasons.includes(o.sas_season) && o.sas_year < 2026)
    : []), [official, national, trendInd, f]);
  const trendFig = useMemo<Fig | null>(() => {
    if (!trendE.length) return null;
    const data: Data[] = [];
    for (const s of ['A', 'B', 'C'] as Season[]) {
      const sv = trendE.filter((r) => r.sas_season === s && r.source === 'survey').sort((a, b) => a.sas_year - b.sas_year);
      if (sv.length) data.push({
        x: sv.map((r) => r.sas_year), y: sv.map((r) => r.estimate), type: 'scatter', mode: 'lines+markers', name: tr(`season_${s.toLowerCase()}`),
        line: { color: seasonCols[s], shape: 'spline', smoothing: 0.5 }, marker: { color: seasonCols[s], symbol: SEASON_SYM[s], size: 8 },
        error_y: { type: 'data', symmetric: false, array: sv.map((r) => (r.ci_high ?? r.estimate) - r.estimate), arrayminus: sv.map((r) => r.estimate - (r.ci_low ?? r.estimate)), color: seasonCols[s], thickness: 1, width: 3 },
        text: sv.map((r) => `${r.sas_year}${s}: <b>${fmtPct(r.estimate)}</b> (95% CI ${fmtPct(r.ci_low)}–${fmtPct(r.ci_high)}) · n = ${fmtNum(r.n)} · ${relLabel(tr, r.reliability)}`), hoverinfo: 'text',
      });
      // NISR published seasons: their own open marker, never joined to the survey line
      const pb = [
        ...trendE.filter((r) => r.sas_season === s && r.source === 'nisr').map((r) => ({ x: r.sas_year, y: r.estimate, t: r.nisr_table ?? '' })),
        ...trendOff.filter((o) => o.sas_season === s).map((o) => ({ x: o.sas_year, y: o.value, t: o.table_or_section })),
      ];
      if (pb.length) data.push({
        x: pb.map((r) => r.x), y: pb.map((r) => r.y), type: 'scatter', mode: 'markers', name: `${tr(`season_${s.toLowerCase()}`)} · ${tr('rb_published')}`,
        marker: { size: 11, symbol: 'diamond-open', color: seasonCols[s], line: { width: 2.5 } },
        text: pb.map((r) => `${r.x}${s}: <b>${fmtPct(r.y)}</b> · ${tr('rb_published')} (${r.t})`), hoverinfo: 'text',
      });
    }
    return simpleLines(data, std({ y: tr(UNIT[trendInd]), xaxis: { dtick: 1 }, yaxis: { ticksuffix: '%' } }));
  }, [trendE, trendOff, trendInd, tr]);
  const trendMeans = useMemo(() => {
    const e = trendE.filter((r) => r.sas_season !== 'C' && r.source === 'survey').sort((a, b) => seasonKey(a) - seasonKey(b));
    if (e.length < 2) return null;
    const a = e[0], b = last(e);
    if (a.ci_low == null || b.ci_low == null) return null;
    const sig = (b.ci_low ?? 0) > (a.ci_high ?? Infinity) || (b.ci_high ?? Infinity) < (a.ci_low ?? 0);
    return tr(!sig ? 'mt_flat' : b.estimate > a.estimate ? 'mt_up' : 'mt_down', f.area, tr(`ind_${trendInd}`),
      fmtPct(a.estimate), seasonLabel(a.sas_year, a.sas_season), fmtPct(b.estimate), seasonLabel(b.sas_year, b.sas_season));
  }, [trendE, trendInd, f.area, tr]);
  const trendHasPub = trendE.some((r) => r.source === 'nisr') || trendOff.length > 0;
  const trendProv: Prov = {
    unit: tr(UNIT[trendInd]), period: period([...trendE].sort((a, b) => a.sas_year - b.sas_year)), kind: trendHasPub ? 'mixed' : 'survey',
    src: ['sas_micro', ...new Set([...trendE.filter((r) => r.source === 'nisr').flatMap((r) => pubSrc(`${r.sas_year}${r.sas_season}`)), ...trendOff.flatMap(reconSrc)])],
    tables: [...new Set([...trendE.map((r) => r.nisr_table).filter((x): x is string => !!x), ...trendOff.map((o) => `${o.sas_year}${o.sas_season} ${o.table_or_section}`)])],
    note: [trendInd === 'irrig_any_farmer' ? tr('n_irrig_def') : '', trendInd === 'irrig_modern' ? tr('n_modern_def') : '', trendHasPub ? tr('n_break_2026') : '',
      ['inorganic_fert', 'organic_fert'].includes(trendInd) ? tr('lim_4') : ''].filter(Boolean).join(' '),
  };
  const trendTable: AltTable = {
    name: `trend_${trendInd}`,
    rows: [
      ...trendE.map((r) => ({ s: seasonLabel(r.sas_year, r.sas_season), k: seasonKey(r), v: r.estimate, lo: r.ci_low, hi: r.ci_high, n: r.source === 'survey' ? r.n : null, q: relLabel(tr, r.reliability), src: r.source === 'nisr' ? `${tr('rb_published')} (${r.nisr_table ?? ''})` : tr('kind_survey') })),
      ...trendOff.map((o) => ({ s: seasonLabel(o.sas_year, o.sas_season), k: seasonKey(o) + 0.5, v: o.value, lo: null, hi: null, n: null, q: relLabel(tr, 'Published'), src: `${tr('rb_published')} (${o.table_or_section})` })),
    ].sort((a, b) => a.k - b.k),
    cols: [
      { label: tr('recon_season'), get: (r: { s: string }) => r.s },
      { label: '%', get: (r: { v: number }) => fmtPct(r.v), num: true },
      { label: '95% CI', get: (r: { lo: number | null; hi: number | null }) => (r.lo == null ? null : `${fmtPct(r.lo)}–${fmtPct(r.hi)}`), num: true },
      { label: 'n', get: (r: { n: number | null }) => (r.n == null ? null : fmtNum(r.n)), num: true },
      { label: tr('quality'), get: (r: { q: string }) => r.q },
      { label: tr('src_type').replace(':', ''), get: (r: { src: string }) => r.src },
    ] as AltTable['cols'],
  };

  const inputs = useMemo(() => {
    const ind = ['irrigated', 'inorganic_fert', 'organic_fert', 'pesticide', 'anti_erosion', 'mechanised', 'agroforestry', 'land_consolidated'];
    // one survey season set, so every bar has the same definition and year
    const e = estFor(D, f, ind, f.years, ab(['A'])).filter((r) => r.source === 'survey');
    if (!e.length) return [];
    const ly = Math.max(...e.map((r) => r.sas_year));
    return [...groupBy(e.filter((r) => r.sas_year === ly), (r) => r.indicator).values()].map((g) => ({
      indicator: g[0].indicator, label: tr(`ind_${g[0].indicator}`), year: ly, n: sum(g.map((r) => r.n)),
      seasons: [...new Set(g.map((r) => r.sas_season))].join('+'),
      estimate: wm(g.map((r) => r.estimate), g.map((r) => r.wsum)), ci_low: wm(g.map((r) => r.ci_low), g.map((r) => r.wsum)), ci_high: wm(g.map((r) => r.ci_high), g.map((r) => r.wsum)),
    })).sort((a, b) => a.estimate - b.estimate);
  }, [D, f, tr]);
  const inputsFig = useMemo<Fig | null>(() => !inputs.length ? null : {
    data: [{
      type: 'bar', orientation: 'h', y: inputs.map((r) => r.label), x: inputs.map((r) => r.estimate),
      marker: { color: inputs.map((r) => (r.indicator === 'irrigated' ? brand.blue : colMuted)) },
      text: inputs.map((r) => fmtPct(r.estimate, 0)), textposition: 'outside', cliponaxis: false, textfont: { size: 12, color: brand.ink },
      hovertext: inputs.map((r) => `<b>${r.label}</b><br>${fmtPct(r.estimate)} (95% CI ${fmtPct(r.ci_low)}–${fmtPct(r.ci_high)})<br>n = ${fmtNum(r.n)}`), hoverinfo: 'text',
    }],
    layout: std({ x: tr('u_pct_plots'), legend: false, bargap: 0.4, yaxis: { title: { text: '' }, ticksuffix: '  ' }, xaxis: { range: [0, Math.max(...inputs.map((r) => r.estimate), 1) * 1.18], ticksuffix: '%' } }),
  }, [inputs, tr]);

  const prov = useMemo(() => {
    const S = new Set(ab(['A'])), Y = new Set(f.years), P = new Set(f.provinces);
    const d = D.est.filter((r) => r.level === 'province' && r.indicator === 'irrigated' && r.source === 'survey' && S.has(r.sas_season) && Y.has(r.sas_year) && P.has(r.area));
    return [...groupBy(d, (r) => `${r.area}|${r.sas_year >= 2023 ? '2023-2025' : '2019-2022'}`).values()].map((g) => ({
      area: g[0].area, period: g[0].sas_year >= 2023 ? '2023-2025' : '2019-2022', estimate: wm(g.map((r) => r.estimate), g.map((r) => r.wsum)), n: sum(g.map((r) => r.n)),
    }));
  }, [D, f]);
  const provFig = useMemo<Fig | null>(() => {
    if (!prov.length) return null;
    const maxP = prov.some((r) => r.period === '2023-2025') ? '2023-2025' : '2019-2022';
    const ord = prov.filter((r) => r.period === maxP).sort((a, b) => a.estimate - b.estimate).map((r) => r.area);
    const data: Data[] = [];
    // two periods told apart by marker shape as well as colour
    const pcol: Record<string, { c: string; s: string }> = { '2019-2022': { c: '#7FA791', s: 'circle-open' }, '2023-2025': { c: brand.blue, s: 'circle' } };
    for (const a of ord) {
      const p = prov.filter((r) => r.area === a);
      if (p.length === 2) data.push({ type: 'scatter', mode: 'lines', x: p.map((r) => r.estimate), y: [a, a], line: { color: '#D5DDD8', width: 5 }, hoverinfo: 'skip', showlegend: false });
    }
    for (const pp of Object.keys(pcol)) {
      const x = prov.filter((r) => r.period === pp); if (!x.length) continue;
      data.push({ type: 'scatter', mode: 'markers', name: pp, x: x.map((r) => r.estimate), y: x.map((r) => r.area),
        marker: { size: 14, symbol: pcol[pp].s, color: pcol[pp].c, line: { color: pcol[pp].s === 'circle' ? '#fff' : pcol[pp].c, width: 2 } },
        text: x.map((r) => `<b>${r.area}</b> ${pp}<br>${fmtPct(r.estimate)} · n = ${fmtNum(r.n)}`), hoverinfo: 'text' });
    }
    return { data, layout: std({ x: tr('u_pct_plots_ab'), xaxis: { ticksuffix: '%' }, yaxis: { title: { text: '' }, categoryorder: 'array', categoryarray: ord }, legend: true }) };
  }, [prov, tr]);

  const prod = useMemo(() => [...groupBy(cropsFor(D, { ...f, seasons: ab() }), (r) => `${r.sas_year}|${r.crop_group}`).values()].map((g) => ({
    sas_year: g[0].sas_year, crop_group: g[0].crop_group, t: sum(g.map((r) => r.production_t)),
    src: g.every((r) => r.production_source === 'nisr') ? 'nisr' : g.some((r) => r.production_source === 'nisr') ? 'mixed' : 'survey',
  })), [D, f]);
  const prodFig = useMemo<Fig | null>(() => {
    if (!prod.length) return null;
    const grp = [...groupBy(prod, (r) => r.crop_group).entries()].map(([k, g]) => ({ k, t: sum(g.map((r) => r.t)) })).sort((a, b) => b.t - a.t);
    // the four largest groups only, as lines (no "Other" bucket)
    const top = grp.slice(0, 4).map((x) => x.k);
    const sym = ['circle', 'square', 'diamond', 'triangle-up'];
    return simpleLines(top.map((g, i) => {
        const x = prod.filter((r) => r.crop_group === g).sort((a, b) => a.sas_year - b.sas_year);
        return { type: 'scatter', mode: 'lines+markers', name: g, x: x.map((r) => r.sas_year), y: x.map((r) => r.t / 1000),
          line: { color: seriesCols[i] }, marker: { color: seriesCols[i], symbol: sym[i] },
          text: x.map((r) => (r.src === 'survey' ? tr('kind_survey') : r.src === 'nisr' ? tr('rb_published') : tr('n_mixed_year'))),
          hovertemplate: `${g} %{x}: <b>%{y:,.0f} kt</b><br>%{text}<extra></extra>` } as Data;
      }), std({ y: tr('u_kt'), xaxis: { tickformat: 'd', tickangle: 0 }, yaxis: { ticksuffix: ' kt' } }));
  }, [prod, tr]);
  const prodMeans = useMemo(() => {
    if (!prod.length) return null;
    const grp = [...groupBy(prod, (r) => r.crop_group).entries()].map(([k, g]) => ({ k, t: sum(g.map((r) => r.t)) })).sort((a, b) => b.t - a.t);
    return tr('m_prod', grp[0].k, fmtPct((100 * grp[0].t) / sum(grp.map((x) => x.t)), 0));
  }, [prod, tr]);
  const prodPub = prod.some((r) => r.src !== 'survey');
  const prodYears = [...new Set(prod.map((r) => r.sas_year))].sort((a, b) => a - b);

  const scD = useMemo(() => estFor(D, f, 'irrigated', f.years, ['C']).sort((a, b) => a.sas_year - b.sas_year), [D, f]);
  const mainAvg = useMemo(() => { const v = yearly('irrigated'); return v.length ? mean(v.map((r) => r.estimate)) : NaN; }, [D, f]);
  const scFig = useMemo<Fig | null>(() => !scD.length ? null : {
    data: [{ type: 'bar', x: scD.map((r) => r.sas_year), y: scD.map((r) => r.estimate), marker: { color: '#B07A1C' },
      error_y: { type: 'data', symmetric: false, array: scD.map((r) => (r.ci_high ?? r.estimate) - r.estimate), arrayminus: scD.map((r) => r.estimate - (r.ci_low ?? r.estimate)), color: brand.ink, thickness: 1, width: 3 },
      text: scD.map((r) => fmtPct(r.estimate, 0)), textposition: 'outside', cliponaxis: false, textfont: { color: brand.ink, size: 12 },
      hovertext: scD.map((r) => `<b>${r.sas_year}C</b><br>${fmtPct(r.estimate)} (95% CI ${fmtPct(r.ci_low)}–${fmtPct(r.ci_high)})<br>n = ${fmtNum(r.n)} · ${relLabel(tr, r.reliability)}`), hoverinfo: 'text' }],
    layout: std({ y: tr('u_pct_plots_c'), legend: false, bargap: 0.4, xaxis: { dtick: 1 }, yaxis: { ticksuffix: '%', range: [0, Math.max(...scD.map((r) => r.ci_high ?? r.estimate), mainAvg || 0, 1) * 1.2] },
      margin: { l: 10, r: 88, t: 10, b: 10 },
      // the main seasons as a reference, so the dry-season bars read against it
      shapes: Number.isFinite(mainAvg) ? [{ type: 'line', xref: 'paper', x0: 0, x1: 1, y0: mainAvg, y1: mainAvg, line: { color: brand.ink, width: 1.5, dash: 'dot' } }] : [],
      annotations: Number.isFinite(mainAvg) ? [{ xref: 'paper', x: 1, xanchor: 'left', xshift: 4, y: mainAvg, yanchor: 'middle', showarrow: false, align: 'left',
        text: tr('main_avg', `<br><b>${fmtPct(mainAvg, 0)}</b>`), font: { size: 11.5, color: brand.ink } }] : [] }),
  }, [scD, mainAvg, tr]);

  const hi = inputs.length ? last(inputs) : null, irrIn = inputs.find((r) => r.indicator === 'irrigated');
  const provLatest = (() => { const p = prov.filter((r) => r.period === (prov.some((x) => x.period === '2023-2025') ? '2023-2025' : '2019-2022')).sort((a, b) => b.estimate - a.estimate); return p; })();
  const lastRecon = recon.rows.length ? last(recon.rows) : null;
  const totProv: Prov = { unit: tr('u_ha_irr'), period: lastTot ? String(lastTot.sas_year) : undefined, kind: 'survey', src: ['sas_micro'], note: tr('n_area') };
  const prodKind = lastAll?.src === 'nisr' ? 'official' : lastAll?.src === 'mixed' ? 'mixed' : 'survey';

  return (
    <>
      <div className="hero">
        <div className="hero-text">
          <h1>SmartIrrigate Rwanda</h1>
          <div className="decision">
            <p className="decision-q">{tr('dq')}</p>
            <p>{tr('dq_sub')}</p>
          </div>
          <div className="hero-meta"><span><Database size={14} aria-hidden="true" /> {tr('hero_data')}</span></div>
          <ol className="path" aria-label={tr('dq')}>
            <li><Link to="/need"><span><b>{tr('path_1_t')}</b><span>{tr('path_1')}</span></span></Link></li>
            <li><Link to="/map"><span><b>{tr('path_2_t')}</b><span>{tr('path_2')}</span></span></Link></li>
            <li><Link to="/methods" state={{ tab: 'limits' }}><span><b>{tr('path_3_t')}</b><span>{tr('path_3')}</span></span></Link></li>
            <li><Link to="/priority"><span><b>{tr('path_4_t')}</b><span>{tr('path_4')}</span></span></Link></li>
          </ol>
        </div>
        <div className="hero-hills" />
      </div>

      <FiltersUsed used={['years', 'seasons', 'area']} />
      <SectionTitle title={tr('s_numbers')} />
      <KpiRow>
        <Kpi label={tr('k_irrigated')} value={fmtPct(lst(irr, 'irrigated'))} icon={Droplet} color={brand.blue} delta={dlt(irr)}
          foot={<>{yr(irr, 'irrigated')}<RelBadge r={irr.length ? last(irr).rel : null} /></>}
          prov={kpiProv(irr, 'irrigated', 'u_pct_plots_ab')} />
        <Kpi label={tr('k_area')} value={`${fmtNum(lastTot?.ha)} ha`} icon={Waves} color="#00897B"
          hint={tr('k_area_sub2', fmtPct(lastTot ? (100 * lastTot.ha) / lastTot.cult : NaN))} foot={lastTot ? String(lastTot.sas_year) : null} prov={totProv} />
        <Kpi label={tr('k_modern')} value={fmtPct(lst(mod, 'irrig_modern'))} icon={Cog} color="#B07A1C" delta={dlt(mod)} hint={tr('k_modern_sub2')}
          foot={<>{yr(mod, 'irrig_modern')}<RelBadge r={mod.length ? last(mod).rel : null} /></>}
          prov={kpiProv(mod, 'irrig_modern', 'u_pct_irr_plots', tr('n_modern_def'))} />
        <Kpi label={tr('ind_irrig_any_farmer')} value={fmtPct(lst(anyf, 'irrig_any_farmer'))} icon={UserCheck} color={brand.green} delta={dlt(anyf)}
          hint={tr('k_any_sub')} foot={<>{yr(anyf, 'irrig_any_farmer')}{!isPub(anyf) && <RelBadge r={anyf.length ? last(anyf).rel : null} />}</>}
          prov={kpiProv(anyf, 'irrig_any_farmer', 'u_pct_farmers', tr('n_irrig_def'))} />
      </KpiRow>
      <KpiRow>
        <Kpi label={tr('ind_inorganic_fert')} value={fmtPct(lst(fert, 'inorganic_fert'))} icon={FlaskConical} color="#6A4C93" delta={dlt(fert)} hint={tr('k_fert_sub')}
          foot={<>{yr(fert, 'inorganic_fert')}{!isPub(fert) && <RelBadge r={fert.length ? last(fert).rel : null} />}</>}
          prov={kpiProv(fert, 'inorganic_fert', 'u_pct_plots', isPub(fert) ? tr('lim_4') : undefined)} />
        <Kpi label={tr('k_production')} value={`${fmtNum(lastAll ? lastAll.t / 1000 : NaN)} kt`} icon={Wheat} color="#B07A1C"
          foot={lastAll ? <>{lastAll.sas_year} · {lastAll.src === 'mixed' ? tr('n_mixed_year') : lastAll.src === 'nisr' ? tr('rb_published') : tr('kind_survey')}</> : null}
          hint={tr('k_production_sub')}
          prov={{ unit: tr('u_kt'), period: lastAll ? String(lastAll.sas_year) : undefined, kind: prodKind,
            src: prodKind === 'survey' ? ['sas_micro'] : prodKind === 'official' ? PROD_SRC : ['sas_micro', ...PROD_SRC],
            note: prodKind === 'survey' ? undefined : tr('n_prod_mixed') }} />
        <Kpi label={tr('k_season_c')} value={fmtPct(lst(sc, 'irrigated'))} icon={Sun} color={brand.terracotta} delta={dlt(sc)} hint={tr('k_season_c_sub')}
          foot={<>{yr(sc, 'irrigated')}<RelBadge r={sc.length ? last(sc).rel : null} /></>}
          prov={kpiProv(sc, 'irrigated', 'u_pct_plots_c', tr('n_season_c'))} />
        <Kpi label={tr('k_maize')} value={maize ? `+${fmtNum(maize.adjusted_pct, 0)}%` : '–'} icon={Sprout} color={brand.green}
          foot={maize ? tr('k_maize_foot') : null}
          hint={maize ? tr('k_maize_sub', fmtNum(maize.adjusted_low, 0), fmtNum(maize.adjusted_high, 0), fmtNum(maize.raw_pct, 0)) : undefined}
          prov={{ unit: tr('u_yield_diff'), period: '2019–2025', kind: 'model', src: ['sas_micro'], note: `${tr('n_assoc')} ${tr('n_yield_excl')}` }} />
      </KpiRow>

      <SectionTitle title={tr('s_official')} />
      <Grid cols="1fr 1fr">
        <ChartCard title={tr('recon_title')} icon={Scale} chart={false}
          means={lastRecon ? tr('recon_means', fmtPct(lastRecon.o.value), seasonLabel(lastRecon.o.sas_year, lastRecon.o.sas_season), fmtNum(recon.maxDiff, 1)) : null}
          prov={{ unit: tr('u_pct_farmers'), period: recon.rows.length ? `${seasonLabel(recon.rows[0].o.sas_year, recon.rows[0].o.sas_season)}–${seasonLabel(lastRecon!.o.sas_year, lastRecon!.o.sas_season)}` : undefined,
            kind: 'mixed', src: ['sas_micro', ...new Set(recon.rows.flatMap((r) => reconSrc(r.o)))], note: tr('recon_note') }}>
          <div className="dt-scroll">
            <table className="recon">
              <caption className="sr-only">{tr('recon_title')}</caption>
              <thead><tr>
                <th scope="col">{tr('recon_season')}</th><th scope="col" className="num">{tr('recon_official')}</th>
                <th scope="col" className="num">{tr('recon_project')}</th><th scope="col" className="num">{tr('recon_diff')}</th><th scope="col">{tr('recon_src')}</th>
              </tr></thead>
              <tbody>{recon.rows.map(({ o, s, diff }) => (
                <tr key={`${o.sas_year}${o.sas_season}`}>
                  <th scope="row">{seasonLabel(o.sas_year, o.sas_season)}</th>
                  <td className="num off">{fmtPct(o.value)}</td>
                  <td className="num">{s ? <>{fmtPct(s.estimate)} <span className="muted">({fmtPct(s.ci_low)}–{fmtPct(s.ci_high)})</span></> : <span className="na">{tr(o.sas_year >= 2026 ? 'na_no_microdata' : 'na_no_data')}</span>}</td>
                  <td className="num">{Number.isFinite(diff) ? `${diff >= 0 ? '+' : ''}${fmtNum(diff, 1)} ${tr('pts')}` : <span className="na">{tr('na_not_comparable')}</span>}</td>
                  <td><a href={o.url} target="_blank" rel="noopener noreferrer">{o.table_or_section}</a></td>
                </tr>
              ))}</tbody>
            </table>
          </div>
        </ChartCard>
        <ChartCard title={tr('recon_defs_t')} icon={Cog} chart={false} means={tr('recon_defs')}>
          <div className="dt-scroll">
            <table className="recon">
              <caption className="sr-only">{tr('recon_defs_t')}</caption>
              <thead><tr><th scope="col">{tr('src_measure').replace(':', '')}</th><th scope="col">{tr('recon_def_unit')}</th><th scope="col">%</th><th scope="col">{tr('src_source').replace(':', '')}</th></tr></thead>
              <tbody>{defs.map((d) => (
                <tr key={d.label}>
                  <th scope="row">{d.label}</th><td>{d.unit}</td>
                  <td className={d.kind === 'official' ? 'off' : ''}>{d.val || <span className="na">{tr('na_no_data')}</span>}</td>
                  <td>{d.src.length
                    ? [...new Map(d.src.map((o) => [o.url, o])).values()].map((o, i) => <span key={o.url}>{i > 0 && '; '}<a href={o.url} target="_blank" rel="noopener noreferrer">{seasonLabel(o.sas_year, o.sas_season)} {o.table_or_section}</a></span>)
                    : <a href={SOURCES.sas_micro.url} target="_blank" rel="noopener noreferrer">{SOURCES.sas_micro.short}</a>}</td>
                </tr>
              ))}</tbody>
            </table>
          </div>
        </ChartCard>
      </Grid>

      <SectionTitle title={tr('s_findings')} />
      {findings && (
        <InsightGrid>
          <Insight icon={Droplet} color={brand.blue} title={tr('f1_t', in100(last(findings.a).estimate, tr))}
            text={tr('f1', f.area, fmtPct(last(findings.a).estimate), last(findings.a).sas_year, fmtPct(findings.a[0].estimate), findings.a[0].sas_year)} />
          <Insight icon={Sprout} color={brand.green} title={tr('f2_t', findings.ya.length)} text={tr('f2', findings.ya.slice(0, 4).map((r) => r.crop_name).join(', '))} />
          <Insight icon={Users} color="#B07A1C" title={tr('f3_t')}
            text={tr('f3', fmtPct(findings.eq.find((r) => r.group === 'Female')?.estimate), fmtPct(findings.eq.find((r) => r.group === 'Male')?.estimate),
              fmtPct(findings.cs.find((r) => r.group === 'In consolidated site')?.estimate))} />
          <Insight icon={Trophy} color={brand.terracotta} title={tr('f4_t')} text={tr('f4', findings.top.map((r) => r.district_std).join(', '))} />
          {findings.pc.length >= 2
            ? <Insight icon={Wheat} color="#00897B" title={tr('f5_t', `${findings.ch >= 0 ? '+' : ''}${fmtNum(findings.ch)}%`, findings.pc[0].y, last(findings.pc).y)}
                text={tr('f5', fmtNum(findings.pc[0].t), findings.pc[0].y, fmtNum(last(findings.pc).t), last(findings.pc).y)} />
            : <Insight icon={Wheat} color="#00897B" title={tr('f5_none')} text={tr('n_prod_mixed')} />}
          <Insight icon={HandCoins} color="#6A4C93" title={tr('f6_t')}
            text={tr('f6', in100(findings.hv('improved_seed', 2024), tr), in100(findings.hv('crop_insurance', 2024), tr))} />
        </InsightGrid>
      )}

      <Grid cols="1fr 1fr">
        <ChartCard title={tr('c_trend')} icon={ChartLine} means={trendMeans} prov={trendProv} table={trendTable}
          tools={<Select label={tr('src_measure').replace(':', '')} value={trendInd} onChange={setTrendInd} options={TREND_INDS.map((i) => ({ value: i, label: tr(`ind_${i}`) }))} width="100%" />}>
          <Plot fig={trendFig} height={300} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('c_inputs')} icon={FlaskConical}
          means={hi && tr('m_inputs', hi.year, hi.label, fmtPct(hi.estimate), fmtPct(irrIn?.estimate))}
          prov={{ unit: tr('u_pct_plots'), period: hi ? `${hi.year} (${tr('season')} ${hi.seasons})` : undefined, kind: 'survey', src: ['sas_micro'], note: tr('lim_4') }}
          table={{ name: 'farm_practices', rows: [...inputs].reverse(), cols: [
            { label: tr('src_measure').replace(':', ''), get: (r: { label: string }) => r.label },
            { label: '%', get: (r: { estimate: number }) => fmtPct(r.estimate), num: true },
            { label: '95% CI', get: (r: { ci_low: number; ci_high: number }) => `${fmtPct(r.ci_low)}–${fmtPct(r.ci_high)}`, num: true },
            { label: 'n', get: (r: { n: number }) => fmtNum(r.n), num: true },
          ] as AltTable['cols'] }}>
          <Plot fig={inputsFig} height={352} empty={tr('no_data')} />
        </ChartCard>
      </Grid>
      <Grid cols="1fr 1fr 1fr">
        <ChartCard title={tr('c_province')} icon={Layers}
          means={provLatest.length ? tr('m_prov', provLatest[0].area, fmtPct(provLatest[0].estimate), last(provLatest).area, fmtPct(last(provLatest).estimate)) : null}
          prov={{ unit: tr('u_pct_plots_ab'), period: '2019–2025', kind: 'survey', src: ['sas_micro'] }}
          table={{ name: 'province_irrigation', rows: [...prov].sort((a, b) => a.area.localeCompare(b.area) || a.period.localeCompare(b.period)), cols: [
            { label: tr('province'), get: (r: { area: string }) => r.area },
            { label: tr('src_period').replace(':', ''), get: (r: { period: string }) => r.period },
            { label: '%', get: (r: { estimate: number }) => fmtPct(r.estimate), num: true },
            { label: 'n', get: (r: { n: number }) => fmtNum(r.n), num: true },
          ] as AltTable['cols'] }}>
          <Plot fig={provFig} height={290} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('c_production')} icon={Wheat} means={prodMeans}
          prov={{ unit: tr('u_kt'), period: prodYears.length ? `${prodYears[0]}–${last(prodYears)}` : undefined, kind: prodPub ? 'mixed' : 'survey',
            src: prodPub ? ['sas_micro', ...PROD_SRC] : ['sas_micro'], note: prodPub ? tr('n_prod_mixed') : undefined }}
          table={{ name: 'production_by_group', rows: [...prod].sort((a, b) => a.sas_year - b.sas_year || b.t - a.t), cols: [
            { label: tr('year'), get: (r: { sas_year: number }) => r.sas_year },
            { label: tr('crop_group'), get: (r: { crop_group: string }) => r.crop_group },
            { label: 'kt', get: (r: { t: number }) => fmtNum(r.t / 1000), num: true },
            { label: tr('src_type').replace(':', ''), get: (r: { src: string }) => (r.src === 'survey' ? tr('kind_survey') : r.src === 'nisr' ? tr('rb_published') : tr('n_mixed_year')) },
          ] as AltTable['cols'] }}>
          <Plot fig={prodFig} height={290} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('c_season_c')} icon={Sun}
          means={scD.length ? tr('m_season_c', fmtPct(Math.min(...scD.map((r) => r.estimate)), 0), fmtPct(Math.max(...scD.map((r) => r.estimate)), 0), irr.length ? fmtPct(mean(irr.map((r) => r.estimate))) : '–') : null}
          prov={{ unit: tr('u_pct_plots_c'), period: period(scD), kind: 'survey', src: ['sas_micro'], note: tr('n_season_c') }}
          table={{ name: 'season_c_irrigation', rows: scD, cols: [
            { label: tr('year'), get: (r: Est) => r.sas_year },
            { label: '%', get: (r: Est) => fmtPct(r.estimate), num: true },
            { label: '95% CI', get: (r: Est) => (r.ci_low == null ? null : `${fmtPct(r.ci_low)}–${fmtPct(r.ci_high)}`), num: true },
            { label: 'n', get: (r: Est) => fmtNum(r.n), num: true },
            { label: tr('quality'), get: (r: Est) => relLabel(tr, r.reliability) },
          ] as AltTable['cols'] }}>
          <Plot fig={scFig} height={290} empty={tr('no_data')} />
        </ChartCard>
      </Grid>
    </>
  );
}

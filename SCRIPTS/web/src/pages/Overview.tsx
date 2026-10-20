import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  Droplet, Sprout, Users, Trophy, Wheat, HandCoins, Waves, Cog, UserCheck, FlaskConical, Sun, ChartLine, Layers,
  Database, Calendar, Map, CloudRain, House, Landmark, MapPinned,
} from 'lucide-react';
import type { Data } from 'plotly.js';
import { useApp } from '../data/store';
import { ChartCard, FiltersUsed, Grid, Insight, InsightGrid, Kpi, KpiRow, RelBadge, SectionTitle, Select } from '../components/ui';
import { Plot, simpleLines, std, legendBottom, type Fig } from '../components/Plot';
import { ahsFor, ahsVal, byYear, cropsFor, estFor, groupBy, in100, last, sum, totalsFor, wm, mean, type YearRow } from '../lib/stats';
import { fmtNum, fmtPct, seasonLabel } from '../lib/format';
import { brand, seasonCols, seriesCols } from '../lib/theme';
import type { Season } from '../data/types';

const TREND_INDS = ['irrigated', 'irrig_modern', 'irrig_any_farmer', 'inorganic_fert', 'organic_fert', 'anti_erosion'];
const STAPLES = ['Maize', 'Bush bean', 'Climbing bean', 'Small red bean', 'Irish potato', 'Paddy rice', 'Cassava', 'Wheat', 'Cooking banana', 'Dessert banana', 'Banana for beer'];

export default function Overview() {
  const { D, f, tr, PUB_YEARS } = useApp();
  const [trendInd, setTrendInd] = useState('irrigated');
  const ab = (fb: Season[] = ['A', 'B']) => { const s = f.seasons.filter((x) => fb.includes(x)); return s.length ? s : fb; };
  // yearly series for an indicator (weighted mean of the chosen main seasons)
  const yearly = (ind: string, seasons: Season[] = ['A', 'B']) =>
    byYear(estFor(D, f, ind, f.years, seasons.length === 1 && seasons[0] === 'C' ? ['C'] : ab(seasons)));

  // ---- number cards ----------------------------------------------------------------
  const tiles = useMemo(() => {
    const irr = yearly('irrigated'), mod = yearly('irrig_modern'), anyf = yearly('irrig_any_farmer');
    const fert = yearly('inorganic_fert'), sc = yearly('irrigated', ['C']);
    const tt = totalsFor(D, f).filter((r) => r.sas_season !== 'C');
    // areas: average per main season (A and B farm the same land); harvests: added up
    const totAll = [...groupBy(tt, (r) => String(r.sas_year)).values()].map((g) => ({
      sas_year: g[0].sas_year, ha: mean(g.map((r) => r.irrigated_area_ha)), t: sum(g.map((r) => r.production_t)), cult: mean(g.map((r) => r.cultivated_area_ha)),
    })).sort((a, b) => a.sas_year - b.sas_year);
    const tot = totAll.filter((r) => Number.isFinite(r.ha));
    const pubYears = new Set(tt.filter((r) => PUB_YEARS.includes(r.sas_year)).map((r) => r.sas_year));
    const maize = D.model_yield.table.find((r) => r.crop_name === 'Maize');
    return { irr, mod, anyf, fert, sc, tot, totAll, pubYears, maize };
  }, [D, f, PUB_YEARS]);

  const lst = (d: YearRow[]) => (d.length ? last(d).estimate : NaN);
  const isPub = (d: YearRow[]) => d.length > 0 && last(d).source === 'nisr';
  const dlt = (d: YearRow[]) => (isPub(d) || d.length < 2 ? null : last(d).estimate - d[0].estimate);
  const yr = (d: YearRow[]) => !d.length ? '' : isPub(d)
    ? <span className="st-pub"><Landmark size={12} /> {tr('k_pub_line', last(d).sas_year, last(d).seasons)} </span>
    : `${last(d).sas_year} · `;
  const since = (d: YearRow[]) => (d.length ? tr('k_pts_since', d[0].sas_year) : '');
  const bench = D.meta.benchmarks.find((b) => b.key === 'nisr_2026a_farmers');
  const { irr, mod, anyf, fert, sc, tot, totAll, pubYears, maize } = tiles;
  const lastTot = tot.length ? last(tot) : null, lastAll = totAll.length ? last(totAll) : null;

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
    // main food crops: harvest change in the selection
    const pc = [...groupBy(cropsFor(D, { ...f, seasons: ab(), crops: [], cropGroups: [] }).filter((r) => STAPLES.includes(r.crop_name)), (r) => String(r.sas_year)).values()]
      .map((g) => ({ y: g[0].sas_year, t: sum(g.map((r) => r.production_t)) / 1000 })).sort((x, y) => x.y - y.y);
    const ch = pc.length >= 2 ? 100 * (last(pc).t / pc[0].t - 1) : NaN;
    return { a, eq, cs, top, ya, hv, pc, ch };
  }, [D, f]);

  // ---- charts --------------------------------------------------------------------------
  const trendE = useMemo(() => estFor(D, f, trendInd), [D, f, trendInd]);
  const trendFig = useMemo<Fig | null>(() => {
    if (!trendE.length) return null;
    const data: Data[] = [];
    for (const s of ['A', 'B', 'C'] as Season[]) {
      const sv = trendE.filter((r) => r.sas_season === s && r.source === 'survey').sort((a, b) => a.sas_year - b.sas_year);
      if (sv.length) data.push({
        x: sv.map((r) => r.sas_year), y: sv.map((r) => r.estimate), type: 'scatter', mode: 'lines+markers', name: tr(`season_${s.toLowerCase()}`),
        line: { color: seasonCols[s], shape: 'spline', smoothing: 0.5 }, marker: { color: seasonCols[s] },
        text: sv.map((r) => `${r.sas_year}${s}: <b>${fmtPct(r.estimate)}</b> (95% CI ${fmtPct(r.ci_low)}–${fmtPct(r.ci_high)}) · n = ${fmtNum(r.n)}`), hoverinfo: 'text',
      });
      // NISR published seasons: their own marker, not joined to the survey line
      const pb = trendE.filter((r) => r.sas_season === s && r.source === 'nisr');
      if (pb.length) data.push({
        x: pb.map((r) => r.sas_year), y: pb.map((r) => r.estimate), type: 'scatter', mode: 'markers', name: `${tr(`season_${s.toLowerCase()}`)} · ${tr('pub_short')}`,
        marker: { size: 11, symbol: 'diamond', color: seasonCols[s], line: { color: '#fff', width: 2 } },
        text: pb.map((r) => `${r.sas_year}${s}: <b>${fmtPct(r.estimate)}</b> · ${tr('pub_hover')}`), hoverinfo: 'text',
      });
    }
    return simpleLines(data, std({ y: tr(`ind_${trendInd}`), xaxis: { dtick: 1 } }));
  }, [trendE, trendInd, tr]);
  const trendMeans = useMemo(() => {
    const e = trendE.filter((r) => r.sas_season !== 'C' && r.source === 'survey').sort((a, b) => a.sas_year - b.sas_year || a.sas_season.localeCompare(b.sas_season));
    if (e.length < 2) return null;
    const a = e[0], b = last(e);
    const sig = (b.ci_low ?? 0) > (a.ci_high ?? Infinity) || (b.ci_high ?? Infinity) < (a.ci_low ?? 0);
    return tr(!sig ? 'm_trend_stable' : b.estimate > a.estimate ? 'm_trend_up' : 'm_trend_down', f.area,
      seasonLabel(a.sas_year, a.sas_season), fmtPct(a.estimate), seasonLabel(b.sas_year, b.sas_season), fmtPct(b.estimate));
  }, [trendE, f.area, tr]);

  const inputs = useMemo(() => {
    const ind = ['irrigated', 'inorganic_fert', 'organic_fert', 'pesticide', 'anti_erosion', 'mechanised', 'agroforestry', 'land_consolidated'];
    // one survey season set, so every bar has the same definition and year
    const e = estFor(D, f, ind, f.years, ab(['A'])).filter((r) => r.source === 'survey');
    if (!e.length) return [];
    const ly = Math.max(...e.map((r) => r.sas_year));
    return [...groupBy(e.filter((r) => r.sas_year === ly), (r) => r.indicator).values()].map((g) => ({
      indicator: g[0].indicator, label: tr(`ind_${g[0].indicator}`), year: ly, n: sum(g.map((r) => r.n)),
      estimate: wm(g.map((r) => r.estimate), g.map((r) => r.wsum)), ci_low: wm(g.map((r) => r.ci_low), g.map((r) => r.wsum)), ci_high: wm(g.map((r) => r.ci_high), g.map((r) => r.wsum)),
    })).sort((a, b) => a.estimate - b.estimate);
  }, [D, f, tr]);
  const inputsFig = useMemo<Fig | null>(() => !inputs.length ? null : {
    data: [{
      type: 'bar', orientation: 'h', y: inputs.map((r) => r.label), x: inputs.map((r) => r.estimate),
      marker: { color: inputs.map((r) => (r.indicator === 'irrigated' ? brand.blue : '#3E8E63')) },
      text: inputs.map((r) => fmtPct(r.estimate, 0)), textposition: 'outside', cliponaxis: false, textfont: { size: 12, color: brand.ink },
      hovertext: inputs.map((r) => `<b>${r.label}</b><br>${fmtPct(r.estimate)} (95% CI ${fmtPct(r.ci_low)}–${fmtPct(r.ci_high)})<br>n = ${fmtNum(r.n)}`), hoverinfo: 'text',
    }],
    layout: std({ x: tr('x_pct_plots'), legend: false, bargap: 0.4, yaxis: { title: { text: '' }, ticksuffix: '  ' }, xaxis: { range: [0, Math.max(...inputs.map((r) => r.estimate), 1) * 1.18], ticksuffix: '%' } }),
  }, [inputs, tr]);

  const prov = useMemo(() => {
    const S = new Set(ab(['A'])), Y = new Set(f.years), P = new Set(f.provinces);
    const d = D.est.filter((r) => r.level === 'province' && r.indicator === 'irrigated' && S.has(r.sas_season) && Y.has(r.sas_year) && P.has(r.area));
    return [...groupBy(d, (r) => `${r.area}|${r.sas_year >= 2023 ? '2023-2025' : '2019-2022'}`).values()].map((g) => ({
      area: g[0].area, period: g[0].sas_year >= 2023 ? '2023-2025' : '2019-2022', estimate: wm(g.map((r) => r.estimate), g.map((r) => r.wsum)), n: sum(g.map((r) => r.n)),
    }));
  }, [D, f]);
  const provFig = useMemo<Fig | null>(() => {
    if (!prov.length) return null;
    const maxP = prov.some((r) => r.period === '2023-2025') ? '2023-2025' : '2019-2022';
    const ord = prov.filter((r) => r.period === maxP).sort((a, b) => a.estimate - b.estimate).map((r) => r.area);
    const data: Data[] = [];
    const pcol: Record<string, string> = { '2019-2022': '#A9C7B5', '2023-2025': brand.blue };
    for (const a of ord) {
      const p = prov.filter((r) => r.area === a);
      if (p.length === 2) data.push({ type: 'scatter', mode: 'lines', x: p.map((r) => r.estimate), y: [a, a], line: { color: '#D5DDD8', width: 5 }, hoverinfo: 'skip', showlegend: false });
    }
    for (const pp of Object.keys(pcol)) {
      const x = prov.filter((r) => r.period === pp); if (!x.length) continue;
      data.push({ type: 'scatter', mode: 'markers', name: pp, x: x.map((r) => r.estimate), y: x.map((r) => r.area),
        marker: { size: 14, color: pcol[pp], line: { color: '#fff', width: 2 } },
        text: x.map((r) => `<b>${r.area}</b> ${pp}<br>${fmtPct(r.estimate)} · n = ${fmtNum(r.n)}`), hoverinfo: 'text' });
    }
    return { data, layout: std({ x: tr('y_pct_plots_ab'), yaxis: { title: { text: '' }, categoryorder: 'array', categoryarray: ord }, legend: true }) };
  }, [prov, tr]);

  const prod = useMemo(() => [...groupBy(cropsFor(D, f), (r) => `${r.sas_year}|${r.crop_group}`).values()].map((g) => ({
    sas_year: g[0].sas_year, crop_group: g[0].crop_group, t: sum(g.map((r) => r.production_t)),
  })), [D, f]);
  const prodFig = useMemo<Fig | null>(() => {
    if (!prod.length) return null;
    const grp = [...groupBy(prod, (r) => r.crop_group).entries()].map(([k, g]) => ({ k, t: sum(g.map((r) => r.t)) })).sort((a, b) => b.t - a.t);
    // the four largest groups only, as clustered bars (no "Other" bucket)
    const top = grp.slice(0, 4).map((x) => x.k);
    return {
      data: top.map((g, i) => {
        const x = prod.filter((r) => r.crop_group === g).sort((a, b) => a.sas_year - b.sas_year);
        return { type: 'bar', name: g, x: x.map((r) => r.sas_year), y: x.map((r) => r.t / 1000), marker: { color: seriesCols[i] },
          text: x.map((r) => `<b>${g}</b> · ${r.sas_year}<br>${fmtNum(r.t / 1000)} kt`), hoverinfo: 'text', textposition: 'none' } as Data;
      }),
      layout: std({ barmode: 'group', bargap: 0.22, xaxis: { dtick: 1 }, yaxis: { ticksuffix: ' kt' }, legend: legendBottom(-0.18) }),
    };
  }, [prod]);
  const prodMeans = useMemo(() => {
    if (!prod.length) return null;
    const grp = [...groupBy(prod, (r) => r.crop_group).entries()].map(([k, g]) => ({ k, t: sum(g.map((r) => r.t)) })).sort((a, b) => b.t - a.t);
    return tr('m_prod', grp[0].k, fmtPct((100 * grp[0].t) / sum(grp.map((x) => x.t)), 0));
  }, [prod, tr]);

  const scD = useMemo(() => estFor(D, f, 'irrigated', f.years, ['C']).sort((a, b) => a.sas_year - b.sas_year), [D, f]);
  const scFig = useMemo<Fig | null>(() => !scD.length ? null : {
    data: [{ type: 'bar', x: scD.map((r) => r.sas_year), y: scD.map((r) => r.estimate), marker: { color: '#B07A1C' },
      text: scD.map((r) => fmtPct(r.estimate, 0)), textposition: 'outside', cliponaxis: false, textfont: { color: brand.ink, size: 12 },
      hovertext: scD.map((r) => `<b>${r.sas_year}C</b><br>${fmtPct(r.estimate)} (95% CI ${fmtPct(r.ci_low)}–${fmtPct(r.ci_high)})<br>n = ${fmtNum(r.n)}`), hoverinfo: 'text' }],
    layout: std({ y: tr('y_pct_plots'), legend: false, bargap: 0.4, xaxis: { dtick: 1 }, yaxis: { range: [0, Math.max(...scD.map((r) => r.estimate), 1) * 1.2] } }),
  }, [scD, tr]);

  const hi = inputs.length ? last(inputs) : null, irrIn = inputs.find((r) => r.indicator === 'irrigated');
  const provLatest = (() => { const p = prov.filter((r) => r.period === (prov.some((x) => x.period === '2023-2025') ? '2023-2025' : '2019-2022')).sort((a, b) => b.estimate - a.estimate); return p; })();

  return (
    <>
      <div className="hero">
        <div className="hero-text">
          <span className="hero-kicker"><Droplet size={14} /> NISR Big Data Hackathon 2026 {'·'} Track 1</span>
          <h1>{tr('hero_title')}</h1>
          <p>{tr('hero_sub')}</p>
          <div className="hero-meta">
            <span><Database size={14} /> {tr('hero_m1')}</span><span><Calendar size={14} /> {tr('hero_m2')}</span>
            <span><Map size={14} /> {tr('hero_m3')}</span><span><CloudRain size={14} /> {tr('hero_m4')}</span>
            <span><House size={14} /> {tr('hero_m5')}</span>
          </div>
        </div>
        <div className="hero-steps">
          <Link to="/need"><Droplet size={18} />{tr('act_gap')}</Link>
          <Link to="/evidence"><Sprout size={18} />{tr('act_payoff')}</Link>
          <Link to="/priority"><MapPinned size={18} />{tr('act_action')}</Link>
        </div>
        <div className="hero-hills" />
      </div>

      <FiltersUsed used={['years', 'seasons', 'area']} />
      <SectionTitle title={tr('s_numbers')} sub={tr('s_numbers_sub')} />
      <KpiRow>
        <Kpi label={tr('k_irrigated')} value={fmtPct(lst(irr))} icon={Droplet} color={brand.blue} delta={dlt(irr)}
          foot={<>{yr(irr)}{since(irr)} <RelBadge r={irr.length ? last(irr).rel : null} /></>} />
        <Kpi label={tr('k_area')} value={`${fmtNum(lastTot?.ha)} ha`} icon={Waves} color="#00897B"
          foot={<>{lastTot ? `${lastTot.sas_year} · ` : ''}{tr('k_area_sub2', fmtPct(lastTot ? (100 * lastTot.ha) / lastTot.cult : NaN))}</>} />
        <Kpi label={tr('k_modern')} value={fmtPct(lst(mod))} icon={Cog} color="#B07A1C" delta={dlt(mod)}
          foot={<>{yr(mod)}{tr('k_modern_sub2')} {!isPub(mod) && <RelBadge r={mod.length ? last(mod).rel : null} />}</>} />
        <Kpi label={tr('ind_irrig_any_farmer')} value={fmtPct(lst(anyf))} icon={UserCheck} color={brand.green} delta={dlt(anyf)}
          foot={<>{yr(anyf)}{tr('k_any_sub')}{bench && f.areaLevel === 'national' && !PUB_YEARS.includes(2026) && <div className="st-bench">{tr('k_any_bench', fmtPct(bench.value))}</div>}</>} />
      </KpiRow>
      <KpiRow>
        <Kpi label={tr('ind_inorganic_fert')} value={fmtPct(lst(fert))} icon={FlaskConical} color="#6A4C93" delta={dlt(fert)} foot={<>{yr(fert)}{tr('k_fert_sub')}</>} />
        <Kpi label={tr('k_production')} value={`${fmtNum(lastAll ? lastAll.t / 1000 : NaN)} kt`} icon={Wheat} color="#B07A1C"
          foot={<>{lastAll && pubYears.has(lastAll.sas_year)
            ? <span className="st-pub"><Landmark size={12} /> {tr('k_pub_prod', lastAll.sas_year)}</span>
            : lastAll ? `${lastAll.sas_year} · ` : ''} {tr('k_production_sub')}</>} />
        <Kpi label={tr('k_season_c')} value={fmtPct(lst(sc))} icon={Sun} color={brand.terracotta} delta={dlt(sc)} foot={<>{yr(sc)}{tr('k_season_c_sub')}</>} />
        <Kpi label={tr('k_maize')} value={maize ? `+${fmtNum(maize.adjusted_pct, 0)}%` : '–'} icon={Sprout} color={brand.green}
          foot={maize ? tr('k_maize_sub', fmtNum(maize.adjusted_low, 0), fmtNum(maize.adjusted_high, 0), fmtNum(maize.raw_pct, 0)) : null} />
      </KpiRow>

      <SectionTitle title={tr('s_findings')} sub={tr('s_findings_sub')} />
      {findings && (
        <InsightGrid>
          <Insight icon={Droplet} color={brand.blue} title={tr('f1_t', in100(last(findings.a).estimate, tr))}
            text={tr('f1', f.area, last(findings.a).sas_year, fmtPct(findings.a[0].estimate), findings.a[0].sas_year)} />
          <Insight icon={Sprout} color={brand.green} title={tr('f2_t', findings.ya.length)} text={tr('f2', findings.ya.slice(0, 4).map((r) => r.crop_name).join(', '))} />
          <Insight icon={Users} color="#B07A1C" title={tr('f3_t')}
            text={tr('f3', fmtPct(findings.eq.find((r) => r.group === 'Female')?.estimate), fmtPct(findings.eq.find((r) => r.group === 'Male')?.estimate),
              fmtPct(findings.cs.find((r) => r.group === 'In consolidated site')?.estimate))} />
          <Insight icon={Trophy} color={brand.terracotta} title={tr('f4_t')} text={tr('f4', findings.top.map((r) => r.district_std).join(', '))} />
          {findings.pc.length >= 2 && (
            <Insight icon={Wheat} color="#00897B" title={tr('f5_t', `${findings.ch >= 0 ? '+' : ''}${fmtNum(findings.ch)}%`, findings.pc[0].y)}
              text={tr('f5', fmtNum(findings.pc[0].t), findings.pc[0].y, fmtNum(last(findings.pc).t), last(findings.pc).y)} />
          )}
          <Insight icon={HandCoins} color="#6A4C93" title={tr('f6_t')}
            text={tr('f6', in100(findings.hv('improved_seed', 2024), tr), in100(findings.hv('improved_seed', 2020), tr), in100(findings.hv('crop_insurance', 2024), tr))} />
        </InsightGrid>
      )}

      <Grid cols="1fr 1fr">
        <ChartCard title={tr('c_trend')} icon={ChartLine} means={trendMeans}
          tools={<Select value={trendInd} onChange={setTrendInd} options={TREND_INDS.map((i) => ({ value: i, label: tr(`ind_${i}`) }))} width="100%" />}>
          <Plot fig={trendFig} height={300} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('c_inputs')} icon={FlaskConical}
          means={hi && tr('m_inputs', hi.year, hi.label, fmtPct(hi.estimate), fmtPct(irrIn?.estimate))}>
          <Plot fig={inputsFig} height={352} empty={tr('no_data')} />
        </ChartCard>
      </Grid>
      <Grid cols="1fr 1fr 1fr">
        <ChartCard title={tr('c_province')} icon={Layers}
          means={provLatest.length ? tr('m_prov', provLatest[0].area, fmtPct(provLatest[0].estimate), last(provLatest).area, fmtPct(last(provLatest).estimate)) : null}>
          <Plot fig={provFig} height={290} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('c_production')} icon={Wheat} means={prodMeans}>
          <Plot fig={prodFig} height={290} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('c_season_c')} icon={Sun}
          means={scD.length ? tr('m_season_c', fmtPct(Math.min(...scD.map((r) => r.estimate)), 0), fmtPct(Math.max(...scD.map((r) => r.estimate)), 0), irr.length ? fmtPct(mean(irr.map((r) => r.estimate))) : '–') : null}>
          <Plot fig={scFig} height={290} empty={tr('no_data')} />
        </ChartCard>
      </Grid>
    </>
  );
}

import { useMemo, useState } from 'react';
import { TriangleAlert, Droplet, Users, Sprout, Handshake, FlaskConical, Presentation, House, Droplets, MapPinned, ArrowDownWideNarrow } from 'lucide-react';
import type { Data } from 'plotly.js';
import { useApp } from '../data/store';
import { ChartCard, FiltersUsed, Grid, Insight, InsightGrid, Kpi, KpiRow, RelBadge, SectionTitle, Select, Callout } from '../components/ui';
import { Plot, choropleth, simpleLines, std, legendBottom, type Fig } from '../components/Plot';
import { ahsFor, ahsVal, groupBy, in100, mean } from '../lib/stats';
import { labOr } from '../lib/i18n';
import { fmtNum, fmtPct } from '../lib/format';
import { brand, colIrrigated, extraCols, seqBlue } from '../lib/theme';
import type { AhsRow } from '../data/types';

// Shares of farm households (not plots). Only the area filter applies; the AHS has
// its own rounds. 2024 used a new questionnaire, so it is drawn apart, never joined.
const YEARS = [2017, 2020, 2024];
const YCOL: Record<number, string> = { 2017: '#1976B9', 2020: '#0F7044', 2024: '#B07A1C' };
const TREND = ['irrigates', 'irrig_modern', 'irrig_motorised', 'improved_seed', 'inorganic_fert', 'organic_fert', 'pesticide', 'erosion_control', 'extension_any', 'coop_member', 'twigire_muhinzi', 'contract_farming'];
const PRACTICE = ['improved_seed', 'inorganic_fert', 'organic_fert', 'pesticide', 'erosion_control', 'agroforestry', 'kitchen_garden'];
const THEMES: Record<string, string[]> = {
  services: ['extension_any', 'extension_irrigation', 'farmer_field_school', 'twigire_muhinzi'],
  groups: ['coop_member', 'water_user_coop', 'contract_farming'],
  finance: ['bank_account', 'savings', 'loan_requested', 'grant_received', 'crop_insurance', 'girinka_cow'],
  info: ['has_telephone', 'has_radio', 'has_internet'],
};
const TCOL: Record<string, string> = { services: '#0F7044', groups: '#B07A1C', finance: '#1976B9', info: '#6A4C93' };
const MAP_INDS = ['irrigates', 'improved_seed', 'inorganic_fert', 'extension_any', 'coop_member'];
const EQ_DIMS = ['head_sex', 'head_age_band', 'head_education', 'farm_size_band', 'ubudehe'];
const EQ_ORDER = ['Female', 'Male', 'Under 35', '35-54', '55+', 'No formal education', 'Primary', 'Secondary / vocational', 'Tertiary', '< 0.25 ha', '0.25-0.5 ha', '0.5-1 ha', '> 1 ha', 'Category 1', 'Category 2', 'Category 3', 'Category 4'];
const yl = (y: number) => (y === 2024 ? '2024*' : String(y));

export default function Households() {
  const { D, f, tr, dict, geo, pickDistrict } = useApp();
  const lab = (p: string, v: string) => labOr(dict, tr, p, v);
  const [trendInd, setTrendInd] = useState('irrigates');
  const [eqDim, setEqDim] = useState('head_sex');
  const [mixDim, setMixDim] = useState('technique');
  const [mapInd, setMapInd] = useState('irrigates');
  const [mapYear, setMapYear] = useState(2020);
  const d = useMemo(() => ahsFor(D, f), [D, f]);
  if (!D.ahs) return <p className="muted">{tr('no_data')}</p>;
  const A = D.ahs;
  const hover = (r: { estimate: number; ci_low?: number | null; ci_high?: number | null; n: number; reliability: string; year: number }) =>
    `${fmtPct(r.estimate)} (95% CI ${fmtPct(r.ci_low)}–${fmtPct(r.ci_high)})<br>n = ${fmtNum(r.n)} · ${r.reliability}${r.year === 2024 ? `<br><i>${tr('break_lbl')}</i>` : ''}`;
  const v = (ind: string, y: number) => ahsVal(d, ind, y);
  const latest = (ind: string) => d.filter((r) => r.indicator === ind).sort((a, b) => b.year - a.year)[0]?.estimate;
  const sex = A.equity.filter((r) => r.dimension === 'head_sex' && r.year === 2024);
  const fem = sex.find((r) => r.group === 'Female')?.estimate ?? NaN, mal = sex.find((r) => r.group === 'Male')?.estimate ?? NaN;

  const tile = (ind: string, key: string, Icon: typeof Droplet, col: string) => {
    const x = d.filter((r) => r.indicator === ind).sort((a, b) => a.year - b.year); if (!x.length) return null;
    const lastR = x[x.length - 1], prev = x.find((r) => r.year === 2020);
    return <Kpi key={ind} label={tr(key)} value={fmtPct(lastR.estimate)} icon={Icon} color={col}
      foot={<>{prev && lastR.year !== 2020 ? tr('ak_vs2020', yl(lastR.year), fmtPct(prev.estimate)) : tr('ak_round', lastR.year)} <RelBadge r={lastR.reliability} /></>} />;
  };

  // ---- trend: 2017-2020 joined, 2024 apart
  const td = d.filter((r) => r.indicator === trendInd).sort((a, b) => a.year - b.year);
  const trendFig: Fig | null = !td.length ? null : (() => {
    const old = td.filter((r) => !r.series_break), nw = td.filter((r) => r.series_break);
    const data: Data[] = [];
    if (old.length) data.push({ type: 'scatter', mode: 'lines+markers', name: '2017–2020', x: old.map((r) => r.year), y: old.map((r) => r.estimate), line: { color: colIrrigated, shape: 'spline', smoothing: 0.5 }, marker: { color: colIrrigated }, hovertext: old.map(hover), hoverinfo: 'text' });
    if (nw.length) data.push({ type: 'scatter', mode: 'markers', name: tr('break_lbl'), x: nw.map((r) => r.year), y: nw.map((r) => r.estimate), marker: { size: 11, symbol: 'diamond', color: YCOL[2024], line: { color: '#fff', width: 2 } }, hovertext: nw.map(hover), hoverinfo: 'text' });
    const fig = simpleLines(data, std({ y: tr(td[0].population === 'Irrigating households' ? 'y_pct_irr_hh' : 'y_pct_hh'),
      xaxis: { tickvals: YEARS, ticktext: ['2017', '2020', '2024*'], range: [2016, 2025] }, yaxis: { range: [0, Math.max(...td.map((r) => r.estimate), 1) * 1.25] },
      shapes: [{ type: 'line', x0: 2022.2, x1: 2022.2, y0: 0, y1: 1, yref: 'paper', line: { color: brand.grey, width: 1.5, dash: 'dot' } }],
      annotations: [{ x: 2022.2, y: 1, yref: 'paper', text: tr('break_short'), showarrow: false, xanchor: 'left', yanchor: 'top', xshift: 4, font: { size: 11, color: '#5E6A66' } }] }));
    fig.layout = { ...fig.layout, hovermode: 'closest' };
    return fig;
  })();

  // ---- practices by round
  const pd = d.filter((r) => PRACTICE.includes(r.indicator));
  const pFig: Fig | null = !pd.length ? null : (() => {
    const maxY = Math.max(...pd.map((r) => r.year));
    const ordered = pd.filter((r) => r.year === maxY).sort((a, b) => a.estimate - b.estimate).map((r) => r.indicator);
    const ord = [...PRACTICE.filter((p) => !ordered.includes(p)), ...ordered].map((i) => lab('ai_', i));
    return {
      data: [...new Set(pd.map((r) => r.year))].sort().map((y) => { const x = pd.filter((r) => r.year === y); return {
        type: 'bar', orientation: 'h', name: y === 2024 ? tr('break_lbl') : String(y), y: x.map((r) => lab('ai_', r.indicator)), x: x.map((r) => r.estimate),
        marker: { color: YCOL[y], line: { color: '#fff', width: 1 } }, hovertext: x.map((r) => `<b>${lab('ai_', r.indicator)}</b> · ${yl(y)}<br>${hover(r)}`), hoverinfo: 'text', textposition: 'none' } as Data; }),
      layout: std({ barmode: 'group', bargap: 0.22, yaxis: { title: { text: '' }, tickfont: { size: 11 }, categoryorder: 'array', categoryarray: ord }, xaxis: { range: [0, 100], ticksuffix: '%' }, legend: { ...legendBottom(-0.14), traceorder: 'normal' } }),
    };
  })();
  const pch = [...groupBy(pd.filter((r) => !r.series_break && r.year <= 2020), (r) => r.indicator).values()].filter((g) => g.length >= 2).map((g) => { const s = [...g].sort((a, b) => a.year - b.year); return { i: s[0].indicator, a: s[0].estimate, b: s[s.length - 1].estimate }; }).sort((x, y) => (y.b - y.a) - (x.b - x.a))[0];

  // ---- services, groups and finance: latest round
  const en = Object.entries(THEMES).flatMap(([t, inds]) => inds.map((i) => { const x = d.filter((r) => r.indicator === i).sort((a, b) => b.year - a.year)[0]; return x ? { ...x, theme: t, lbl: lab('ai_', i) } : null; }))
    .filter((x): x is AhsRow & { theme: string; lbl: string } => !!x).sort((a, b) => a.estimate - b.estimate);
  const enFig: Fig | null = !en.length ? null : {
    data: Object.keys(THEMES).map((t) => { const x = en.filter((r) => r.theme === t); return x.length ? {
      type: 'bar', orientation: 'h', name: tr(`th_${t}`), y: x.map((r) => r.lbl), x: x.map((r) => r.estimate), marker: { color: TCOL[t], opacity: x.map((r) => (r.reliability === 'Unreliable' ? 0.45 : 1)) },
      text: x.map((r) => `${fmtPct(r.estimate, 0)} · ${yl(r.year)}`), textposition: 'outside', textfont: { size: 10.5, color: brand.ink }, cliponaxis: false,
      hovertext: x.map((r) => `<b>${r.lbl}</b> · AHS ${yl(r.year)}<br>${hover(r)}`), hoverinfo: 'text' } as Data : null; }).filter(Boolean) as Data[],
    layout: std({ barmode: 'overlay', bargap: 0.28, yaxis: { title: { text: '' }, tickfont: { size: 10.5 }, categoryorder: 'array', categoryarray: en.map((r) => r.lbl) }, xaxis: { range: [0, 118], ticksuffix: '%' }, legend: legendBottom(-0.1) }),
  };
  const enD = [...en].sort((a, b) => b.estimate - a.estimate);

  // ---- equity (national only)
  const eq = A.equity.filter((r) => r.dimension === eqDim).sort((a, b) => EQ_ORDER.indexOf(a.group) - EQ_ORDER.indexOf(b.group));
  const groups = [...new Set(eq.map((r) => r.group))];
  const eqFig: Fig | null = !eq.length ? null : {
    data: [...new Set(eq.map((r) => r.year))].sort().map((y) => { const x = eq.filter((r) => r.year === y); return {
      type: 'bar', name: y === 2024 ? tr('break_lbl') : String(y), x: x.map((r) => lab('grp_', r.group)), y: x.map((r) => r.estimate),
      marker: { color: YCOL[y], opacity: x.map((r) => (r.reliability === 'Unreliable' ? 0.35 : 1)), line: { color: '#fff', width: 1 } },
      hovertext: x.map((r) => `<b>${lab('grp_', r.group)}</b> · ${yl(y)}<br>${hover({ ...r, ci_low: r.estimate - 1.96 * r.se, ci_high: r.estimate + 1.96 * r.se })}`), hoverinfo: 'text', textposition: 'none' } as Data; }),
    layout: std({ y: tr('y_pct_hh'), barmode: 'group', bargap: 0.25, xaxis: { title: { text: '' }, tickfont: { size: 11 }, categoryorder: 'array', categoryarray: groups.map((g) => lab('grp_', g)) }, legend: legendBottom(-0.18) }),
  };
  const eqL = eq.filter((r) => r.year === Math.max(...eq.map((x) => x.year)) && r.reliability !== 'Unreliable').sort((a, b) => b.estimate - a.estimate);

  // ---- irrigation mix (national, named answers only)
  const mx = A.irrigation_mix.filter((r) => r.dimension === mixDim);
  const cats = [...groupBy(mx, (r) => r.category).values()].map((g) => ({ c: g[0].category, s: mean(g.map((r) => r.share)) })).sort((a, b) => b.s - a.s).map((x) => x.c);
  const mxYears = [...new Set(mx.map((r) => r.year))].sort();
  const mixFig: Fig | null = !mx.length ? null : {
    data: cats.map((c, i) => { const x = mx.filter((r) => r.category === c); return {
      type: 'bar', name: lab('mc_', c), x: x.map((r) => yl(r.year)), y: x.map((r) => r.share), marker: { color: extraCols[i % extraCols.length], line: { color: '#fff', width: 1.5 } },
      hovertext: x.map((r) => `<b>${lab('mc_', c)}</b> · ${yl(r.year)}<br>${fmtPct(r.share)} · n = ${fmtNum(r.n)}`), hoverinfo: 'text', textposition: 'none' } as Data; }),
    layout: std({ y: tr('y_pct_irr_hh'), barmode: 'group', bargap: 0.3, xaxis: { title: { text: '' }, type: 'category', categoryorder: 'array', categoryarray: mxYears.map(yl) }, yaxis: { ticksuffix: '%' }, legend: legendBottom(-0.12) }),
  };
  const mxL = mx.filter((r) => r.year === Math.max(...mxYears)).sort((a, b) => b.share - a.share);

  // ---- district map and ranking
  const md = A.indicators.filter((r) => r.level === 'district' && r.indicator === mapInd && r.year === mapYear);
  const sel = f.areaLevel !== 'national' ? f.districts : [];
  const mapFig: Fig | null = !md.length ? null : choropleth(geo, md.map((r) => ({ district: r.area, value: r.estimate,
    hover: `<b>${r.area}</b> · AHS ${yl(r.year)}<br>${tr(`ai_${mapInd}`)}: ${fmtPct(r.estimate)} (95% CI ${fmtPct(r.ci_low)}–${fmtPct(r.ci_high)})<br>n = ${fmtNum(r.n)} · ${r.reliability}` })),
  { noData: tr('no_estimate'), label: tr('y_pct_hh'), colorscale: seqBlue, selected: sel.length ? sel : undefined });
  const mdS = [...md].sort((a, b) => a.estimate - b.estimate);
  const rankFig: Fig | null = !mdS.length ? null : {
    data: [{ type: 'bar', orientation: 'h', y: mdS.map((r) => r.area), x: mdS.map((r) => r.estimate), customdata: mdS.map((r) => r.area),
      marker: { color: mdS.map((r) => (sel.includes(r.area) ? brand.amber : brand.blue)), opacity: mdS.map((r) => (r.reliability === 'Unreliable' ? 0.45 : 1)) },
      hovertext: mdS.map((r) => `<b>${r.area}</b>: ${fmtPct(r.estimate)} (95% CI ${fmtPct(r.ci_low)}–${fmtPct(r.ci_high)})<br>n = ${fmtNum(r.n)} · ${r.reliability}`), hoverinfo: 'text', textposition: 'none' }],
    layout: std({ x: tr('y_pct_hh'), legend: false, bargap: 0.25, yaxis: { title: { text: '' }, tickfont: { size: 10.5 }, categoryorder: 'array', categoryarray: mdS.map((r) => r.area) }, xaxis: { ticksuffix: '%' } }),
  };
  const mdD = [...mdS].reverse();

  return (
    <>
      <SectionTitle title={tr('ahs_t')} sub={tr('ahs_sub')} />
      <FiltersUsed used={['area']} />
      <Callout icon={TriangleAlert}>{`${tr('ahs_break')} ${tr('ahs_years_note')}`}</Callout>
      <SectionTitle title={tr('ahs_s_findings')} sub={tr('ahs_s_findings_sub')} />
      {d.length ? (
        <InsightGrid>
          <Insight icon={Droplet} color={brand.blue} title={tr('ah_f1_t', in100(v('irrigates', 2024), tr))} text={tr('ah_f1', f.area, fmtPct(v('irrigates', 2024)), fmtPct(v('irrigates', 2017)), fmtPct(v('irrigates', 2020)))} />
          <Insight icon={Users} color="#B07A1C" title={tr('ah_f2_t', fmtNum(mal - fem, 0))} text={tr('ah_f2', fmtPct(fem), fmtPct(mal))} />
          <Insight icon={Sprout} color={brand.green} title={tr('ah_f3_t')} text={tr('ah_f3', fmtPct(v('improved_seed', 2024), 0), fmtPct(v('inorganic_fert', 2024), 0))} />
          <Insight icon={Handshake} color={brand.terracotta} title={tr('ah_f4_t')} text={tr('ah_f4', fmtPct(latest('water_user_coop')), fmtPct(latest('crop_insurance')), fmtPct(latest('coop_member')))} />
        </InsightGrid>
      ) : <p className="muted">{tr('no_data')}</p>}
      <KpiRow>
        {tile('irrigates', 'ak_irrig', Droplet, brand.blue)}{tile('improved_seed', 'ak_seed', Sprout, brand.green)}
        {tile('inorganic_fert', 'ak_fert', FlaskConical, '#6A4C93')}{tile('extension_any', 'ak_ext', Presentation, '#B07A1C')}
      </KpiRow>
      <Grid cols="1fr 1fr">
        <ChartCard title={tr('ac_trend')} icon={House}
          tools={<Select value={trendInd} onChange={setTrendInd} options={TREND.map((i) => ({ value: i, label: tr(`ai_${i}`) }))} width="100%" />}
          means={td.length ? tr('am_trend', tr(`ai_${trendInd}`), fmtPct(ahsVal(td, trendInd, 2017)), fmtPct(ahsVal(td, trendInd, 2020)), fmtPct(ahsVal(td, trendInd, 2024))) : null}>
          <Plot fig={trendFig} height={300} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('ac_practices')} icon={Sprout} means={pch ? tr('am_practices', tr(`ai_${pch.i}`), fmtPct(pch.a, 0), fmtPct(pch.b, 0)) : null}>
          <Plot fig={pFig} height={352} empty={tr('no_data')} />
        </ChartCard>
      </Grid>
      <Grid cols="1fr 1fr 1fr">
        <ChartCard title={tr('ac_enablers')} icon={Handshake} means={enD.length >= 2 ? tr('am_enablers', enD[0].lbl, fmtPct(enD[0].estimate, 0), enD[enD.length - 1].lbl, fmtPct(enD[enD.length - 1].estimate)) : null}>
          <Plot fig={enFig} height={420} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('ac_equity')} icon={Users}
          tools={<Select value={eqDim} onChange={setEqDim} options={EQ_DIMS.map((x) => ({ value: x, label: tr(`eq_${x}`) }))} width="100%" />}
          means={eqL.length >= 2 ? tr('am_equity', yl(eqL[0].year), lab('grp_', eqL[0].group), fmtPct(eqL[0].estimate), lab('grp_', eqL[eqL.length - 1].group), fmtPct(eqL[eqL.length - 1].estimate)) : null}>
          <Plot fig={eqFig} height={360} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('ac_mix')} icon={Droplets}
          tools={<Select value={mixDim} onChange={setMixDim} options={['technique', 'water_source', 'tool'].map((x) => ({ value: x, label: tr(`mx_${x}`) }))} width="100%" />}
          means={mxL.length ? tr('am_mix', yl(mxL[0].year), lab('mc_', mxL[0].category), fmtPct(mxL[0].share, 0)) : null}>
          <Plot fig={mixFig} height={360} empty={tr('no_data')} />
        </ChartCard>
      </Grid>
      <Grid cols="7fr 5fr">
        <ChartCard title={tr('ac_map')} icon={MapPinned}
          tools={<>
            <Select value={mapInd} onChange={setMapInd} options={MAP_INDS.map((i) => ({ value: i, label: tr(`ai_${i}`) }))} />
            <Select value={mapYear} onChange={setMapYear} options={YEARS.map((y) => ({ value: y, label: y === 2024 ? tr('break_lbl') : String(y) }))} />
          </>}
          means={mdD.length >= 2 ? tr('am_map', yl(mdD[0].year), mdD[0].area, fmtPct(mdD[0].estimate), mdD[mdD.length - 1].area, fmtPct(mdD[mdD.length - 1].estimate)) : null}>
          <Plot fig={mapFig} height={400} onClick={pickDistrict} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('ac_rank')} icon={ArrowDownWideNarrow}>
          <Plot fig={rankFig} height={470} onClick={pickDistrict} empty={tr('no_data')} />
        </ChartCard>
      </Grid>
    </>
  );
}

import { useEffect, useMemo, useState } from 'react';
import { Scale, Sprout, Wheat, ChartLine, MapPin, ChartNoAxesColumnIncreasing } from 'lucide-react';
import type { Data } from 'plotly.js';
import { useApp } from '../data/store';
import { Callout, ChartCard, FiltersUsed, Grid, RelBadge, Select } from '../components/ui';
import { Plot, simpleLines, std, type Fig } from '../components/Plot';
import { cropsFor, groupBy, yieldOf } from '../lib/stats';
import { fmtNum } from '../lib/format';
import { brand, colIrrigated, colRainfed } from '../lib/theme';

// No causal claims: "simple" = observed difference; "fair" = after taking inputs,
// crop area, district and season into account (survey-weighted log model).
export default function Evidence() {
  const { D, f, tr } = useApp();
  const [crop, setCrop] = useState('Maize');
  // follow the sidebar crop when it has enough irrigated plots
  useEffect(() => { const ok = f.crops.filter((c) => D.yield.crops.includes(c)); if (ok.length && !ok.includes(crop)) setCrop(ok[0]); }, [f.crops]); // eslint-disable-line
  const scope = useMemo(() => new Set(D.crop.filter((r) => (!f.cropGroups.length || f.cropGroups.includes(r.crop_group)) && (!f.crops.length || f.crops.includes(r.crop_name))).map((r) => r.crop_name)), [D, f]);
  const MY = D.model_yield.table;

  const forestFig = useMemo<Fig | null>(() => {
    const d = MY.filter((r) => scope.has(r.crop_name)).sort((a, b) => a.adjusted_pct - b.adjusted_pct);
    if (!d.length) return null;
    const col = (r: (typeof d)[number]) => (r.adjusted_low > 0 ? colIrrigated : r.adjusted_high < 0 ? brand.terracotta : brand.grey);
    return {
      data: [
        ...d.map((r) => ({ type: 'scatter', mode: 'lines', x: [r.adjusted_low, r.adjusted_high], y: [r.crop_name, r.crop_name], line: { color: col(r), width: 2.5 }, hoverinfo: 'skip', showlegend: false })),
        { type: 'scatter', mode: 'markers', name: tr('raw_diff'), x: d.map((r) => r.raw_pct), y: d.map((r) => r.crop_name), marker: { symbol: 'circle-open', size: 10, color: brand.grey, line: { width: 2 } },
          text: d.map((r) => `${r.crop_name}<br>${tr('raw_diff')}: ${fmtNum(r.raw_pct, 0)}%`), hoverinfo: 'text' },
        { type: 'scatter', mode: 'markers', name: tr('adj_diff'), x: d.map((r) => r.adjusted_pct), y: d.map((r) => r.crop_name), marker: { size: 11, color: d.map(col) },
          text: d.map((r) => `<b>${r.crop_name}</b><br>${tr('adj_diff')}: ${fmtNum(r.adjusted_pct, 0)}% (${fmtNum(r.adjusted_low, 0)} to ${fmtNum(r.adjusted_high, 0)})<br>n = ${fmtNum(r.n)} · ${tr('n_irrigated')} ${fmtNum(r.n_irrigated)}`), hoverinfo: 'text' },
      ] as Data[],
      layout: std({ x: tr('x_yield_diff'), yaxis: { title: { text: '' }, categoryorder: 'array', categoryarray: d.map((r) => r.crop_name), tickmode: 'array', tickvals: d.map((r) => r.crop_name), automargin: true },
        shapes: [{ type: 'line', x0: 0, x1: 0, y0: 0, y1: 1, yref: 'paper', line: { color: brand.ink, width: 1 } }] }),
    };
  }, [MY, scope, tr]);
  const pos = MY.filter((r) => r.adjusted_low > 0).sort((a, b) => b.adjusted_pct - a.adjusted_pct), neg = MY.filter((r) => r.adjusted_high < 0);

  const pooled = D.yield.pooled.filter((r) => r.crop_name === crop);
  const m = MY.find((r) => r.crop_name === crop);
  const dumb = useMemo(() => {
    let d = pooled.map((r) => ({ ...r, st: /C/.test(r.season_type || '') ? tr('season_c') : tr('seasons_ab') }));
    if (!f.seasons.includes('C')) d = d.filter((r) => !/C/.test(r.season_type || ''));
    if (!f.seasons.some((s) => s !== 'C')) d = d.filter((r) => /C/.test(r.season_type || ''));
    return d;
  }, [pooled, f.seasons, tr]);
  const dumbFig = useMemo<Fig | null>(() => {
    if (!dumb.length) return null;
    const sts = [...new Set(dumb.map((r) => r.st))];
    const data: Data[] = sts.map((s) => { const i = dumb.find((r) => r.st === s && r.irrigation === 'Irrigated'), rf = dumb.find((r) => r.st === s && r.irrigation === 'Rain-fed');
      return i && rf ? { type: 'scatter', mode: 'lines', x: [rf.estimate, i.estimate], y: [s, s], line: { color: '#D5DDD8', width: 6 }, hoverinfo: 'skip', showlegend: false } as Data : null; }).filter(Boolean) as Data[];
    for (const g of ['Rain-fed', 'Irrigated'] as const) {
      const x = dumb.filter((r) => r.irrigation === g); if (!x.length) continue;
      data.push({ type: 'scatter', mode: 'markers', name: tr(g === 'Irrigated' ? 'irrigated' : 'rainfed'), x: x.map((r) => r.estimate), y: x.map((r) => r.st),
        marker: { size: 16, color: g === 'Irrigated' ? colIrrigated : colRainfed, line: { color: '#fff', width: 2 } },
        text: x.map((r) => `${g} · ${r.st}<br><b>${fmtNum(r.estimate)} kg/ha</b> (95% CI ${fmtNum(r.ci_low)}–${fmtNum(r.ci_high)})<br>n = ${fmtNum(r.n)} · ${r.reliability}`), hoverinfo: 'text' });
    }
    return { data, layout: std({ x: tr('y_yield'), yaxis: { title: { text: '' } }, legend: { orientation: 'h', y: -0.3 } }) };
  }, [dumb, tr]);
  const main = pooled.filter((r) => /main/.test(r.season_type || ''));
  const mi = main.find((r) => r.irrigation === 'Irrigated'), mr = main.find((r) => r.irrigation === 'Rain-fed');

  const byYearD = D.yield.by_year.filter((r) => r.crop_name === crop);
  const byYearFig = useMemo<Fig | null>(() => {
    const d = byYearD.filter((r) => f.years.includes(r.sas_year!)); if (!d.length) return null;
    const data: Data[] = (['Rain-fed', 'Irrigated'] as const).map((g) => { const x = d.filter((r) => r.irrigation === g).sort((a, b) => a.sas_year! - b.sas_year!); const c = g === 'Irrigated' ? colIrrigated : colRainfed;
      return { type: 'scatter', mode: 'lines+markers', name: tr(g === 'Irrigated' ? 'irrigated' : 'rainfed'), x: x.map((r) => r.sas_year), y: x.map((r) => r.estimate),
        line: { color: c, shape: 'spline', smoothing: 0.5 }, marker: { color: c }, text: x.map((r) => `${g} ${r.sas_year}: ${fmtNum(r.estimate)} kg/ha<br>n = ${fmtNum(r.n)} · ${r.reliability}`), hoverinfo: 'text' } as Data; });
    return simpleLines(data, std({ y: tr('y_yield'), xaxis: { dtick: 1 } }));
  }, [byYearD, f.years, tr]);
  const yrsBoth = [...groupBy(byYearD, (r) => String(r.sas_year)).values()].map((g) => ({ i: g.find((r) => r.irrigation === 'Irrigated')?.estimate, r: g.find((r) => r.irrigation === 'Rain-fed')?.estimate })).filter((x) => x.i != null && x.r != null);

  const ladder = D.yield.ladder.filter((r) => r.crop_name === crop).sort((a, b) => a.modern_inputs_n! - b.modern_inputs_n!);
  const ladderFig = useMemo<Fig | null>(() => !ladder.length ? null : {
    data: [{ type: 'bar', x: ladder.map((r) => String(r.modern_inputs_n)), y: ladder.map((r) => r.estimate), marker: { color: ladder.map((r) => (r.reliability === 'Unreliable' ? '#C9D8CF' : colIrrigated)) },
      text: ladder.map((r) => `${r.modern_inputs_n} ${tr('inputs')}: ${fmtNum(r.estimate)} kg/ha<br>n = ${fmtNum(r.n)} · ${r.reliability}`), hoverinfo: 'text', textposition: 'none' }],
    layout: std({ x: tr('x_modern_inputs'), y: tr('y_yield'), legend: false, bargap: 0.35, xaxis: { type: 'category' } }),
  }, [ladder, tr]);
  const ladOk = ladder.filter((r) => r.reliability !== 'Unreliable');

  // one bar pair per survey season: yields of different seasons and districts are only
  // combined from summed harvest and area (yieldOf), never by averaging yields
  const yarea = useMemo(() => [...groupBy(cropsFor(D, { ...f, crops: [crop], cropGroups: [] }), (r) => `${r.sas_year}${r.sas_season}`).values()]
    .map((g) => ({ g, y: yieldOf(D, g) }))
    .filter((x) => x.y.excluded < x.g.length)
    .map(({ g, y }) => ({ y: `${g[0].sas_year}${g[0].sas_season}`, yr: g[0].sas_year, irr: y.irr, rain: y.rf, nIrr: y.nIrr, exact: y.exact }))
    .sort((a, b) => a.y.localeCompare(b.y)), [D, f, crop]);
  const yPending = yarea.some((r) => !r.exact);
  const yareaFig = useMemo<Fig | null>(() => {
    const d = yarea.filter((r) => Number.isFinite(r.rain) || Number.isFinite(r.irr));
    if (!d.length) return null;
    const ok = d.filter((r) => r.nIrr >= 10 && Number.isFinite(r.irr));
    return {
      data: [
        { type: 'bar', name: tr('rainfed'), x: d.map((r) => r.y), y: d.map((r) => r.rain), marker: { color: colRainfed }, text: d.map((r) => `${r.y} · ${tr('rainfed')}: ${fmtNum(r.rain)} kg/ha`), hoverinfo: 'text', textposition: 'none' },
        { type: 'bar', name: tr('irrigated'), x: ok.map((r) => r.y), y: ok.map((r) => r.irr), marker: { color: colIrrigated }, text: ok.map((r) => `${r.y} · ${tr('irrigated')}: ${fmtNum(r.irr)} kg/ha (n = ${fmtNum(r.nIrr)})`), hoverinfo: 'text', textposition: 'none' },
      ] as Data[],
      layout: std({ y: tr('y_yield'), xaxis: { type: 'category', tickangle: -45 }, barmode: 'group', bargap: 0.3 }),
    };
  }, [yarea, tr]);
  const yOk = yarea.filter((r) => r.nIrr >= 10 && Number.isFinite(r.irr) && Number.isFinite(r.rain));

  return (
    <>
      <FiltersUsed used={['years', 'seasons', 'area', 'crop']} />
      <Callout icon={Scale}>{tr('evidence_caveat')}</Callout>
      <ChartCard title={tr('c_forest')} icon={Sprout} source={<>{tr('src_model_y')} {D.model_yield.eligibility ?? ''}</>}
        table={{ cols: [tr('crop'), tr('raw_diff'), tr('adj_diff'), '95%', 'n'], rows: MY.filter((r) => scope.has(r.crop_name)).map((r) => [r.crop_name, `${fmtNum(r.raw_pct, 0)}%`, `${fmtNum(r.adjusted_pct, 0)}%`, `${fmtNum(r.adjusted_low, 0)} to ${fmtNum(r.adjusted_high, 0)}`, r.n]) }}
        means={<>{tr('m_forest', pos.length, MY.length, pos.length ? pos.map((r) => `${r.crop_name} (+${fmtNum(r.adjusted_pct, 0)}%)`).join(', ') : '–', MY.length - pos.length - neg.length)} {tr('m_forest_controls', D.model_yield.controls)}</>}>
        <Plot fig={forestFig} height={400} empty={tr('no_adjusted')} />
      </ChartCard>
      <div style={{ height: 16 }} />
      <Grid cols="3fr 4fr 5fr">
        <section className="card chart-card">
          <header className="card-head"><span className="ch-icon"><Wheat size={16} /></span><h3>{tr('choose_crop')}</h3></header>
          <div className="card-body">
            <Select value={crop} onChange={setCrop} options={D.yield.crops.map((c) => ({ value: c, label: c }))} width="100%" />
            <p className="muted">{pooled[0]?.crop_group}</p>
            {m ? <><div className="big-number">{m.adjusted_pct > 0 ? '+' : ''}{fmtNum(m.adjusted_pct, 0)}%</div><p className="kpi-sub" title={tr('k_adj_sub', fmtNum(m.adjusted_low, 0), fmtNum(m.adjusted_high, 0))}>{tr('k_maize_foot')}</p></>
              : <p className="muted">{tr('no_adjusted')}</p>}
          </div>
        </section>
        <ChartCard title={tr('c_dumbbell')} icon={Scale}
          means={mi && mr ? <>{tr(!((mi.ci_low > mr.ci_high) || (mi.ci_high < mr.ci_low)) ? 'm_dumb_overlap' : 'm_dumb_diff', crop, fmtNum(mi.estimate), fmtNum(mr.estimate))} <RelBadge r={mi.reliability} /></> : null}>
          <Plot fig={dumbFig} height={260} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('c_ladder')} icon={ChartNoAxesColumnIncreasing}
          means={ladOk.length >= 2 ? tr('m_ladder', crop, fmtNum(ladOk[0].estimate), fmtNum(ladOk[ladOk.length - 1].estimate), ladOk[ladOk.length - 1].modern_inputs_n!) : null}>
          <Plot fig={ladderFig} height={260} empty={tr('no_data')} />
        </ChartCard>
      </Grid>
      <Grid cols="1fr 1fr">
        <ChartCard title={tr('c_yield_year')} icon={ChartLine} means={yrsBoth.length ? tr('m_byyear', yrsBoth.filter((x) => x.i! > x.r!).length, yrsBoth.length, crop) : null}>
          <Plot fig={byYearFig} height={300} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('c_yield_area')} icon={MapPin}
          means={yPending && !yOk.length ? tr('yield_combined_pending') : yOk.length ? tr('m_yarea', crop, f.area, yOk.filter((r) => r.irr > r.rain).length, yOk.length) : tr('m_yarea_few', crop, f.area)}
          source={tr('src_yield')}
          table={{ cols: [tr('season'), tr('irrigated'), tr('rainfed'), 'n'], rows: yarea.map((r) => [r.y, Number.isFinite(r.irr) && r.nIrr >= 10 ? Math.round(r.irr) : null, Number.isFinite(r.rain) ? Math.round(r.rain) : null, r.nIrr]) }}>
          <Plot fig={yareaFig} height={300} empty={tr('no_data')} />
        </ChartCard>
      </Grid>
    </>
  );
}

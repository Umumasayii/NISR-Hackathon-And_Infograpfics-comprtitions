import { useEffect, useMemo, useState } from 'react';
import { FlaskConical, Target, ChartLine, Scale, CalendarCheck, ListOrdered, ArrowLeftRight, SlidersHorizontal, Map as MapIcon } from 'lucide-react';
import type { Data } from 'plotly.js';
import { useApp } from '../data/store';
import { Callout, ChartCard, FiltersUsed, Grid, Kpi, KpiRow, Select, SourceLine } from '../components/ui';
import type { Prov } from '../lib/sources';
import { Plot, choropleth, std, type Fig } from '../components/Plot';
import { fmtNum, fmtPct } from '../lib/format';
import { brand, colIrrigated, divGap } from '../lib/theme';

type Inputs = Record<string, string | number>;
/** logistic model: p = plogis(intercept + level effects + slopes * x); the base level has no coefficient */
function predict(coef: Record<string, number>, x: Inputs) {
  let z = coef['(Intercept)'] ?? 0;
  for (const [k, v] of Object.entries(x)) z += typeof v === 'number' ? (coef[k] ?? 0) * v : coef[`${k}${v}`] ?? 0;
  return 1 / (1 + Math.exp(-z));
}

export default function Model() {
  const { D, f, tr, geo, pickDistrict } = useApp();
  const M = D.model, L = M.levels;
  const glm = M.performance.find((r) => /Logistic/i.test(r.model))!, rf = M.performance.find((r) => /forest/i.test(r.model));
  const [s, setS] = useState<Inputs>({ district: 'Kirehe', season: 'A', area: 0.1, rain: 0, erosion: 'Moderate', consolidated: 'No', inorganic_fert: 'No', organic_fert: 'Yes', gender: 'Female', age_band: '35-54', large_farm: 'Small-scale' });
  useEffect(() => { if (f.areaLevel !== 'national' && (L.district as string[]).includes(f.districts[0])) setS((x) => ({ ...x, district: f.districts[0] })); }, [f.districts, f.areaLevel]); // eslint-disable-line
  const set = (k: string) => (v: string | number) => setS((x) => ({ ...x, [k]: v }));
  const sim = useMemo(() => {
    const nd: Inputs = { district: s.district, season: s.season, log_plot_area: Math.log(Math.min(Math.max(Number(s.area) || 0.1, 0.005), 20)), rain_anomaly_z: Number(s.rain),
      erosion: s.erosion, consolidated: s.consolidated, inorganic_fert: s.inorganic_fert, organic_fert: s.organic_fert, gender: s.gender, age_band: s.age_band, large_farm: s.large_farm };
    return { p: predict(M.coef, nd), alt: predict(M.coef, { ...nd, consolidated: 'Yes', inorganic_fert: 'Yes' }) };
  }, [s, M.coef]);
  const opts = (k: string) => (L[k] as string[]).map((v) => ({ value: v, label: v }));

  const calFig = useMemo<Fig>(() => {
    const d = M.calibration, mx = Math.max(...d.map((r) => Math.max(r.predicted_pct, r.observed_pct))) * 1.05;
    return { data: [
      { type: 'scatter', mode: 'lines+markers', name: tr('model'), x: d.map((r) => r.predicted_pct), y: d.map((r) => r.observed_pct), line: { color: colIrrigated }, marker: { color: colIrrigated, size: d.map((r) => Math.sqrt(r.n) / 6 + 6) },
        text: d.map((r) => `${tr('decile')} ${r.bin}<br>${tr('predicted')}: ${fmtPct(r.predicted_pct, 2)}<br>${tr('observed')}: ${fmtPct(r.observed_pct, 2)}<br>n = ${fmtNum(r.n)}`), hoverinfo: 'text' },
      { type: 'scatter', mode: 'lines', name: tr('perfect'), x: [0, mx], y: [0, mx], line: { dash: 'dot', color: brand.grey }, hoverinfo: 'skip' },
    ] as Data[], layout: std({ x: tr('x_predicted'), y: tr('y_observed'), legend: { x: 0.02, y: 0.98, orientation: 'v' } }) };
  }, [M, tr]);
  const topBin = [...M.calibration].sort((a, b) => b.bin - a.bin)[0];
  // every model output says it is one, with the test period and the main caveat
  const mp = (unit: string, note?: string): Prov => ({ unit: tr(unit), period: tr('model_period'), kind: 'model', src: ['model', 'sas_micro'], note });

  const fairFig = useMemo<Fig>(() => {
    const d = M.fairness.map((r) => ({ ...r, lbl: `${r.group} (${r.dimension})` }));
    return { data: [{ type: 'bar', x: d.map((r) => r.lbl), y: d.map((r) => r.auc), marker: { color: d.map((r) => (r.dimension === 'Gender' ? '#B07A1C' : '#1976B9')) },
      text: d.map((r) => `${r.lbl}<br>AUC ${r.auc.toFixed(3)}<br>${tr('calib_gap')}: ${r.calibration_gap_pts > 0 ? '+' : ''}${fmtNum(r.calibration_gap_pts, 2)} pts<br>n = ${fmtNum(r.n)}`), hoverinfo: 'text', textposition: 'none' }],
    layout: std({ y: 'AUC', legend: false, bargap: 0.35, yaxis: { range: [0.5, 1] }, xaxis: { title: { text: '' } } }) };
  }, [M, tr]);
  const worst = [...M.fairness].sort((a, b) => Math.abs(b.calibration_gap_pts) - Math.abs(a.calibration_gap_pts))[0];

  const imp = [...M.importance].sort((a, b) => a.importance - b.importance);
  const impFig: Fig = { data: [{ type: 'bar', orientation: 'h', y: imp.map((r) => r.feature), x: imp.map((r) => r.importance), marker: { color: colIrrigated }, text: imp.map((r) => `${r.feature}: ${fmtNum(r.importance, 0)}`), hoverinfo: 'text', textposition: 'none' }],
    layout: std({ x: tr('x_importance'), legend: false, bargap: 0.35, yaxis: { title: { text: '' }, categoryorder: 'array', categoryarray: imp.map((r) => r.feature) } }) };

  const odds = M.coefficients.filter((r) => r.term !== '(Intercept)' && !/^district/.test(r.term) && !/Unknown$/.test(r.term) && Number.isFinite(r.or_high)).sort((a, b) => a.odds_ratio - b.odds_ratio);
  // very wide intervals (rare levels) are cut at the edge of the chart; the hover keeps the real values
  const OR_MIN = 0.05, OR_MAX = 20, clip = (v: number) => Math.min(Math.max(v, OR_MIN), OR_MAX);
  const oddsFig: Fig = { data: [
    ...odds.map((r) => ({ type: 'scatter', mode: 'lines', x: [clip(r.or_low), clip(r.or_high)], y: [r.term, r.term], line: { color: '#C5D6CC', width: 2.5 }, hoverinfo: 'skip', showlegend: false })),
    { type: 'scatter', mode: 'markers', showlegend: false, x: odds.map((r) => clip(r.odds_ratio)), y: odds.map((r) => r.term), marker: { size: 10, color: odds.map((r) => (r.or_low > 1 ? colIrrigated : r.or_high < 1 ? brand.terracotta : brand.grey)), symbol: odds.map((r) => (r.or_low > 1 ? 'triangle-right' : r.or_high < 1 ? 'triangle-left' : 'circle-open')) },
      text: odds.map((r) => `${r.term}<br>OR ${fmtNum(r.odds_ratio, 2)} (${fmtNum(r.or_low, 2)}–${fmtNum(r.or_high, 2)})`), hoverinfo: 'text' },
  ] as Data[], layout: std({ x: tr('x_odds'), legend: false, xaxis: { type: 'log', range: [Math.log10(OR_MIN), Math.log10(OR_MAX)], tickvals: [0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20], ticktext: ['0.05', '0.1', '0.2', '0.5', '1', '2', '5', '10', '20'] }, yaxis: { title: { text: '' }, tickfont: { size: 11 }, tickmode: 'array', tickvals: odds.map((r) => r.term), automargin: true, categoryorder: 'array', categoryarray: odds.map((r) => r.term) },
    shapes: [{ type: 'line', x0: 1, x1: 1, y0: 0, y1: 1, yref: 'paper', line: { color: brand.ink } }] }) };

  const lim = Math.max(...M.potential.map((r) => Math.abs(r.gap_pts)));
  const potFig = useMemo(() => choropleth(geo, M.potential.map((r) => ({ district: r.district_std, value: r.gap_pts,
    hover: `<b>${r.district_std}</b><br>${tr('observed')}: ${fmtPct(r.observed_pct)}<br>${tr('predicted')}: ${fmtPct(r.predicted_pct)}<br>${tr('gap')}: ${r.gap_pts > 0 ? '+' : ''}${fmtNum(r.gap_pts, 1)} pts` })),
  { label: tr('gap_pts'), colorscale: divGap, zmin: -lim, zmax: lim, selected: f.areaLevel !== 'national' ? f.districts : undefined }), [geo, M, f, tr, lim]);
  const potTop = [...M.potential].sort((a, b) => b.gap_pts - a.gap_pts).slice(0, 4).map((r) => r.district_std);

  return (
    <>
      <FiltersUsed used={['area']} />
      <Callout icon={FlaskConical}>{tr('model_caveat', fmtNum(M.n_train), fmtNum(M.n_test))}</Callout>
      <KpiRow>
        <Kpi label={tr('k_auc')} value={glm.auc.toFixed(3)} icon={Target} color={brand.green} foot={tr('k_auc_sub', rf ? rf.auc.toFixed(3) : '–')} prov={mp('u_auc')} />
        <Kpi label={tr('k_brier')} value={glm.brier.toFixed(4)} icon={ChartLine} color={brand.blue} foot={tr('k_brier_sub')} prov={mp('u_auc')} />
        <Kpi label={tr('k_obs_pred')} value={`${fmtPct(glm.observed_pct)} / ${fmtPct(glm.predicted_pct)}`} icon={Scale} color="#6A4C93" foot={tr('k_obs_pred_sub')} prov={mp('u_pct_plots')} />
        <Kpi label={tr('k_validation')} value={'2024–2025'} icon={CalendarCheck} color="#B07A1C" foot={tr('k_validation_sub')} prov={mp('u_auc')} />
      </KpiRow>
      <Grid cols="1fr 1fr">
        <ChartCard title={tr('c_calibration')} icon={Target} means={tr('m_calib', fmtPct(topBin.predicted_pct), fmtPct(topBin.observed_pct))} prov={mp('u_prob')}
          table={{ name: 'model_calibration', rows: M.calibration, cols: [
            { label: tr('decile'), get: (r: (typeof M.calibration)[number]) => r.bin, num: true },
            { label: tr('predicted'), get: (r: (typeof M.calibration)[number]) => fmtPct(r.predicted_pct, 2), num: true },
            { label: tr('observed'), get: (r: (typeof M.calibration)[number]) => fmtPct(r.observed_pct, 2), num: true },
            { label: 'n', get: (r: (typeof M.calibration)[number]) => fmtNum(r.n), num: true },
          ] }}><Plot fig={calFig} height={300} /></ChartCard>
        <ChartCard title={tr('c_fairness')} icon={Scale}
          means={tr('m_fair', Math.min(...M.fairness.map((r) => r.auc)).toFixed(2), Math.max(...M.fairness.map((r) => r.auc)).toFixed(2), worst.group, fmtNum(Math.abs(worst.calibration_gap_pts), 1))}
          prov={mp('u_auc')}
          table={{ name: 'model_performance_by_group', rows: M.fairness, cols: [
            { label: tr('group'), get: (r: (typeof M.fairness)[number]) => `${r.group} (${r.dimension})` },
            { label: 'AUC', get: (r: (typeof M.fairness)[number]) => r.auc.toFixed(3), num: true },
            { label: tr('calib_gap'), get: (r: (typeof M.fairness)[number]) => `${fmtNum(r.calibration_gap_pts, 2)} ${tr('pts')}`, num: true },
            { label: 'n', get: (r: (typeof M.fairness)[number]) => fmtNum(r.n), num: true },
          ] }}>
          <Plot fig={fairFig} height={300} />
        </ChartCard>
      </Grid>
      <Grid cols="5fr 7fr">
        <ChartCard title={tr('c_importance')} icon={ListOrdered} means={tr('m_imp', M.importance[0]?.feature, M.importance[1]?.feature)} prov={mp('u_imp')}
          table={{ name: 'model_importance', rows: [...imp].reverse(), cols: [
            { label: tr('variable'), get: (r: (typeof imp)[number]) => r.feature }, { label: tr('u_imp'), get: (r: (typeof imp)[number]) => fmtNum(r.importance, 0), num: true },
          ] }}><Plot fig={impFig} height={340} /></ChartCard>
        <ChartCard title={tr('c_odds')} icon={ArrowLeftRight} means={tr('m_odds')} prov={mp('u_or', tr('n_model_ci'))}
          table={{ name: 'model_odds_ratios', rows: [...odds].reverse(), cols: [
            { label: tr('variable'), get: (r: (typeof odds)[number]) => r.term }, { label: 'OR', get: (r: (typeof odds)[number]) => fmtNum(r.odds_ratio, 2), num: true },
            { label: '95% CI', get: (r: (typeof odds)[number]) => `${fmtNum(r.or_low, 2)}–${fmtNum(r.or_high, 2)}`, num: true },
          ] }}><Plot fig={oddsFig} height={340} /></ChartCard>
      </Grid>
      <Grid cols="5fr 7fr">
        <section className="card chart-card">
          <header className="card-head"><span className="ch-icon"><SlidersHorizontal size={16} /></span><h3>{tr('c_simulator')}</h3></header>
          <div className="card-body">
            <div className="form-grid">
              <Select label={tr('district')} value={String(s.district)} onChange={set('district')} options={opts('district')} />
              <Select label={tr('season')} value={String(s.season)} onChange={set('season')} options={[{ value: 'A', label: tr('season_a') }, { value: 'B', label: tr('season_b') }]} />
              <label className="field">{tr('plot_area_ha')}<input type="number" min={0.005} max={20} step={0.05} value={s.area} onChange={(e) => set('area')(Number(e.target.value))} /></label>
              <label className="field">{tr('rain_z')} <output>{Number(s.rain).toFixed(2)}</output><input type="range" min={-1.5} max={2.5} step={0.25} value={s.rain} onChange={(e) => set('rain')(Number(e.target.value))} /></label>
              <Select label={tr('dim_erosion')} value={String(s.erosion)} onChange={set('erosion')} options={opts('erosion')} />
              <Select label={tr('dim_consolidated')} value={String(s.consolidated)} onChange={set('consolidated')} options={opts('consolidated')} />
              <Select label={tr('ind_inorganic_fert')} value={String(s.inorganic_fert)} onChange={set('inorganic_fert')} options={opts('inorganic_fert')} />
              <Select label={tr('ind_organic_fert')} value={String(s.organic_fert)} onChange={set('organic_fert')} options={opts('organic_fert')} />
              <Select label={tr('gender')} value={String(s.gender)} onChange={set('gender')} options={opts('gender')} />
              <Select label={tr('dim_age_band')} value={String(s.age_band)} onChange={set('age_band')} options={opts('age_band')} />
              <Select label={tr('farm_type')} value={String(s.large_farm)} onChange={set('large_farm')} options={opts('large_farm')} />
            </div>
            <div className="sim-result">
              <div className="big-number">{fmtPct(100 * sim.p)}</div>
              <p className="kpi-sub">{tr('sim_prob')}</p>
              <p>{tr('sim_alt', fmtPct(100 * sim.alt))}</p>
              <p className="muted small">{tr('sim_caveat')}</p>
            </div>
            <SourceLine p={mp('u_prob', tr('n_model_ci'))} />
          </div>
        </section>
        <ChartCard title={tr('c_potential')} icon={MapIcon} means={tr('m_potential', potTop.join(', '))} prov={mp('u_pts', tr('n_pred_gap'))}
          table={{ name: 'model_observed_vs_predicted', rows: [...M.potential].sort((a, b) => b.gap_pts - a.gap_pts), cols: [
            { label: tr('district'), get: (r: (typeof M.potential)[number]) => r.district_std },
            { label: tr('observed'), get: (r: (typeof M.potential)[number]) => fmtPct(r.observed_pct), num: true },
            { label: tr('predicted'), get: (r: (typeof M.potential)[number]) => fmtPct(r.predicted_pct), num: true },
            { label: tr('gap_pts'), get: (r: (typeof M.potential)[number]) => fmtNum(r.gap_pts, 1), num: true },
          ] }}><Plot fig={potFig} height={470} onClick={pickDistrict} /></ChartCard>
      </Grid>
    </>
  );
}

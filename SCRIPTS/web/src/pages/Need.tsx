import { useEffect, useMemo, useState } from 'react';
import { TriangleAlert, Crosshair, Thermometer, CirclePlay, CloudRain, Play, Pause } from 'lucide-react';
import type { Data } from 'plotly.js';
import { useApp } from '../data/store';
import { Callout, ChartCard, FiltersUsed, Grid, Select } from '../components/ui';
import { Plot, choropleth, std, type Fig } from '../components/Plot';
import { groupBy, mean, median, sum, wm } from '../lib/stats';
import { fmtNum, fmtPct } from '../lib/format';
import { brand, divRain, provinceCols, seasonCols } from '../lib/theme';

const qKey = (q: string) => `q_${q.toLowerCase().replace(/[^a-z]/g, '')}`;
const QLEV = ['High need, low adoption', 'High need, higher adoption', 'Lower need, low adoption', 'Lower need, higher adoption'];
const QCOL = [brand.terracotta, '#0F7044', '#B07A1C', '#1976B9'];

export default function Need() {
  const { D, f, tr, geo, pickDistrict } = useApp();
  const prov = (d: string) => D.lookup.find((r) => r.district === d)?.province ?? '';
  const nd = D.rain.district;
  const isSel = (d: string) => f.areaLevel !== 'national' && f.districts.includes(d);

  // ---- quadrant
  const quadFig = useMemo<Fig>(() => {
    const mx = median(nd.map((r) => r.need_score)), my = median(nd.map((r) => r.adoption_pct ?? NaN));
    const data: Data[] = QLEV.map((q, i) => {
      const d = nd.filter((r) => r.quadrant === q);
      return {
        type: 'scatter', mode: 'text+markers', name: tr(qKey(q)), x: d.map((r) => r.need_score), y: d.map((r) => r.adoption_pct), customdata: d.map((r) => r.district_std),
        text: d.map((r) => (q === QLEV[0] || isSel(r.district_std) ? r.district_std : '')), textposition: 'top center', textfont: { size: 10, color: brand.ink },
        marker: { color: QCOL[i], size: d.map((r) => (isSel(r.district_std) ? 16 : 11)), line: { color: d.map((r) => (isSel(r.district_std) ? brand.ink : '#FFFFFF')), width: 1.5 } },
        hovertext: d.map((r) => `<b>${r.district_std}</b> (${prov(r.district_std)})<br>${tr('need_score')}: ${fmtNum(r.need_score, 0)}/100<br>${tr('ind_irrigated')}: ${fmtPct(r.adoption_pct)} (${fmtPct(r.adoption_low)}–${fmtPct(r.adoption_high)})<br>${tr('normal_rain')}: ${fmtNum(r.rain_normal_ab_mm)} mm · CV A ${fmtNum(r.rain_cv_a_pct, 0)}%, B ${fmtNum(r.rain_cv_b_pct, 0)}%<br>${tr(qKey(r.quadrant))}`),
        hoverinfo: 'text',
      } as Data;
    });
    return { data, layout: std({ x: tr('need_score'), y: tr('y_pct_plots_2325'), yaxis: { rangemode: 'nonnegative' },
      shapes: [
        { type: 'line', x0: mx, x1: mx, y0: 0, y1: 1, yref: 'paper', line: { dash: 'dot', color: brand.grey } },
        { type: 'line', y0: my, y1: my, x0: 0, x1: 1, xref: 'paper', line: { dash: 'dot', color: brand.grey } }],
      annotations: [{ x: 1, y: 0, xref: 'paper', yref: 'paper', xanchor: 'right', yanchor: 'bottom', text: tr('q_hnla_label'), showarrow: false, font: { color: brand.terracotta, size: 12 } }] }) };
  }, [nd, f, tr]); // eslint-disable-line
  const hnla = nd.filter((r) => r.quadrant === QLEV[0]).sort((a, b) => b.need_score - a.need_score);

  // ---- animated bubbles: each district's irrigation (A+B) per year vs its need score
  const bub = useMemo(() => {
    const Y = new Set(f.years), Ds = new Set(f.districts);
    const e = D.est.filter((r) => r.level === 'district' && r.indicator === 'irrigated' && (r.sas_season === 'A' || r.sas_season === 'B') && Y.has(r.sas_year) && Ds.has(r.area));
    const ha = new Map([...groupBy(D.totals.filter((r) => r.level === 'district' && r.sas_season !== 'C'), (r) => `${r.area}|${r.sas_year}`).entries()].map(([k, g]) => [k, mean(g.map((r) => r.cultivated_area_ha))]));  // land per main season, not A + B
    return [...groupBy(e, (r) => `${r.area}|${r.sas_year}`).values()].map((g) => ({
      d: g[0].area, y: g[0].sas_year, a: wm(g.map((r) => r.estimate), g.map((r) => r.wsum)), n: sum(g.map((r) => r.n)),
      need: nd.find((r) => r.district_std === g[0].area)?.need_score ?? NaN, ha: ha.get(`${g[0].area}|${g[0].sas_year}`) ?? 0,
    })).filter((r) => Number.isFinite(r.need));
  }, [D, f, nd]);
  const years = useMemo(() => [...new Set(bub.map((r) => r.y))].sort(), [bub]);
  const [yi, setYi] = useState(0);
  const [playing, setPlaying] = useState(false);
  useEffect(() => { setYi(Math.max(0, years.length - 1)); }, [years.length]);
  useEffect(() => {
    if (!playing) return;
    const t = setInterval(() => setYi((i) => { if (i + 1 >= years.length) { setPlaying(false); return i; } return i + 1; }), 1200);
    return () => clearInterval(t);
  }, [playing, years.length]);
  const bubFig = useMemo<Fig | null>(() => {
    if (!bub.length) return null;
    const y = years[Math.min(yi, years.length - 1)];
    const maxHa = Math.max(...bub.map((r) => r.ha), 1), maxA = Math.max(...bub.map((r) => r.a));
    const data: Data[] = Object.keys(provinceCols).map((p) => {
      const d = bub.filter((r) => r.y === y && prov(r.d) === p);
      return { type: 'scatter', mode: 'markers', name: p, x: d.map((r) => r.need), y: d.map((r) => r.a), ids: d.map((r) => r.d), customdata: d.map((r) => r.d),
        marker: { color: provinceCols[p], opacity: 0.85, sizemode: 'diameter', size: d.map((r) => 8 + 37 * Math.sqrt(r.ha / maxHa)), line: { color: '#fff', width: 1 } },
        text: d.map((r) => `<b>${r.d}</b> (${p}) · ${y}<br>${tr('ind_irrigated')}: ${fmtPct(r.a)}<br>${tr('need_score')}: ${fmtNum(r.need, 0)}<br>${tr('w_c_scale')}: ${fmtNum(r.ha)} ha · n = ${fmtNum(r.n)}`), hoverinfo: 'text' } as Data;
    });
    return { data, layout: std({ x: tr('need_score'), y: tr('y_pct_plots_ab'), yaxis: { range: [0, maxA * 1.1] }, xaxis: { range: [0, 100] }, transition: { duration: 700, easing: 'cubic-in-out' } }) };
  }, [bub, yi, years, tr]); // eslint-disable-line

  // ---- anomaly map
  const ysOpts = useMemo(() => {
    const Y = new Set(f.years), S = new Set<string>(f.seasons);
    return [...new Set(D.rain.rain.filter((r) => Y.has(r.sas_year) && S.has(r.sas_season)).map((r) => `${r.sas_year}${r.sas_season}`))].sort().reverse();
  }, [D, f]);
  const [ys, setYs] = useState('');
  const curYs = ysOpts.includes(ys) ? ys : ysOpts[0] ?? '';
  const amap = useMemo(() => D.rain.rain.filter((r) => `${r.sas_year}${r.sas_season}` === curYs), [D, curYs]);
  const amapFig = useMemo<Fig | null>(() => {
    if (!amap.length) return null;
    const lim = Math.max(30, ...amap.map((r) => Math.abs(r.rain_anomaly_pct)));
    return choropleth(geo, amap.map((r) => ({ district: r.district_std, value: r.rain_anomaly_pct,
      hover: `<b>${r.district_std}</b><br>${fmtNum(r.rain_mm)} mm (${tr('normal')} ${fmtNum(r.rain_normal_mm)} mm)<br>${tr('anomaly')}: ${r.rain_anomaly_pct > 0 ? '+' : ''}${fmtNum(r.rain_anomaly_pct, 0)}%` })),
    { noData: tr('no_estimate'), label: tr('anomaly_pct'), colorscale: divRain, zmin: -lim, zmax: lim, selected: f.areaLevel !== 'national' ? f.districts : undefined });
  }, [amap, geo, f, tr]);
  const dryMap = amap.filter((r) => r.rain_anomaly_pct < -15).sort((a, b) => a.rain_anomaly_pct - b.rain_anomaly_pct);

  // ---- rainfall trend for the selected area
  const rt = useMemo(() => {
    const S = new Set<string>(f.seasons), Ds = new Set(f.districts);
    return [...groupBy(D.rain.rain.filter((r) => S.has(r.sas_season) && r.sas_year >= 2000 && Ds.has(r.district_std)), (r) => `${r.sas_year}|${r.sas_season}`).values()]
      .map((g) => ({ y: g[0].sas_year, s: g[0].sas_season, mm: mean(g.map((r) => r.rain_mm)), normal: mean(g.map((r) => r.rain_normal_mm)) })).sort((a, b) => a.y - b.y);
  }, [D, f]);
  const rtFig = useMemo<Fig | null>(() => {
    if (!rt.length) return null;
    const data: Data[] = [];
    for (const s of ['A', 'B', 'C']) {
      const x = rt.filter((r) => r.s === s); if (!x.length) continue;
      data.push({ type: 'bar', name: tr(`season_${s.toLowerCase()}`), x: x.map((r) => r.y), y: x.map((r) => r.mm),
        marker: { color: x.map((r) => (f.years.includes(r.y) ? seasonCols[s] : `${seasonCols[s]}55`)) },
        text: x.map((r) => `${r.y}${s}: ${fmtNum(r.mm)} mm<br>${tr('normal')} ${fmtNum(r.normal)} mm`), hoverinfo: 'text', textposition: 'none' });
      data.push({ type: 'scatter', mode: 'lines', x: x.map((r) => r.y), y: x.map((r) => r.normal), line: { color: seasonCols[s], dash: 'dash', width: 1.5, shape: 'spline' }, hoverinfo: 'skip', showlegend: false });
    }
    return { data, layout: std({ y: tr('y_rain_mm'), barmode: 'group', bargap: 0.25 }) };
  }, [rt, f, tr]);
  const rtSel = rt.filter((r) => f.years.includes(r.y)), below = rtSel.filter((r) => r.mm < 0.85 * r.normal);

  return (
    <>
      <FiltersUsed used={['years', 'seasons', 'area']} />
      <Callout icon={TriangleAlert}>{tr('need_caveat')}</Callout>
      <Grid cols="7fr 5fr">
        <ChartCard title={tr('c_quadrant')} icon={Crosshair} means={tr('m_quadrant', hnla.length, hnla.map((r) => r.district_std).join(', '))}>
          <Plot fig={quadFig} height={380} onClick={pickDistrict} />
        </ChartCard>
        <ChartCard title={tr('c_anomaly_map')} icon={Thermometer}
          tools={<Select value={curYs} onChange={setYs} options={ysOpts.map((y) => ({ value: y, label: y }))} width="100%" />}
          means={amap.length ? (dryMap.length ? tr('m_anom_dry', curYs, dryMap.length, dryMap.slice(0, 5).map((r) => r.district_std).join(', ')) : tr('m_anom_ok', curYs, fmtNum(mean(amap.map((r) => r.rain_anomaly_pct)), 0))) : null}>
          <Plot fig={amapFig} height={328} onClick={pickDistrict} empty={tr('no_data')} />
        </ChartCard>
      </Grid>
      <Grid cols="7fr 5fr">
        <ChartCard title={tr('c_bubble')} icon={CirclePlay} means={tr('m_bubble')}>
          {years.length > 0 && (
            <div className="play-row">
              <button className="btn outline sm" onClick={() => { if (yi >= years.length - 1) setYi(0); setPlaying(!playing); }}>
                {playing ? <Pause size={14} /> : <Play size={14} />} {tr(playing ? 'pause' : 'play').replace(/^[^\p{L}]+/u, '')}
              </button>
              <input type="range" min={0} max={years.length - 1} value={Math.min(yi, years.length - 1)} onChange={(e) => { setPlaying(false); setYi(+e.target.value); }} aria-label={tr('year')} />
              <span className="play-year">{years[Math.min(yi, years.length - 1)]}</span>
            </div>
          )}
          <Plot fig={bubFig} height={370} onClick={pickDistrict} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('c_rain_trend')} icon={CloudRain}
          means={!rtSel.length ? null : below.length ? tr('m_rain_trend', f.area, below.length, rtSel.length, below.map((r) => `${r.y}${r.s}`).join(', ')) : tr('m_rain_none', f.area, rtSel.length)}>
          <Plot fig={rtFig} height={400} empty={tr('no_data')} />
        </ChartCard>
      </Grid>
    </>
  );
}

import { useEffect, useMemo, useState } from 'react';
import { Map as MapIcon, Trophy, CloudSunRain, Droplet, Cog, FlaskConical, Mountain, ThermometerSun, Wheat, Sprout, ChartLine, Target, Scale, CloudRain, Calendar } from 'lucide-react';
import type { Data } from 'plotly.js';
import { useApp } from '../data/store';
import { ChartCard, Grid, Kpi, KpiRow, RelBadge, Select } from '../components/ui';
import { Plot, simpleLines, std, legendBottom, type Fig } from '../components/Plot';
import { groupBy, mean, median, mode, sum, surveyFirst, wm } from '../lib/stats';
import { fmtNum, fmtPct } from '../lib/format';
import { brand, catCols } from '../lib/theme';

export const COMP = ['c_need', 'c_gap', 'c_scale', 'c_equity', 'c_readiness'] as const;
const qKey = (q: string) => `q_${q.toLowerCase().replace(/[^a-z]/g, '')}`;

export default function District() {
  const { D, f, tr } = useApp();
  const [dist, setDist] = useState(f.district || (f.areaLevel !== 'national' ? f.districts[0] : 'Kirehe'));
  // follow the sidebar: one district selected, or the first of several
  useEffect(() => { if (f.areaLevel !== 'national' && !f.districts.includes(dist)) setDist(f.districts[0]); }, [f.districts, f.areaLevel]); // eslint-disable-line
  const prov = D.lookup.find((r) => r.district === dist)?.province ?? '';
  const seas = f.seasons.filter((s) => s !== 'C').length ? f.seasons.filter((s) => s !== 'C') : ['A', 'B'];
  const S = new Set<string>(seas), Y = new Set(f.years);
  const agg = (lv: string, ar: string, inds: string[]) => {
    const e = surveyFirst(D.est.filter((r) => r.level === lv && r.area === ar && inds.includes(r.indicator) && Y.has(r.sas_year) && S.has(r.sas_season)), (r) => r.indicator);
    return new Map([...groupBy(e, (r) => r.indicator).entries()].map(([k, g]) => [k, {
      v: wm(g.map((r) => r.estimate), g.map((r) => r.wsum)), n: sum(g.map((r) => r.n)), rel: mode(g.map((r) => r.reliability)),
    }]));
  };
  const sc = D.screen.table.find((r) => r.district_std === dist);
  const nd = D.rain.district.find((r) => r.district_std === dist);

  const tiles = useMemo(() => {
    const inds = ['irrigated', 'irrig_modern', 'inorganic_fert', 'anti_erosion'];
    const a = agg('district', dist, inds), r = agg('national', 'Rwanda', inds);
    const tot = [...groupBy(D.totals.filter((x) => x.level === 'district' && x.area === dist && S.has(x.sas_season) && Y.has(x.sas_year)), (x) => String(x.sas_year)).values()]
      .map((g) => ({ t: sum(g.map((x) => x.production_t)), cult: sum(g.map((x) => x.cultivated_area_ha)) }));
    return { a, r, t: mean(tot.map((x) => x.t)), cult: mean(tot.map((x) => x.cult)) };
  }, [D, dist, f]); // eslint-disable-line

  const trendD = useMemo(() => {
    const ser = (lv: string, ar: string) => [...groupBy(D.est.filter((r) => r.level === lv && r.area === ar && r.indicator === 'irrigated' && S.has(r.sas_season) && Y.has(r.sas_year)), (r) => String(r.sas_year)).values()]
      .map((g) => ({ y: g[0].sas_year, e: wm(g.map((r) => r.estimate), g.map((r) => r.wsum)), n: sum(g.map((r) => r.n)) })).sort((a, b) => a.y - b.y);
    return [{ who: dist, d: ser('district', dist), col: brand.blue }, { who: prov, d: ser('province', prov), col: '#B07A1C' }, { who: 'Rwanda', d: ser('national', 'Rwanda'), col: brand.grey }];
  }, [D, dist, prov, f]); // eslint-disable-line
  const trendFig = useMemo<Fig | null>(() => {
    if (!trendD[0].d.length) return null;
    const data: Data[] = trendD.filter((s) => s.d.length).map((s) => ({
      type: 'scatter', mode: 'lines+markers', name: s.who, x: s.d.map((r) => r.y), y: s.d.map((r) => r.e),
      line: { color: s.col, dash: s.who === 'Rwanda' ? 'dot' : 'solid', shape: 'spline', smoothing: 0.5 }, marker: { color: s.col },
      text: s.d.map((r) => `${s.who} ${r.y}: ${fmtPct(r.e)} · n = ${fmtNum(r.n)}`), hoverinfo: 'text',
    }));
    return simpleLines(data, std({ y: tr('y_pct_plots_ab'), xaxis: { dtick: 1 } }));
  }, [trendD, tr]);
  const trendMeans = (() => {
    const d = trendD[0].d, r = trendD[2].d; if (d.length < 2) return null;
    const above = d.filter((x) => { const n = r.find((z) => z.y === x.y); return n && x.e > n.e; }).length;
    return tr('m_d_trend', dist, above, d.length, fmtPct(d[d.length - 1].e), d[d.length - 1].y);
  })();

  const radarFig = useMemo<Fig | null>(() => {
    if (!sc) return null;
    const lab = COMP.map((c) => tr(`w_${c}`).replace(/(.{1,16})(\s|$)/g, '$1<br>').replace(/<br>$/, ''));
    const med = COMP.map((c) => 100 * median(D.screen.table.map((r) => r[c])));
    const v = COMP.map((c) => 100 * sc[c]);
    const close = <T,>(x: T[]) => [...x, x[0]];
    return {
      data: [
        { type: 'scatterpolar', mode: 'lines+markers', r: close(med), theta: close(lab), name: tr('median_district'), line: { color: brand.grey, dash: 'dot' }, marker: { color: brand.grey, size: 5 }, hoverinfo: 'text', text: close(med).map((x, i) => `${close(lab)[i]}: ${Math.round(x)}`) },
        { type: 'scatterpolar', mode: 'lines+markers', r: close(v), theta: close(lab), name: dist, fill: 'toself', fillcolor: `${brand.blue}33`, line: { color: brand.blue, width: 2.5 }, marker: { color: brand.blue, size: 7 }, hoverinfo: 'text', text: close(v).map((x, i) => `${close(lab)[i]}: ${Math.round(x)}`) },
      ] as Data[],
      layout: { ...std(), polar: { domain: { x: [0.12, 0.88], y: [0.05, 0.95] }, radialaxis: { range: [0, 100], gridcolor: '#E4EAE5', tickfont: { size: 10 } }, angularaxis: { gridcolor: '#E4EAE5', tickfont: { size: 10.5 } }, bgcolor: 'rgba(0,0,0,0)' }, legend: { orientation: 'h', y: -0.1 }, margin: { l: 20, r: 20, t: 30, b: 20 } },
    };
  }, [sc, D, dist, tr]);

  const gapD = useMemo(() => {
    const inds = ['irrigated', 'irrig_modern', 'irrig_any_farmer', 'inorganic_fert', 'organic_fert', 'pesticide', 'anti_erosion', 'land_consolidated', 'agroforestry'];
    const a = agg('district', dist, inds), r = agg('national', 'Rwanda', inds);
    return inds.filter((i) => a.has(i)).map((i) => ({ i, label: tr(`ind_${i}`), v: a.get(i)!.v, n: a.get(i)!.n, rel: a.get(i)!.rel, nat: r.get(i)?.v ?? NaN }))
      .map((x) => ({ ...x, gap: x.v - x.nat })).sort((a2, b) => a2.gap - b.gap);
  }, [D, dist, f, tr]); // eslint-disable-line
  const gapFig = useMemo<Fig | null>(() => !gapD.length ? null : {
    data: [
      ...gapD.map((r) => ({ type: 'scatter', mode: 'lines', x: [r.nat, r.v], y: [r.label, r.label], line: { color: '#D5DDD8', width: 5 }, hoverinfo: 'skip', showlegend: false })),
      { type: 'scatter', mode: 'markers', name: 'Rwanda', x: gapD.map((r) => r.nat), y: gapD.map((r) => r.label), marker: { size: 11, color: brand.grey }, text: gapD.map((r) => `${r.label} · Rwanda: ${fmtPct(r.nat)}`), hoverinfo: 'text' },
      { type: 'scatter', mode: 'markers', name: dist, x: gapD.map((r) => r.v), y: gapD.map((r) => r.label), marker: { size: 13, color: gapD.map((r) => (r.gap >= 0 ? brand.green : brand.terracotta)), line: { color: '#fff', width: 2 } },
        text: gapD.map((r) => `<b>${r.label}</b> · ${dist}: ${fmtPct(r.v)} (${r.gap >= 0 ? '+' : ''}${fmtNum(r.gap, 1)} pts)<br>n = ${fmtNum(r.n)} · ${r.rel}`), hoverinfo: 'text' },
    ] as Data[],
    layout: std({ x: tr('x_pct_plots'), yaxis: { title: { text: '' }, categoryorder: 'array', categoryarray: gapD.map((r) => r.label) } }),
  }, [gapD, dist, tr]);

  const cropsD = useMemo(() => {
    const Sf = new Set<string>(f.seasons);
    const d = D.crop_dist.filter((r) => r.district_std === dist && Y.has(r.sas_year) && Sf.has(r.sas_season) && (!f.cropGroups.length || f.cropGroups.includes(r.crop_group)) && (!f.crops.length || f.crops.includes(r.crop_name)));
    return [...groupBy(d, (r) => r.crop_name).values()].map((g) => ({ crop: g[0].crop_name, grp: g[0].crop_group, t: sum(g.map((r) => r.production_t)) / new Set(g.map((r) => r.sas_year)).size }))
      .sort((a, b) => b.t - a.t).slice(0, 10).reverse();
  }, [D, dist, f]); // eslint-disable-line
  const cropsFig = useMemo<Fig | null>(() => {
    if (!cropsD.length) return null;
    const cols = catCols([...new Set(D.crop.map((r) => r.crop_group))].sort());
    const grps = [...new Set(cropsD.map((r) => r.grp))];
    const mx = Math.max(...cropsD.map((r) => r.t / 1000));
    return {
      data: grps.map((g) => { const x = cropsD.filter((r) => r.grp === g); return {
        type: 'bar', orientation: 'h', name: g, y: x.map((r) => r.crop), x: x.map((r) => r.t / 1000), marker: { color: cols[g] },
        text: x.map((r) => `${fmtNum(r.t / 1000, 1)} kt`), textposition: 'outside', cliponaxis: false, textfont: { size: 11, color: brand.ink },
        hovertext: x.map((r) => `<b>${r.crop}</b> (${g})<br>${fmtNum(r.t / 1000, 1)} kt ${tr('per_year')}`), hoverinfo: 'text' } as Data; }),
      layout: std({ x: tr('y_kt'), legend: legendBottom(-0.25), bargap: 0.3, yaxis: { title: { text: '' }, categoryorder: 'array', categoryarray: cropsD.map((r) => r.crop) }, xaxis: { range: [0, mx * 1.25] } }),
    };
  }, [cropsD, D, tr]);

  const rainD = useMemo(() => D.rain.rain.filter((r) => r.district_std === dist && r.sas_year >= 2010 && S.has(r.sas_season))
    .sort((a, b) => a.sas_year - b.sas_year || a.sas_season.localeCompare(b.sas_season)), [D, dist, f]); // eslint-disable-line
  const rainFig = useMemo<Fig | null>(() => !rainD.length ? null : {
    data: [{ type: 'bar', x: rainD.map((r) => `${r.sas_year}${r.sas_season}`), y: rainD.map((r) => r.rain_anomaly_pct),
      marker: { color: rainD.map((r) => { const c = r.rain_anomaly_pct < -15 ? brand.terracotta : r.rain_anomaly_pct > 15 ? brand.blue : '#A9C7B5'; return Y.has(r.sas_year) ? c : `${c}55`; }) },
      text: rainD.map((r) => `<b>${r.sas_year}${r.sas_season}</b><br>${fmtNum(r.rain_mm)} mm (${tr('normal')} ${fmtNum(r.rain_normal_mm)})<br>${r.rain_anomaly_pct > 0 ? '+' : ''}${fmtNum(r.rain_anomaly_pct, 0)}%`), hoverinfo: 'text', textposition: 'none' }],
    layout: std({ y: tr('anomaly_pct'), legend: false, xaxis: { type: 'category', tickangle: -60, tickfont: { size: 10 } }, yaxis: { rangemode: 'normal' } }),
  }, [rainD, tr]); // eslint-disable-line
  const dry = rainD.filter((r) => r.rain_anomaly_pct < -15);

  const g = (m: Map<string, { v: number; rel: string | null }>, i: string) => m.get(i)?.v ?? NaN;
  const tile = (i: string, Icon: typeof Droplet, col: string) => (
    <Kpi label={tr(`ind_${i}`)} value={fmtPct(g(tiles.a, i))} icon={Icon} color={col} delta={g(tiles.a, i) - g(tiles.r, i)}
      foot={<>{tr('vs_rwanda', fmtPct(g(tiles.r, i)))} <RelBadge r={tiles.a.get(i)?.rel} /></>} />
  );
  const comps = sc ? COMP.map((c) => ({ c, v: sc[c] })) : [];
  const top = comps.length ? comps.reduce((a, b) => (b.v > a.v ? b : a)) : null, low = comps.length ? comps.reduce((a, b) => (b.v < a.v ? b : a)) : null;
  const gl = gapD.length ? gapD[gapD.length - 1] : null;

  return (
    <>
      <div className="district-bar">
        <Select value={dist} onChange={setDist} options={[...D.lookup.map((r) => r.district)].sort().map((d) => ({ value: d, label: d }))} />
        <span className="pill"><MapIcon size={14} /> {prov}</span>
        {sc && <span className="pill strong"><Trophy size={14} /> {tr('profile_rank', sc.rank, sc.stability)}</span>}
        {nd && <span className="pill warn"><CloudSunRain size={14} /> {tr(qKey(nd.quadrant))}</span>}
      </div>
      <p className="muted small"><Calendar size={13} /> {tr('d_period2', `${Math.min(...f.years)}–${Math.max(...f.years)}`, seas.join('+'))}</p>
      <KpiRow>
        {tile('irrigated', Droplet, brand.blue)}{tile('irrig_modern', Cog, '#B07A1C')}{tile('inorganic_fert', FlaskConical, '#6A4C93')}{tile('anti_erosion', Mountain, brand.green)}
      </KpiRow>
      <KpiRow>
        <Kpi label={tr('need_score')} value={`${fmtNum(nd?.need_score, 0)}/100`} icon={ThermometerSun} color={brand.terracotta} foot={nd && tr('d_need_sub', fmtNum(nd.rain_normal_ab_mm), nd.dry_seasons_2016_2025)} />
        <Kpi label={tr('k_production')} value={`${fmtNum(tiles.t / 1000, 1)} kt`} icon={Wheat} color="#B07A1C" foot={tr('d_prod_sub')} />
        <Kpi label={tr('w_c_scale')} value={`${fmtNum(tiles.cult / 1000, 1)}k ha`} icon={Sprout} color={brand.green} foot={tr('d_area_sub')} />
        <Kpi label={tr('score')} value={`${fmtNum(sc?.score, 0)}/100`} icon={Trophy} color={brand.blue} foot={sc && tr('d_score_sub', sc.rank, Math.round(sc.rank_p10), Math.round(sc.rank_p90))} />
      </KpiRow>
      <Grid cols="7fr 5fr">
        <ChartCard title={tr('c_d_trend')} icon={ChartLine} means={trendMeans}><Plot fig={trendFig} height={300} empty={tr('no_data')} /></ChartCard>
        <ChartCard title={tr('c_d_radar')} icon={Target} means={top && low && tr('m_d_radar', dist, tr(`w_${top.c}`), tr(`w_${low.c}`))}><Plot fig={radarFig} height={300} empty={tr('no_data')} /></ChartCard>
      </Grid>
      <Grid cols="1fr 1fr">
        <ChartCard title={tr('c_d_gap')} icon={Scale} means={gl && tr('m_d_gap', dist, gl.label, fmtNum(gl.gap, 1), gapD[0].label, fmtNum(gapD[0].gap, 1))}><Plot fig={gapFig} height={300} empty={tr('no_data')} /></ChartCard>
        <ChartCard title={tr('c_d_crops')} icon={Wheat}
          means={cropsD.length ? (() => { const d = [...cropsD].reverse(); return tr('m_d_crops', dist, d[0].crop, fmtNum(d[0].t / 1000, 1), d.slice(1, 3).map((r) => r.crop).join(', ')); })() : null}>
          <Plot fig={cropsFig} height={300} empty={tr('no_data')} />
        </ChartCard>
      </Grid>
      <ChartCard title={tr('c_d_rain')} icon={CloudRain} means={rainD.length ? tr('m_d_rain', dist, dry.length, rainD.length, dry.length ? dry.map((r) => `${r.sas_year}${r.sas_season}`).join(', ') : '–') : null}>
        <Plot fig={rainFig} height={250} empty={tr('no_data')} />
      </ChartCard>
    </>
  );
}

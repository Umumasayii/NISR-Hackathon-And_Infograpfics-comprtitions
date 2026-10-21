import { useEffect, useMemo, useState } from 'react';
import { Map as MapIcon, Trophy, CloudSunRain, Droplet, Cog, FlaskConical, LandPlot, UserCheck, ThermometerSun, Wheat, ChartLine, Target, Scale, CloudRain, Calendar } from 'lucide-react';
import type { Data } from 'plotly.js';
import { useApp } from '../data/store';
import { ChartCard, Grid, Kpi, KpiRow, RelBadge, Select } from '../components/ui';
import { Plot, simpleLines, std, legendBottom, type Fig } from '../components/Plot';
import { groupBy, median, mode, sum, wm } from '../lib/stats';
import { citeShort, cite, pubSource, seasonsOf, splitAtUpgrade, FIRST_UPGRADED, type YS } from '../lib/official';
import type { PubRow, Season } from '../data/types';
import { fmtNum, fmtPct } from '../lib/format';
import { brand, seasonCols } from '../lib/theme';

export const COMP = ['c_need', 'c_gap', 'c_scale', 'c_equity', 'c_readiness'] as const;
const qKey = (q: string) => `q_${q.toLowerCase().replace(/[^a-z]/g, '')}`;

export default function District() {
  const { D, O, f, tr } = useApp();
  const [dist, setDist] = useState(f.district || (f.areaLevel !== 'national' ? f.districts[0] : 'Kirehe'));
  // follow the sidebar: one district selected, or the first of several
  useEffect(() => { if (f.areaLevel !== 'national' && !f.districts.includes(dist)) setDist(f.districts[0]); }, [f.districts, f.areaLevel]); // eslint-disable-line
  const prov = D.lookup.find((r) => r.district === dist)?.province ?? '';
  const seas = f.seasons.filter((s) => s !== 'C').length ? f.seasons.filter((s) => s !== 'C') : ['A', 'B'];
  const S = new Set<string>(seas), Y = new Set(f.years);
  const agg = (lv: string, ar: string, inds: string[]) => {
    const e = D.est.filter((r) => r.level === lv && r.area === ar && inds.includes(r.indicator) && Y.has(r.sas_year) && S.has(r.sas_season));
    return new Map([...groupBy(e, (r) => r.indicator).entries()].map(([k, g]) => [k, {
      v: wm(g.map((r) => r.estimate), g.map((r) => r.wsum)), n: sum(g.map((r) => r.n)), rel: mode(g.map((r) => r.reliability)),
    }]));
  };
  const sc = D.screen.table.find((r) => r.district_std === dist);
  const nd = D.rain.district.find((r) => r.district_std === dist);

  // published NISR figures for the newest selected main season (one season: NISR publishes no multi-season figure)
  const ss = seasonsOf(f, seas as Season[]);
  const ps: YS | undefined = ss[ss.length - 1];
  const pub = (ind: string, area = dist, x: YS | undefined = ps) => (O && x ? O.get(ind, x.y, x.s, area) : undefined);
  const tiles = useMemo(() => {
    const inds = ['irrigated', 'irrig_modern'];
    const a = agg('district', dist, inds), r = agg('national', 'Rwanda', inds);
    // harvests of Seasons A and B add up (our estimate, labelled); land never does
    const tot = [...groupBy(D.totals.filter((x) => x.level === 'district' && x.area === dist && S.has(x.sas_season) && Y.has(x.sas_year)), (x) => String(x.sas_year)).values()]
      .map((g) => (g.every((x) => x.production_t != null) ? sum(g.map((x) => x.production_t)) : NaN));
    return { a, r, t: tot.length && tot.every(Number.isFinite) ? sum(tot) / tot.length : NaN };
  }, [D, dist, f]); // eslint-disable-line

  const trendD = useMemo(() => {
    if (!O) return [];
    const S2 = f.seasons;
    return [dist, 'Rwanda'].flatMap((who) => S2.map((sn) => ({ who, s: sn,
      d: f.years.map((y) => O.get('irrig_any_farmer', y, sn, who)).filter((r): r is PubRow => !!r && r.value != null) })))
      .filter((x) => x.d.length);
  }, [O, dist, f]);
  const trendFig = useMemo<Fig | null>(() => {
    if (!trendD.length || !O) return null;
    const data: Data[] = trendD.map((x) => ({
      type: 'scatter', mode: 'lines+markers', name: `${x.who} · ${tr('season_of', x.s, '').trim()}`, connectgaps: false,
      x: splitAtUpgrade(x.d.map((r) => r.sas_year), x.d).x, y: splitAtUpgrade(x.d.map((r) => r.sas_year), x.d.map((r) => r.value as number)).y,
      line: { color: seasonCols[x.s], dash: x.who === 'Rwanda' ? 'dot' : 'solid', width: x.who === 'Rwanda' ? 1.5 : 2.5 },
      marker: { color: seasonCols[x.s], symbol: x.who === 'Rwanda' ? 'circle-open' : 'circle', size: 7 },
      text: splitAtUpgrade(x.d.map((r) => r.sas_year), x.d).y.map((r) => !r ? '' : `${x.who} ${r.sas_year}${r.sas_season}: ${fmtPct(r.value)}<br>${citeShort(O, r)}, ${tr('cell')} ${r.cell}`), hoverinfo: 'text',
    }));
    return simpleLines(data, std({ y: tr('x_pct_farmers'), xaxis: { dtick: 1 }, yaxis: { ticksuffix: '%', rangemode: 'tozero' } }));
  }, [trendD, O, tr]);
  const trendMeans = (() => {
    const d = trendD.find((x) => x.who === dist && x.s === (ps?.s ?? 'A'));
    const r = trendD.find((x) => x.who === 'Rwanda' && x.s === (ps?.s ?? 'A'));
    if (!d || !r || d.d.length < 2) return null;
    const dd = d.d.filter((x) => x.sas_year >= FIRST_UPGRADED);
    if (dd.length < 2) return null;
    const above = dd.filter((x) => { const n = r.d.find((z) => z.sas_year === x.sas_year); return n && (x.value as number) > (n.value as number); }).length;
    const l = d.d[d.d.length - 1];
    return tr('m_d_trend_pub', dist, tr('season_of', l.sas_season, '').trim(), above, dd.length, fmtPct(l.value), l.sas_year);
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

  const GAP_PUB = ['irrig_any_farmer', 'inorganic_fert_farmer', 'organic_fert_farmer', 'pesticide_farmer', 'anti_erosion_farmer', 'agroforestry_farmer', 'improved_seed_farmer', 'mechanised_farmer'];
  const gapD = useMemo(() => GAP_PUB.map((i) => ({ i, d: pub(i), n: pub(i, 'Rwanda') }))
    .filter((x) => x.d?.value != null && x.n?.value != null)
    .map((x) => ({ i: x.i, label: tr(`pub_ind_${x.i}`), v: x.d!.value as number, nat: x.n!.value as number, r: x.d!, gap: (x.d!.value as number) - (x.n!.value as number), n: NaN, rel: null as string | null }))
    .sort((a2, b) => a2.gap - b.gap), [O, dist, ps, tr]); // eslint-disable-line
  const gapFig = useMemo<Fig | null>(() => !gapD.length ? null : {
    data: [
      ...gapD.map((r) => ({ type: 'scatter', mode: 'lines', x: [r.nat, r.v], y: [r.label, r.label], line: { color: '#D5DDD8', width: 5 }, hoverinfo: 'skip', showlegend: false })),
      { type: 'scatter', mode: 'markers', name: 'Rwanda', x: gapD.map((r) => r.nat), y: gapD.map((r) => r.label), marker: { size: 11, color: brand.grey }, text: gapD.map((r) => `${r.label} · Rwanda: ${fmtPct(r.nat)}`), hoverinfo: 'text' },
      { type: 'scatter', mode: 'markers', name: dist, x: gapD.map((r) => r.v), y: gapD.map((r) => r.label), marker: { size: 13, color: gapD.map((r) => (r.gap >= 0 ? brand.green : brand.terracotta)), line: { color: '#fff', width: 2 } },
        text: gapD.map((r) => `<b>${r.label}</b> · ${dist}: ${fmtPct(r.v)} (${r.gap >= 0 ? '+' : ''}${fmtNum(r.gap, 1)} pts)<br>${O ? citeShort(O, r.r) : ''}, ${tr('cell')} ${r.r.cell}`), hoverinfo: 'text' },
    ] as Data[],
    layout: std({ x: tr('x_pct_farmers'), legend: legendBottom(-0.2), yaxis: { title: { text: '' }, categoryorder: 'array', categoryarray: gapD.map((r) => r.label) } }),
  }, [gapD, dist, tr]);

  const cropsD = useMemo(() => {
    if (!O || !ps) return [];
    return O.of('production_t').filter((r) => r.area === dist && r.sas_year === ps.y && r.sas_season === ps.s && !r.is_group && r.value != null && r.crop_name)
      .map((r) => ({ crop: r.crop_name as string, t: r.value as number, r })).sort((a, b) => b.t - a.t).slice(0, 10).reverse();
  }, [O, dist, ps]);
  const cropsFig = useMemo<Fig | null>(() => {
    if (!cropsD.length) return null;
    const mx = Math.max(...cropsD.map((r) => r.t / 1000));
    return {
      data: [{ type: 'bar', orientation: 'h', y: cropsD.map((r) => r.crop), x: cropsD.map((r) => r.t / 1000), marker: { color: brand.amber },
        text: cropsD.map((r) => `${fmtNum(r.t / 1000, 1)} kt`), textposition: 'outside', cliponaxis: false, textfont: { size: 11, color: brand.ink },
        hovertext: cropsD.map((r) => `<b>${r.crop}</b><br>${fmtNum(r.t)} t<br>${O ? citeShort(O, r.r) : ''}, ${tr('cell')} ${r.r.cell}`), hoverinfo: 'text' } as Data],
      layout: std({ x: tr('y_kt'), legend: false, bargap: 0.3, margin: { l: 10, r: 50, t: 4, b: 30 }, yaxis: { title: { text: '' }, categoryorder: 'array', categoryarray: cropsD.map((r) => r.crop) }, xaxis: { range: [0, mx * 1.25] } }),
    };
  }, [cropsD, O, tr]);

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
    <Kpi label={`${tr(`ind_${i}`)}`} value={fmtPct(g(tiles.a, i))} icon={Icon} color={col} delta={g(tiles.a, i) - g(tiles.r, i)}
      foot={<>{tr('vs_rwanda', fmtPct(g(tiles.r, i)))} · {tr('layer_est')} <RelBadge r={tiles.a.get(i)?.rel} /></>} />
  );
  const ptile = (i: string, Icon: typeof Droplet, col: string) => {
    const r = pub(i), n = pub(i, 'Rwanda');
    const isHa = O?.def.get(i)?.unit === 'ha';
    return <Kpi label={tr(`pub_ind_${i}`)} icon={Icon} color={col}
      value={r?.value != null ? (isHa ? `${fmtNum(r.value / 1000, 1)}k ha` : fmtPct(r.value)) : '–'}
      delta={!isHa && r?.value != null && n?.value != null ? r.value - n.value : null}
      foot={r && O ? <>{isHa ? (ps ? tr('season_of', ps.s, ps.y) : '') : tr('vs_rwanda', fmtPct(n?.value))} · <span className="pub-tag" title={cite(O, r)}>{citeShort(O, r)}</span></> : tr('pub_unavailable')}
      hint={r && O ? cite(O, r) : undefined} />;
  };
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
      <p className="muted small"><Calendar size={13} /> {tr('d_period_pub', ps ? tr('season_of', ps.s, ps.y) : '–', `${Math.min(...f.years)}–${Math.max(...f.years)}`, seas.join('+'))}</p>
      <KpiRow>
        {ptile('irrig_any_farmer', UserCheck, brand.blue)}{ptile('inorganic_fert_farmer', FlaskConical, '#6A4C93')}{ptile('cultivated_land_ha', LandPlot, brand.green)}{tile('irrigated', Droplet, '#3B8FCF')}
      </KpiRow>
      <KpiRow>
        <Kpi label={tr('need_score')} value={`${fmtNum(nd?.need_score, 0)}/100`} icon={ThermometerSun} color={brand.terracotta} foot={nd && tr('d_need_sub', fmtNum(nd.rain_normal_ab_mm), nd.dry_seasons_2016_2025)} />
        <Kpi label={tr('k_production')} value={`${fmtNum(tiles.t / 1000, 1)} kt`} icon={Wheat} color="#B07A1C" foot={<>{tr('d_prod_sub')} · {tr('layer_est')}</>} />
        {tile('irrig_modern', Cog, '#B07A1C')}
        <Kpi label={tr('score')} value={`${fmtNum(sc?.score, 0)}/100`} icon={Trophy} color={brand.blue} foot={sc && tr('d_score_sub', sc.rank, Math.round(sc.rank_p10), Math.round(sc.rank_p90))} />
      </KpiRow>
      <Grid cols="7fr 5fr">
        <ChartCard title={tr('c_d_trend_pub')} icon={ChartLine} means={trendMeans} source={O ? pubSource(O, trendD.flatMap((x) => x.d), tr) : tr('pub_unavailable')}
          table={{ cols: [tr('season'), dist, 'Rwanda'], rows: f.years.flatMap((y) => f.seasons.map((sn) => [`${y}${sn}`, pub('irrig_any_farmer', dist, { y, s: sn })?.value ?? null, pub('irrig_any_farmer', 'Rwanda', { y, s: sn })?.value ?? null]))
            .filter((r) => r[1] != null || r[2] != null).map((r) => [r[0], fmtPct(r[1] as number | null), fmtPct(r[2] as number | null)]) }}>
          <Plot fig={trendFig} height={300} empty={tr('pub_unavailable')} /></ChartCard>
        <ChartCard title={tr('c_d_radar')} icon={Target} means={top && low && tr('m_d_radar', dist, tr(`w_${top.c}`), tr(`w_${low.c}`))}><Plot fig={radarFig} height={300} empty={tr('no_data')} /></ChartCard>
      </Grid>
      <Grid cols="1fr 1fr">
        <ChartCard title={tr('c_d_gap_pub')} icon={Scale} means={gl && <>{tr('m_d_gap', dist, gl.label, fmtNum(gl.gap, 1), gapD[0].label, fmtNum(gapD[0].gap, 1))} {ps ? tr('season_of', ps.s, ps.y) : ''}.</>}
          source={O ? pubSource(O, gapD.map((x) => x.r), tr) : tr('pub_unavailable')}
          table={{ cols: ['', dist, 'Rwanda', tr('pub_cell')], rows: gapD.map((x) => [x.label, fmtPct(x.v), fmtPct(x.nat), O ? `${citeShort(O, x.r)} · ${x.r.cell}` : '']) }}>
          <Plot fig={gapFig} height={320} empty={tr('pub_unavailable')} /></ChartCard>
        <ChartCard title={tr('c_d_crops_pub')} icon={Wheat}
          source={O ? pubSource(O, cropsD.map((x) => x.r), tr) : tr('pub_unavailable')}
          table={{ cols: [tr('crop'), 't', tr('pub_cell')], rows: [...cropsD].reverse().map((x) => [x.crop, Math.round(x.t), O ? `${citeShort(O, x.r)} · ${x.r.cell}` : '']) }}
          means={cropsD.length ? (() => { const d = [...cropsD].reverse(); return tr('m_d_crops_pub', dist, ps ? tr('season_of', ps.s, ps.y) : '', d[0].crop, fmtNum(d[0].t / 1000, 1), d.slice(1, 3).map((r) => r.crop).join(', ')); })() : tr('pub_unavailable')}>
          <Plot fig={cropsFig} height={300} empty={tr('pub_unavailable')} />
        </ChartCard>
      </Grid>
      <ChartCard title={tr('c_d_rain')} icon={CloudRain} means={rainD.length ? tr('m_d_rain', dist, dry.length, rainD.length, dry.length ? dry.map((r) => `${r.sas_year}${r.sas_season}`).join(', ') : '–') : null}>
        <Plot fig={rainFig} height={250} empty={tr('no_data')} />
      </ChartCard>
    </>
  );
}

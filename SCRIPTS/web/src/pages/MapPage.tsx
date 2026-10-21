import { useEffect, useMemo, useState } from 'react';
import { MapPinned, MapPin, ArrowDownWideNarrow, Hand, Play, Pause, CloudRain, Trophy } from 'lucide-react';
import { useApp } from '../data/store';
import { ChartCard, FiltersUsed, Grid, RelBadge, Select } from '../components/ui';
import { Plot, choropleth, std, type Fig } from '../components/Plot';
import { downloadCsv, groupBy, mean, mode, sum, wm } from '../lib/stats';
import { citeShort, cite, pubCsv, pubSource, seasonsOf, ysKey, type YS } from '../lib/official';
import { fmtNum, fmtPct } from '../lib/format';
import { brand, colIrrigated, seqGreen } from '../lib/theme';
import type { PubRow } from '../data/types';

// Published NISR figures first ("pub:"), one season at a time: NISR publishes each season
// on its own and no district total of several seasons. Our own estimates follow, labelled,
// for questions NISR does not publish (plots irrigated, motorised and modern methods).
const PUB = ['irrig_any_farmer', 'inorganic_fert_farmer', 'inorganic_fert', 'organic_fert_farmer', 'pesticide_farmer', 'cultivated_land_ha', 'anti_erosion_farmer'];
const OURS = ['irrigated', 'irrig_modern', 'anti_erosion', 'irrigated_area_ha'];
const isTotal = (m: string) => m === 'irrigated_area_ha';

interface Val { district: string; value: number; n: number | null; rel: string | null; r?: PubRow }

export default function MapPage() {
  const { D, O, f, tr, geo, pickDistrict } = useApp();
  const [metric, setMetric] = useState(O ? 'pub:irrig_any_farmer' : 'irrigated');
  const [animate, setAnimate] = useState(false);
  const isPub = metric.startsWith('pub:');
  const ind = metric.replace(/^pub:/, '');
  const total = isTotal(ind);
  const pubUnit = isPub ? O?.def.get(ind)?.unit ?? '%' : '';
  const unit = isPub ? (pubUnit === '%' ? '%' : ` ${pubUnit}`) : total ? ' ha' : '%';
  const dec = unit === '%' ? 1 : 0;
  const selected = f.areaLevel !== 'national' ? f.districts : undefined;
  const indLabel = isPub ? `${tr(`pub_ind_${ind}`)} (NISR)` : `${tr(`ind_${ind}`)} (${tr('layer_est')})`;

  // the one season a published map is for
  const ss = useMemo(() => seasonsOf(f), [f]);
  const [seasonKey, setSeasonKey] = useState('');
  const mainLast = [...ss].reverse().find((x) => x.s !== 'C') ?? ss[ss.length - 1];
  const ps: YS | undefined = ss.find((x) => ysKey(x) === seasonKey) ?? mainLast;
  useEffect(() => { if (seasonKey && !ss.some((x) => ysKey(x) === seasonKey)) setSeasonKey(''); }, [ss, seasonKey]);

  // published: one value per district for each selected year of that season
  const pubYear = useMemo(() => {
    if (!isPub || !O || !ps) return [];
    return f.years.flatMap((y) => D.lookup.map((l) => O.get(ind, y, ps.s, l.district)))
      .filter((r): r is PubRow => !!r && r.value != null)
      .map((r) => ({ district: r.area, year: r.sas_year, value: r.value as number, n: null, rel: null, r }));
  }, [isPub, O, ps, f.years, D, ind]);

  // ours: district values per year (selected seasons pooled with survey weights; hectares averaged per season)
  const perYear = useMemo(() => {
    if (isPub) return pubYear;
    const Y = new Set(f.years), S = new Set<string>(f.seasons);
    if (total) {
      const t = D.totals.filter((r) => r.level === 'district' && Y.has(r.sas_year) && S.has(r.sas_season));
      return [...groupBy(t, (r) => `${r.area}|${r.sas_year}`).values()].map((g) => ({
        district: g[0].area, year: g[0].sas_year, n: null as number | null, rel: null as string | null,
        value: (() => { const v = g.map((r) => r.irrigated_area_ha); return v.some((x) => x == null) ? NaN : mean(v); })(),
      }));
    }
    const e = D.est.filter((r) => r.level === 'district' && r.indicator === ind && Y.has(r.sas_year) && S.has(r.sas_season));
    return [...groupBy(e, (r) => `${r.area}|${r.sas_year}`).values()].map((g) => ({
      district: g[0].area, year: g[0].sas_year, value: wm(g.map((r) => r.estimate), g.map((r) => r.wsum)), n: sum(g.map((r) => r.n)), rel: mode(g.map((r) => r.reliability)),
    }));
  }, [D, f, ind, total, isPub, pubYear]);

  const vals = useMemo<Val[]>(() => {
    if (isPub) {
      if (!O || !ps) return [];
      return D.lookup.map((l) => O.get(ind, ps.y, ps.s, l.district)).filter((r): r is PubRow => !!r && r.value != null)
        .map((r) => ({ district: r.area, value: r.value as number, n: null, rel: null, r }));
    }
    const Y = new Set(f.years), S = new Set<string>(f.seasons);
    if (total) return [...groupBy(perYear, (r) => r.district).values()].map((g) => ({ district: g[0].district, value: g.some((r) => !Number.isFinite(r.value)) ? NaN : mean(g.map((r) => r.value)), n: null, rel: null }));
    const e = D.est.filter((r) => r.level === 'district' && r.indicator === ind && Y.has(r.sas_year) && S.has(r.sas_season));
    return [...groupBy(e, (r) => r.area).values()].map((g) => ({ district: g[0].area, value: wm(g.map((r) => r.estimate), g.map((r) => r.wsum)), n: sum(g.map((r) => r.n)), rel: mode(g.map((r) => r.reliability)) }));
  }, [D, O, f, ind, total, perYear, isPub, ps]);

  const years = useMemo(() => [...new Set(perYear.map((r) => r.year))].sort(), [perYear]);
  const [yi, setYi] = useState(0);
  const [playing, setPlaying] = useState(false);
  useEffect(() => { setYi(0); }, [years.length, metric]);
  useEffect(() => {
    if (!playing) return;
    const t = setInterval(() => setYi((i) => { if (i + 1 >= years.length) { setPlaying(false); return i; } return i + 1; }), 1100);
    return () => clearInterval(t);
  }, [playing, years.length]);

  const label = isPub ? (pubUnit === '%' ? tr('x_pct_farmers') : pubUnit) : tr(`unit_${total ? ind : 'pct'}`);
  const hov = (r: Val) => `<b>${r.district}</b><br>${indLabel}: ${fmtNum(r.value, dec)}${unit}` +
    (r.r && O ? `<br>${citeShort(O, r.r)}, ${tr('cell')} ${r.r.cell}` : r.n != null ? `<br>n = ${fmtNum(r.n)} · ${r.rel}` : '');
  const mapFig = useMemo<Fig | null>(() => {
    if (animate) {
      const y = years[Math.min(yi, years.length - 1)];
      const d = perYear.filter((r) => r.year === y);
      if (!d.length) return null;
      const all = perYear.map((r) => r.value).filter(Number.isFinite).sort((a, b) => a - b);
      const zmax = all[Math.floor(all.length * 0.97)] ?? all[all.length - 1];
      return choropleth(geo, d.map((r) => ({ district: r.district, value: r.value, hover: `<b>${r.district}</b> · ${isPub && ps ? `${y}${ps.s}` : y}<br>${fmtNum(r.value, dec)}${unit}` })),
        { label, colorscale: seqGreen, zmin: 0, zmax, selected, noData: isPub ? tr('pub_unavailable') : tr('no_estimate') });
    }
    if (!vals.length) return null;
    return choropleth(geo, vals.map((r) => ({ district: r.district, value: r.value, weak: r.rel === 'Unreliable', hover: hov(r) })),
      { label, colorscale: seqGreen, zmin: 0, selected, noData: isPub ? tr('pub_unavailable') : tr('no_estimate') });
  }, [animate, yi, years, perYear, vals, geo, label, selected, dec, unit, isPub, ps, tr]); // eslint-disable-line

  const sorted = [...vals].filter((r) => Number.isFinite(r.value)).sort((a, b) => b.value - a.value);
  const rankFig = useMemo<Fig | null>(() => {
    const d = [...sorted].reverse(); if (!d.length) return null;
    const sel = new Set(selected ?? []);
    const lab = (x: string) => (sel.has(x) ? `▶ ${x}` : x);
    return {
      data: [{ type: 'bar', orientation: 'h', y: d.map((r) => lab(r.district)), x: d.map((r) => r.value),
        marker: { color: d.map((r) => (sel.has(r.district) ? brand.amber : colIrrigated)) }, customdata: d.map((r) => r.district),
        text: d.map((r) => `${fmtNum(r.value, dec)}${unit}`), textposition: 'outside', cliponaxis: false, textfont: { size: 10.5, color: brand.ink },
        hovertext: d.map((r) => hov(r)), hoverinfo: 'text' }],
      layout: std({ x: label, legend: false, bargap: 0.25, margin: { l: 10, r: 60, t: 4, b: 30 }, xaxis: { range: [0, Math.max(...d.map((r) => r.value)) * 1.18] },
        yaxis: { title: { text: '' }, tickfont: { size: 10.5 }, categoryorder: 'array', categoryarray: d.map((r) => lab(r.district)) } }),
    };
  }, [sorted, selected, dec, unit, label]); // eslint-disable-line
  const when = isPub && ps ? tr('season_of', ps.s, ps.y) : `${Math.min(...f.years)}–${Math.max(...f.years)}, ${f.seasons.join('+')}`;
  const source = isPub ? (O ? pubSource(O, vals.map((r) => r.r), tr) : tr('pub_unavailable'))
    : total ? tr('src_totals', when, tr('k_who_land', '').replace(/^\s*·\s*/, '')) : tr('src_plots', f.seasons.join('+'), `${Math.min(...f.years)}–${Math.max(...f.years)}`, tr('n_districts', vals.length));
  const table = { cols: [tr('district'), indLabel, isPub ? tr('pub_cell') : 'n'],
    rows: sorted.map((r) => [r.district, `${fmtNum(r.value, dec)}${unit}`, r.r && O ? `${citeShort(O, r.r)} · ${r.r.cell}` : r.n]) };

  return (
    <>
      <FiltersUsed used={['years', 'seasons', 'area']} />
      <Grid cols="2fr 1fr">
        <ChartCard title={tr('c_map')} icon={MapPinned} source={source} table={table}
          tools={<>
            <Select value={metric} onChange={setMetric} width={320} options={[
              ...(O ? PUB.map((m) => ({ value: `pub:${m}`, label: `${tr(`pub_ind_${m}`)} (NISR)` })) : []),
              ...OURS.map((m) => ({ value: m, label: `${tr(`ind_${m}`)} (${tr('layer_est')})` })),
            ]} />
            {isPub && <Select value={ps ? ysKey(ps) : ''} onChange={setSeasonKey} width={170}
              options={[...ss].reverse().map((x) => ({ value: ysKey(x), label: tr('season_of', x.s, x.y) }))} />}
            <label className="switch"><input type="checkbox" checked={animate} onChange={(e) => { setAnimate(e.target.checked); setPlaying(e.target.checked); }} /><Play size={14} /> {tr('animate_years')}</label>
          </>}
          means={sorted.length >= 3 ? <>{tr('m_map', indLabel, sorted.slice(0, 3).map((r) => r.district).join(', '), sorted.slice(-3).reverse().map((r) => r.district).join(', '))} {when}. {tr('m_click')}</> : isPub ? tr('pub_unavailable') : null}>
          {animate && years.length > 0 && (
            <div className="play-row">
              <button className="btn outline sm" onClick={() => { if (yi >= years.length - 1) setYi(0); setPlaying(!playing); }}>
                {playing ? <Pause size={14} /> : <Play size={14} />} {tr(playing ? 'pause' : 'play').replace(/^[^\p{L}]+/u, '')}
              </button>
              <input type="range" min={0} max={years.length - 1} value={Math.min(yi, years.length - 1)} onChange={(e) => { setPlaying(false); setYi(+e.target.value); }} aria-label={tr('year')} />
              <span className="play-year">{years[Math.min(yi, years.length - 1)]}{isPub && ps ? ps.s : ''}</span>
            </div>
          )}
          <Plot fig={mapFig} height={430} onClick={pickDistrict} empty={isPub ? tr('pub_unavailable') : tr('no_data')} />
        </ChartCard>
        <section className="card chart-card">
          <header className="card-head"><span className="ch-icon"><MapPin size={16} /></span><h3>{tr('c_profile')}</h3></header>
          <div className="card-body profile"><Profile ind={ind} isPub={isPub} ps={ps} vals={vals} unit={unit} dec={dec} label={indLabel} /></div>
        </section>
      </Grid>
      <ChartCard title={tr('c_ranking')} icon={ArrowDownWideNarrow} means={tr('m_rank')} source={source} table={table}>
        <Plot fig={rankFig} height={560} onClick={pickDistrict} empty={isPub ? tr('pub_unavailable') : tr('no_data')} />
      </ChartCard>
      {isPub && O && vals.length > 0 && (
        <p className="muted small"><button type="button" className="link-btn" onClick={() =>
          downloadCsv(pubCsv(O, vals.map((r) => r.r!)), `smartirrigate_nisr_${ind}_${ps ? ysKey(ps) : ''}.csv`)}>{tr('dl_pub_csv')}</button></p>
      )}
    </>
  );
}

function Profile({ ind, isPub, ps, vals, unit, dec, label }: { ind: string; isPub: boolean; ps?: YS; vals: Val[]; unit: string; dec: number; label: string }) {
  const { D, O, f, tr, pickDistrict } = useApp();
  if (!f.district && f.areaLevel !== 'national') {
    const d = vals.filter((r) => f.districts.includes(r.district)).sort((a, b) => b.value - a.value);
    return (
      <>
        <h4>{f.area}</h4><p className="muted">{tr('profile_multi', d.length)}{isPub ? ` ${tr('pub_no_sum')}` : ''}</p>
        <table className="ptable"><thead><tr><th>{tr('district')}</th><th>{label}</th></tr></thead>
          <tbody>{d.map((r) => (
            <tr key={r.district}><td><button className="link-btn" onClick={() => pickDistrict(r.district)}>{r.district}</button></td>
              <td>{fmtNum(r.value, dec)}{unit} {!isPub && <RelBadge r={r.rel} />}</td></tr>))}</tbody></table>
        <p className="muted small">{tr('profile_pick')}</p>
      </>
    );
  }
  if (!f.district) return <div className="profile-empty"><Hand size={30} /><p>{tr('profile_empty')}</p></div>;
  const dist = f.district;
  const rr = D.rain.district.find((r) => r.district_std === dist);
  const sc = D.screen.table.find((r) => r.district_std === dist);
  const head = (
    <>
      <h4>{dist}</h4>
      <p className="muted">{D.lookup.find((r) => r.district === dist)?.province} · {isPub && ps ? tr('season_of', ps.s, ps.y) : tr('profile_period', Math.min(...f.years), Math.max(...f.years), f.seasons.join('+'))}</p>
    </>
  );
  const tail = (
    <>
      {rr && <p><CloudRain size={14} /> {tr('profile_rain', fmtNum(rr.rain_normal_ab_mm), fmtNum(rr.rain_cv_pct, 0), rr.dry_seasons_2016_2025)}</p>}
      {sc && <p><Trophy size={14} /> {tr('profile_rank', sc.rank, sc.stability)}</p>}
    </>
  );
  if (isPub && O && ps) {
    const rows = PUB.filter((i) => O.def.get(i)?.unit === '%').map((i) => ({ i, d: O.get(i, ps.y, ps.s, dist), n: O.get(i, ps.y, ps.s, 'Rwanda') }));
    return (
      <>
        {head}
        <table className="ptable">
          <thead><tr><th /><th>{dist}</th><th>Rwanda</th></tr></thead>
          <tbody>{rows.map((x) => (
            <tr key={x.i} className={x.i === ind ? 'on' : ''}><td>{tr(`pub_ind_${x.i}`)}</td>
              <td title={x.d ? cite(O, x.d) : ''}>{x.d?.value != null ? fmtPct(x.d.value) : '–'}</td><td className="muted">{x.n?.value != null ? fmtPct(x.n.value) : '–'}</td></tr>))}</tbody>
        </table>
        <p className="muted small">{pubSource(O, rows.map((x) => x.d), tr)}</p>
        {tail}
      </>
    );
  }
  const inds = ['irrigated', 'irrig_modern', 'anti_erosion', 'mechanised'];
  const Y = new Set(f.years), S = new Set<string>(f.seasons);
  const pick = (lv: string, ar: string) => {
    const e = D.est.filter((r) => r.level === lv && r.area === ar && inds.includes(r.indicator) && Y.has(r.sas_year) && S.has(r.sas_season));
    return new Map([...groupBy(e, (r) => r.indicator).entries()].map(([k, g]) => [k, { v: wm(g.map((r) => r.estimate), g.map((r) => r.wsum)), n: sum(g.map((r) => r.n)), rel: mode(g.map((r) => r.reliability)) }]));
  };
  const dd = pick('district', dist), nn = pick('national', 'Rwanda');
  return (
    <>
      {head}
      <table className="ptable">
        <thead><tr><th /><th>{dist}</th><th>Rwanda</th><th>n</th></tr></thead>
        <tbody>{inds.filter((i) => dd.has(i)).map((i) => (
          <tr key={i}><td>{tr(`ind_${i}`)}</td><td>{fmtPct(dd.get(i)!.v)} <RelBadge r={dd.get(i)!.rel} /></td>
            <td className="muted">{fmtPct(nn.get(i)?.v)}</td><td className="muted">{fmtNum(dd.get(i)!.n)}</td></tr>))}</tbody>
      </table>
      <p className="muted small">{tr('layer_est')}</p>
      {tail}
    </>
  );
}

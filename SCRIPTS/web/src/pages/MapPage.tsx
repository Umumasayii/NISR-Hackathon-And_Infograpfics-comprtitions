import { useEffect, useMemo, useState } from 'react';
import { MapPinned, MapPin, ArrowDownWideNarrow, Hand, Play, Pause, CloudRain, Trophy } from 'lucide-react';
import { useApp } from '../data/store';
import { ChartCard, FiltersUsed, Grid, RelBadge, Select } from '../components/ui';
import { Plot, choropleth, std, type Fig } from '../components/Plot';
import { groupBy, mean, mode, sum, wm } from '../lib/stats';
import { fmtNum, fmtPct } from '../lib/format';
import { brand, colIrrigated, seqAmber, seqGreen } from '../lib/theme';

const METRICS = ['irrigated', 'irrig_modern', 'irrig_any_farmer', 'inorganic_fert', 'anti_erosion', 'irrigated_area_ha', 'production_t'];
const isTotal = (m: string) => m === 'irrigated_area_ha' || m === 'production_t';

export default function MapPage() {
  const { D, f, tr, geo, pickDistrict } = useApp();
  const [metric, setMetric] = useState('irrigated');
  const [animate, setAnimate] = useState(false);
  const total = isTotal(metric);
  const unit = metric === 'production_t' ? ' t' : metric === 'irrigated_area_ha' ? ' ha' : '%';
  const dec = total ? 0 : 1;
  const selected = f.areaLevel !== 'national' ? f.districts : undefined;

  // district values per year (selected seasons averaged / summed)
  const perYear = useMemo(() => {
    const Y = new Set(f.years), S = new Set<string>(f.seasons);
    if (total) {
      const t = D.totals.filter((r) => r.level === 'district' && Y.has(r.sas_year) && S.has(r.sas_season));
      return [...groupBy(t, (r) => `${r.area}|${r.sas_year}`).values()].map((g) => ({
        // tonnes of Seasons A, B and C add up; hectares do not (the same land is farmed
        // in several seasons), so an area is the average per selected season
        district: g[0].area, year: g[0].sas_year, wsum: 1, n: null as number | null, rel: null as string | null,
        value: (() => { const v = g.map((r) => (r as unknown as Record<string, number | null>)[metric]); return v.some((x) => x == null) ? NaN : metric === 'production_t' ? sum(v) : mean(v); })(),
      }));
    }
    const e = D.est.filter((r) => r.level === 'district' && r.indicator === metric && Y.has(r.sas_year) && S.has(r.sas_season));
    return [...groupBy(e, (r) => `${r.area}|${r.sas_year}`).values()].map((g) => ({
      district: g[0].area, year: g[0].sas_year, value: wm(g.map((r) => r.estimate), g.map((r) => r.wsum)), n: sum(g.map((r) => r.n)), rel: mode(g.map((r) => r.reliability)), wsum: sum(g.map((r) => r.wsum)),
    }));
  }, [D, f, metric, total]);

  // the whole period: average over the selected years (survey seasons first)
  const vals = useMemo(() => {
    const Y = new Set(f.years), S = new Set<string>(f.seasons);
    if (total) return [...groupBy(perYear, (r) => r.district).values()].map((g) => ({ district: g[0].district, value: g.some((r) => !Number.isFinite(r.value)) ? NaN : mean(g.map((r) => r.value)), n: null as number | null, rel: null as string | null }));
    const e = D.est.filter((r) => r.level === 'district' && r.indicator === metric && Y.has(r.sas_year) && S.has(r.sas_season));
    return [...groupBy(e, (r) => r.area).values()].map((g) => ({ district: g[0].area, value: wm(g.map((r) => r.estimate), g.map((r) => r.wsum)), n: sum(g.map((r) => r.n)), rel: mode(g.map((r) => r.reliability)) }));
  }, [D, f, metric, total, perYear]);

  const years = useMemo(() => [...new Set(perYear.map((r) => r.year))].sort(), [perYear]);
  const [yi, setYi] = useState(0);
  const [playing, setPlaying] = useState(false);
  useEffect(() => { setYi(0); }, [years.length, metric]);
  useEffect(() => {
    if (!playing) return;
    const t = setInterval(() => setYi((i) => { if (i + 1 >= years.length) { setPlaying(false); return i; } return i + 1; }), 1100);
    return () => clearInterval(t);
  }, [playing, years.length]);

  const label = tr(`unit_${total ? metric : 'pct'}`);
  const scale = metric === 'production_t' ? seqAmber : seqGreen;
  const mapFig = useMemo<Fig | null>(() => {
    if (animate) {
      const y = years[Math.min(yi, years.length - 1)];
      const d = perYear.filter((r) => r.year === y);
      if (!d.length) return null;
      const all = perYear.map((r) => r.value).filter(Number.isFinite).sort((a, b) => a - b);
      const zmax = all[Math.floor(all.length * 0.97)] ?? all[all.length - 1];
      return choropleth(geo, d.map((r) => ({ district: r.district, value: r.value, hover: `<b>${r.district}</b> · ${y}<br>${fmtNum(r.value, dec)}${unit}` })),
        { label, colorscale: scale, zmin: 0, zmax, selected, noData: tr('no_estimate') });
    }
    if (!vals.length) return null;
    return choropleth(geo, vals.map((r) => ({
      district: r.district, value: r.value, weak: r.rel === 'Unreliable',
      hover: `<b>${r.district}</b><br>${tr(`ind_${metric}`)}: ${fmtNum(r.value, dec)}${unit}${total ? '' : `<br>n = ${fmtNum(r.n)} · ${r.rel}`}`,
    })), { label, colorscale: scale, selected, noData: tr('no_estimate') });
  }, [animate, yi, years, perYear, vals, geo, label, scale, selected, metric, dec, unit, total, tr]);

  const sorted = [...vals].filter((r) => Number.isFinite(r.value)).sort((a, b) => b.value - a.value);
  const rankFig = useMemo<Fig | null>(() => {
    const d = [...sorted].reverse(); if (!d.length) return null;
    const sel = selected ?? [];
    return {
      data: [{ type: 'bar', orientation: 'h', y: d.map((r) => r.district), x: d.map((r) => r.value),
        marker: { color: d.map((r) => (sel.includes(r.district) ? brand.amber : colIrrigated)) }, customdata: d.map((r) => r.district),
        text: d.map((r) => `${r.district}: ${fmtNum(r.value, dec)}${unit}`), hoverinfo: 'text', textposition: 'none' }],
      layout: std({ x: label, legend: false, bargap: 0.25, yaxis: { title: { text: '' }, tickfont: { size: 10.5 } } }),
    };
  }, [sorted, selected, dec, unit, label]);

  return (
    <>
      <FiltersUsed used={['years', 'seasons', 'area']} />
      <Grid cols="2fr 1fr">
        <ChartCard title={tr('c_map')} icon={MapPinned}
          tools={<>
            <Select value={metric} onChange={setMetric} options={METRICS.map((m) => ({ value: m, label: tr(`ind_${m}`) }))} width={320} />
            <label className="switch"><input type="checkbox" checked={animate} onChange={(e) => { setAnimate(e.target.checked); setPlaying(e.target.checked); }} /><Play size={14} /> {tr('animate_years')}</label>
          </>}
          means={sorted.length >= 3 ? <>{tr('m_map', tr(`ind_${metric}`), sorted.slice(0, 3).map((r) => r.district).join(', '), sorted.slice(-3).reverse().map((r) => r.district).join(', '))} {tr('m_click')}</> : null}>
          {animate && years.length > 0 && (
            <div className="play-row">
              <button className="btn outline sm" onClick={() => { if (yi >= years.length - 1) setYi(0); setPlaying(!playing); }}>
                {playing ? <Pause size={14} /> : <Play size={14} />} {tr(playing ? 'pause' : 'play').replace(/^[^\p{L}]+/u, '')}
              </button>
              <input type="range" min={0} max={years.length - 1} value={Math.min(yi, years.length - 1)} onChange={(e) => { setPlaying(false); setYi(+e.target.value); }} aria-label={tr('year')} />
              <span className="play-year">{years[Math.min(yi, years.length - 1)]}</span>
            </div>
          )}
          <Plot fig={mapFig} height={430} onClick={pickDistrict} empty={tr('no_data')} />
        </ChartCard>
        <section className="card chart-card">
          <header className="card-head"><span className="ch-icon"><MapPin size={16} /></span><h3>{tr('c_profile')}</h3></header>
          <div className="card-body profile"><Profile metric={metric} vals={vals} unit={unit} dec={dec} /></div>
        </section>
      </Grid>
      <ChartCard title={tr('c_ranking')} icon={ArrowDownWideNarrow} means={tr('m_rank')}>
        <Plot fig={rankFig} height={470} onClick={pickDistrict} empty={tr('no_data')} />
      </ChartCard>
    </>
  );
}

function Profile({ metric, vals, unit, dec }: { metric: string; vals: { district: string; value: number; n: number | null; rel: string | null }[]; unit: string; dec: number }) {
  const { D, f, tr, pickDistrict } = useApp();
  if (!f.district && f.areaLevel !== 'national') {
    const d = vals.filter((r) => f.districts.includes(r.district)).sort((a, b) => b.value - a.value);
    return (
      <>
        <h4>{f.area}</h4><p className="muted">{tr('profile_multi', d.length)}</p>
        <table className="ptable"><thead><tr><th>{tr('district')}</th><th>{tr(`ind_${metric}`)}</th></tr></thead>
          <tbody>{d.map((r) => (
            <tr key={r.district}><td><button className="link-btn" onClick={() => pickDistrict(r.district)}>{r.district}</button></td>
              <td>{fmtNum(r.value, dec)}{unit} <RelBadge r={r.rel} /></td></tr>))}</tbody></table>
        <p className="muted small">{tr('profile_pick')}</p>
      </>
    );
  }
  if (!f.district) return <div className="profile-empty"><Hand size={30} /><p>{tr('profile_empty')}</p></div>;
  const dist = f.district;
  const inds = ['irrigated', 'irrig_modern', 'inorganic_fert', 'organic_fert', 'anti_erosion', 'mechanised'];
  const Y = new Set(f.years), S = new Set<string>(f.seasons);
  const pick = (lv: string, ar: string) => {
    const e = D.est.filter((r) => r.level === lv && r.area === ar && inds.includes(r.indicator) && Y.has(r.sas_year) && S.has(r.sas_season));
    return new Map([...groupBy(e, (r) => r.indicator).entries()].map(([k, g]) => [k, { v: wm(g.map((r) => r.estimate), g.map((r) => r.wsum)), n: sum(g.map((r) => r.n)), rel: mode(g.map((r) => r.reliability)) }]));
  };
  const dd = pick('district', dist), nn = pick('national', 'Rwanda');
  const rr = D.rain.district.find((r) => r.district_std === dist);
  const sc = D.screen.table.find((r) => r.district_std === dist);
  return (
    <>
      <h4>{dist}</h4>
      <p className="muted">{D.lookup.find((r) => r.district === dist)?.province} {'·'} {tr('profile_period', Math.min(...f.years), Math.max(...f.years), f.seasons.join('+'))}</p>
      <table className="ptable">
        <thead><tr><th /><th>{dist}</th><th>Rwanda</th><th>n</th></tr></thead>
        <tbody>{inds.filter((i) => dd.has(i)).map((i) => (
          <tr key={i}><td>{tr(`ind_${i}`)}</td><td>{fmtPct(dd.get(i)!.v)} <RelBadge r={dd.get(i)!.rel} /></td>
            <td className="muted">{fmtPct(nn.get(i)?.v)}</td><td className="muted">{fmtNum(dd.get(i)!.n)}</td></tr>))}</tbody>
      </table>
      {rr && <p><CloudRain size={14} /> {tr('profile_rain', fmtNum(rr.rain_normal_ab_mm), fmtNum(rr.rain_cv_pct, 0), rr.dry_seasons_2016_2025)}</p>}
      {sc && <p><Trophy size={14} /> {tr('profile_rank', sc.rank, sc.stability)}</p>}
    </>
  );
}

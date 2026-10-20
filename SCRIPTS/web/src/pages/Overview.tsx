import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  Droplet, Sprout, Users, Wheat, HandCoins, Waves, UserCheck, Sun, ChartLine, Database, Calendar, Map as MapIcon, CloudRain, House,
  MapPinned, Grid3x3, Wrench, Trophy, ClipboardCheck, IdCard, Compass, ChartColumn, Brain, Table,
} from 'lucide-react';
import type { Data } from 'plotly.js';
import { useApp } from '../data/store';
import { ChartCard, FiltersUsed, Grid, Insight, InsightGrid, Kpi, KpiRow, RelBadge, SectionTitle, Select } from '../components/ui';
import { AudioNote } from '../components/AudioNote';
import { Plot, choropleth, simpleLines, std, type Fig } from '../components/Plot';
import { ahsFor, ahsVal, byYear, cropsFor, estFor, groupBy, in100, last, mean, sum, totalsFor, yieldOf, type YearRow } from '../lib/stats';
import { fmtNum, fmtPct, seasonLabel } from '../lib/format';
import { brand, colIrrigated, colRainfed, seasonCols, seqBlue } from '../lib/theme';
import type { Season } from '../data/types';

const TREND_INDS = ['irrigated', 'irrig_modern', 'irrig_any_farmer', 'inorganic_fert', 'organic_fert', 'anti_erosion'];
const STAPLES = ['Maize', 'Bush bean', 'Climbing bean', 'Small red bean', 'Irish potato', 'Paddy rice', 'Cassava', 'Wheat', 'Cooking banana', 'Dessert banana', 'Banana for beer'];
const qKey = (q: string) => `q_${q.toLowerCase().replace(/[^a-z]/g, '')}`;

// The overview: a few headline numbers, each with the population and period beside it,
// then the district map beside the same numbers in order, the chosen district explained,
// and three small pictures (100 plots, how water arrives, one crop's yield). Every figure
// follows the year, season and area filters unless its source line says otherwise.
export default function Overview() {
  const { D, f, tr, geo, pickDistrict } = useApp();
  const [trendInd, setTrendInd] = useState('irrigated');
  const [crop, setCrop] = useState('Maize');
  const ab = (fb: Season[] = ['A', 'B']) => { const s = f.seasons.filter((x) => fb.includes(x)); return s.length ? s : fb; };
  const abTxt = ab().join('+');
  const yearly = (ind: string, seasons: Season[] = ['A', 'B']) =>
    byYear(estFor(D, f, ind, f.years, seasons.length === 1 && seasons[0] === 'C' ? ['C'] : ab(seasons)));
  const lst = (d: YearRow[]) => (d.length ? last(d).estimate : NaN);
  const dlt = (d: YearRow[]) => (d.length < 2 ? null : last(d).estimate - d[0].estimate);
  const since = (d: YearRow[]) => (d.length >= 2 ? tr('k_pts_since', d[0].sas_year) : '');
  const yrOf = (d: YearRow[]) => (d.length ? String(last(d).sas_year) : '–');

  // ---- headline numbers -----------------------------------------------------------------
  const tiles = useMemo(() => {
    const irr = yearly('irrigated'), anyf = yearly('irrig_any_farmer'), sc = yearly('irrigated', ['C']);
    // irrigated land: average per main season (A and B farm the same land)
    const tt = totalsFor(D, f).filter((r) => r.sas_season !== 'C');
    const land = [...groupBy(tt, (r) => String(r.sas_year)).values()].map((g) => ({
      y: g[0].sas_year, ha: g.some((r) => r.irrigated_area_ha == null) ? NaN : mean(g.map((r) => r.irrigated_area_ha)),
      cult: g.some((r) => r.cultivated_area_ha == null) ? NaN : mean(g.map((r) => r.cultivated_area_ha)),
    })).filter((r) => Number.isFinite(r.ha)).sort((a, b) => a.y - b.y);
    return { irr, anyf, sc, land: land.length ? last(land) : null };
  }, [D, f]); // eslint-disable-line
  const { irr, anyf, sc, land } = tiles;

  // ---- district map and the same numbers in order ------------------------------------------
  const dist = useMemo(() => {
    const Y = new Set(f.years), S = new Set<string>(ab());
    const e = D.est.filter((r) => r.level === 'district' && r.indicator === 'irrigated' && Y.has(r.sas_year) && S.has(r.sas_season));
    // seasons combined as weighted sums (estimate x weighted plots), not averaged percentages
    return [...groupBy(e, (r) => r.area).values()].map((g) => {
      const W = sum(g.map((r) => r.wsum));
      return { d: g[0].area, v: W > 0 ? sum(g.map((r) => r.estimate * r.wsum)) / W : NaN, n: sum(g.map((r) => r.n)),
        weak: g.every((r) => r.reliability === 'Unreliable') };
    }).filter((r) => Number.isFinite(r.v)).sort((a, b) => b.v - a.v);
  }, [D, f]); // eslint-disable-line
  const period = f.years.length ? `${Math.min(...f.years)}–${Math.max(...f.years)}` : '–';
  const sel = f.areaLevel !== 'national' ? f.districts : undefined;
  const distMap = useMemo<Fig | null>(() => !dist.length ? null : choropleth(geo, dist.map((r) => ({
    district: r.d, value: r.v, weak: r.weak, hover: `<b>${r.d}</b><br>${fmtPct(r.v)} ${tr('x_pct_plots')}<br>n = ${fmtNum(r.n)}`,
  })), { label: tr('x_pct_plots'), colorscale: seqBlue, zmin: 0, selected: sel, unit: '%', noData: tr('no_estimate') }), [geo, dist, sel, tr]);
  const distBar = useMemo<Fig | null>(() => {
    if (!dist.length) return null;
    const d = [...dist].reverse();
    const on = new Set(sel ?? []);
    return {
      data: [{ type: 'bar', orientation: 'h', y: d.map((r) => r.d), x: d.map((r) => r.v), customdata: d.map((r) => r.d),
        marker: { color: d.map((r) => (on.size && !on.has(r.d) ? '#BFD6EA' : r.weak ? '#9DBFDD' : brand.blue)) },
        text: d.map((r) => fmtPct(r.v, 1)), textposition: 'outside', cliponaxis: false, textfont: { size: 11, color: brand.ink },
        hovertext: d.map((r) => `<b>${r.d}</b> ${fmtPct(r.v)} · n = ${fmtNum(r.n)}`), hoverinfo: 'text' } as Data],
      layout: std({ legend: false, bargap: 0.25, margin: { l: 10, r: 40, t: 4, b: 10 }, xaxis: { visible: false, range: [0, Math.max(...d.map((r) => r.v)) * 1.22] },
        yaxis: { title: { text: '' }, tickfont: { size: 11 }, categoryorder: 'array', categoryarray: d.map((r) => r.d) } }),
    };
  }, [dist, sel]);

  // ---- the chosen district, explained ------------------------------------------------------
  const one = f.district;
  const card = useMemo(() => {
    if (!one) return null;
    const v = dist.find((r) => r.d === one);
    const Y = new Set(f.years), S = new Set<string>(ab());
    const nat = D.est.filter((r) => r.level === 'national' && r.indicator === 'irrigated' && Y.has(r.sas_year) && S.has(r.sas_season));
    const W = sum(nat.map((r) => r.wsum));
    return { v, nat: W ? sum(nat.map((r) => r.estimate * r.wsum)) / W : NaN, need: D.rain.district.find((r) => r.district_std === one),
      sc: D.screen.table.find((r) => r.district_std === one), prov: D.lookup.find((r) => r.district === one)?.province ?? '' };
  }, [one, dist, D, f]); // eslint-disable-line

  // ---- three small pictures -----------------------------------------------------------------
  const share = lst(irr);
  const methods = useMemo(() => {
    const Y = new Set(f.years), S = new Set<string>(f.seasons);
    const d = D.tech.mix.filter((r) => r.period == null && r.dimension === 'irrig_tool_level' && Y.has(r.sas_year) && S.has(r.sas_season));
    const W = sum(d.map((r) => r.w));
    return [...groupBy(d, (r) => r.category).values()].map((g) => ({ c: g[0].category.replace(/^\d+\s*/, ''), s: W ? (100 * sum(g.map((r) => r.w))) / W : NaN, n: sum(g.map((r) => r.n)) }))
      .filter((r) => Number.isFinite(r.s)).sort((a, b) => b.s - a.s);
  }, [D, f]);
  const methodFig = useMemo<Fig | null>(() => !methods.length ? null : {
    data: [{ type: 'bar', orientation: 'h', y: [...methods].reverse().map((r) => r.c), x: [...methods].reverse().map((r) => r.s),
      marker: { color: [...methods].reverse().map((_, i, a) => (i === a.length - 1 ? brand.blue : '#8FB5D8')) },
      text: [...methods].reverse().map((r) => fmtPct(r.s, 0)), textposition: 'outside', cliponaxis: false, textfont: { size: 12, color: brand.ink },
      hovertext: [...methods].reverse().map((r) => `${r.c}: ${fmtPct(r.s)} · n = ${fmtNum(r.n)}`), hoverinfo: 'text' } as Data],
    layout: std({ legend: false, bargap: 0.35, margin: { l: 10, r: 40, t: 4, b: 10 }, xaxis: { visible: false, range: [0, 118] }, yaxis: { title: { text: '' } } }),
  }, [methods]);

  const cropY = useMemo(() => {
    // the latest usable season of the selection, for the chosen crop (one season: no averaging)
    const rows = cropsFor(D, { ...f, crops: [crop], cropGroups: [], seasons: ab() });
    const bySeason = [...groupBy(rows, (r) => `${r.sas_year}${r.sas_season}`).values()]
      .map((g) => ({ k: `${g[0].sas_year}${g[0].sas_season}`, y: yieldOf(D, g) }))
      .filter((x) => x.y.excluded === 0 && Number.isFinite(x.y.irr) && Number.isFinite(x.y.rf) && x.y.nIrr >= 10)
      .sort((a, b) => a.k.localeCompare(b.k));
    return bySeason.length ? last(bySeason) : null;
  }, [D, f, crop]); // eslint-disable-line
  const cropFig = useMemo<Fig | null>(() => !cropY ? null : {
    data: [{ type: 'bar', x: [tr('rainfed'), tr('irrigated')], y: [cropY.y.rf, cropY.y.irr], marker: { color: [colRainfed, colIrrigated] },
      text: [cropY.y.rf, cropY.y.irr].map((v) => `${fmtNum(v)} kg/ha`), textposition: 'outside', cliponaxis: false, textfont: { size: 13, color: brand.ink }, hoverinfo: 'skip' } as Data],
    layout: std({ legend: false, bargap: 0.45, margin: { l: 10, r: 10, t: 24, b: 10 }, yaxis: { visible: false, rangemode: 'tozero', range: [0, Math.max(cropY.y.rf, cropY.y.irr) * 1.25] } }),
  }, [cropY, tr]);

  // ---- trend --------------------------------------------------------------------------------
  const trendE = useMemo(() => estFor(D, f, trendInd), [D, f, trendInd]);
  const trendFig = useMemo<Fig | null>(() => {
    if (!trendE.length) return null;
    const data: Data[] = [];
    for (const s of ['A', 'B', 'C'] as Season[]) {
      const sv = trendE.filter((r) => r.sas_season === s).sort((a, b) => a.sas_year - b.sas_year);
      if (sv.length) data.push({
        x: sv.map((r) => r.sas_year), y: sv.map((r) => r.estimate), type: 'scatter', mode: 'lines+markers', name: tr(`season_${s.toLowerCase()}`),
        line: { color: seasonCols[s] }, marker: { color: seasonCols[s] },
        text: sv.map((r) => `${r.sas_year}${s}: <b>${fmtPct(r.estimate)}</b> (95% CI ${fmtPct(r.ci_low)}–${fmtPct(r.ci_high)}) · n = ${fmtNum(r.n)}`), hoverinfo: 'text',
      });
    }
    return simpleLines(data, std({ y: tr(`ind_${trendInd}`), xaxis: { dtick: 1 }, yaxis: { ticksuffix: '%' } }));
  }, [trendE, trendInd, tr]);
  const trendMeans = useMemo(() => {
    const e = trendE.filter((r) => r.sas_season !== 'C').sort((a, b) => a.sas_year - b.sas_year || a.sas_season.localeCompare(b.sas_season));
    if (e.length < 2) return null;
    const a = e[0], b = last(e);
    const sig = (b.ci_low ?? 0) > (a.ci_high ?? Infinity) || (b.ci_high ?? Infinity) < (a.ci_low ?? 0);
    return tr(!sig ? 'm_trend_stable' : b.estimate > a.estimate ? 'm_trend_up' : 'm_trend_down', f.area,
      seasonLabel(a.sas_year, a.sas_season), fmtPct(a.estimate), seasonLabel(b.sas_year, b.sas_season), fmtPct(b.estimate));
  }, [trendE, f.area, tr]);

  // ---- findings -----------------------------------------------------------------------------
  const findings = useMemo(() => {
    if (irr.length < 1) return null;
    const eq = D.equity.equity.filter((r) => r.dimension === 'gender');
    const cs = D.equity.equity.filter((r) => r.dimension === 'consolidated');
    const ya = D.model_yield.table.filter((r) => r.adjusted_low > 0).sort((x, y) => y.adjusted_pct - x.adjusted_pct);
    const hv = (ind: string, y: number) => ahsVal(ahsFor(D, f), ind, y);
    const pc = [...groupBy(cropsFor(D, { ...f, seasons: ab(), crops: [], cropGroups: [] }).filter((r) => STAPLES.includes(r.crop_name)), (r) => String(r.sas_year)).values()]
      .map((g) => ({ y: g[0].sas_year, t: sum(g.map((r) => r.production_t)) / 1000 })).sort((x, y) => x.y - y.y);
    const ch = pc.length >= 2 ? 100 * (last(pc).t / pc[0].t - 1) : NaN;
    return { eq, cs, ya, hv, pc, ch };
  }, [D, f, irr]); // eslint-disable-line

  const top5 = [...D.screen.table].sort((a, b) => a.rank - b.rank).slice(0, 5);
  const pct = (v: number) => (Number.isFinite(v) ? Math.max(0, Math.min(100, Math.round(v))) : 0);

  return (
    <>
      <div className="hero">
        <div className="hero-text">
          <h1>SmartIrrigate Rwanda</h1>
          <p>{tr('tagline')}</p>
          <div className="hero-meta">
            <span><Database size={14} /> {tr('hero_m1')}</span><span><Calendar size={14} /> {tr('hero_m2')}</span>
            <span><MapIcon size={14} /> {tr('hero_m3')}</span><span><CloudRain size={14} /> {tr('hero_m4')}</span>
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

      <AudioNote id="overview" />
      <FiltersUsed used={['years', 'seasons', 'area']} />
      <KpiRow>
        <Kpi label={tr('k_irrigated')} value={fmtPct(share)} icon={Droplet} color={brand.blue} delta={dlt(irr)}
          foot={<>{tr('k_who_plots', f.area, `${abTxt} ${yrOf(irr)}`)}<RelBadge r={irr.length ? last(irr).rel : null} /></>}
          hint={[irr.length ? last(irr).seasons : '', since(irr), tr('layer_est')].filter(Boolean).join(' · ')} />
        <Kpi label={tr('ind_irrig_any_farmer')} value={fmtPct(lst(anyf))} icon={UserCheck} color={brand.green} delta={dlt(anyf)}
          foot={<>{tr('k_who_farmers', f.area, `${abTxt} ${yrOf(anyf)}`)}<RelBadge r={anyf.length ? last(anyf).rel : null} /></>}
          hint={`${tr('k_any_sub')} · ${tr('layer_est')}`} />
        <Kpi label={tr('k_area')} value={land ? `${fmtNum(land.ha)} ha` : '–'} icon={Waves} color="#00897B"
          foot={land ? tr('k_who_land', `${f.area} ${land.y}`) : tr('no_estimate')}
          hint={land ? tr('k_area_sub2', fmtPct((100 * land.ha) / land.cult)) : undefined} />
        <Kpi label={tr('k_season_c')} value={fmtPct(lst(sc))} icon={Sun} color={brand.terracotta} delta={dlt(sc)}
          foot={<>{tr('k_who_plots', f.area, `C ${yrOf(sc)}`)}<RelBadge r={sc.length ? last(sc).rel : null} /></>} hint={tr('k_season_c_sub')} />
      </KpiRow>

      <Grid cols="7fr 5fr">
        <ChartCard title={tr('ov_map_title')} icon={MapPinned}
          means={dist.length >= 2 ? tr('ov_m_map', dist[0].d, fmtPct(dist[0].v), last(dist).d, fmtPct(last(dist).v)) : null}
          source={tr('src_plots', abTxt, period, tr('n_districts', dist.length))}
          table={{ cols: [tr('district'), tr('x_pct_plots'), 'n'], rows: dist.map((r) => [r.d, fmtPct(r.v), r.n]) }}>
          <div className="map-bars">
            <Plot fig={distMap} height={360} onClick={pickDistrict} empty={tr('no_data')} />
            <div className="map-bars-list" aria-hidden="true"><Plot fig={distBar} height={Math.max(360, 15 * dist.length + 20)} onClick={pickDistrict} /></div>
          </div>
        </ChartCard>
        <section className="card chart-card" aria-live="polite">
          <header className="card-head"><span className="ch-icon"><IdCard size={15} /></span><h3>{one || tr('ov_district_title')}</h3></header>
          <div className="card-body district-card">
            {!card ? (
              <>
                <p className="muted">{tr('ov_pick')}</p>
                <label className="select"><span className="select-label">{tr('district')}</span>
                  <span className="select-box"><select value="" onChange={(e) => e.target.value && pickDistrict(e.target.value)}>
                    <option value="">–</option>{[...D.lookup.map((r) => r.district)].sort().map((d) => <option key={d} value={d}>{d}</option>)}
                  </select></span>
                </label>
              </>
            ) : (
              <>
                <p className="muted small">{card.prov}{card.need ? ` · ${tr(qKey(card.need.quadrant))}` : ''}</p>
                <div className="dc-big"><span className="dc-num">{fmtPct(card.v?.v)}</span><span>{tr('x_pct_plots')} · {abTxt} {period}</span></div>
                <div className="dc-compare" role="img" aria-label={`${one} ${fmtPct(card.v?.v)}, Rwanda ${fmtPct(card.nat)}`}>
                  {[{ k: one, v: card.v?.v ?? NaN, c: brand.blue }, { k: 'Rwanda', v: card.nat, c: brand.grey }].map((x) => (
                    <div key={x.k} className="dc-row"><span>{x.k}</span><span className="dc-track"><i style={{ width: `${Math.min(100, (100 * (x.v || 0)) / Math.max(card.v?.v ?? 0, card.nat, 1))}%`, background: x.c }} /></span><b>{fmtPct(x.v)}</b></div>
                  ))}
                </div>
                <ul className="dc-facts">
                  {card.need && <li><CloudRain size={14} /> {tr('need_score')}: <b>{fmtNum(card.need.need_score, 0)}/100</b></li>}
                  {card.sc && <li><Trophy size={14} /> {tr('profile_rank', card.sc.rank, card.sc.stability)}</li>}
                  {card.v?.weak && <li><RelBadge r="Unreliable" /></li>}
                </ul>
                <Link className="btn outline sm" to="/district">{tr('ov_open_profile')}</Link>
              </>
            )}
          </div>
        </section>
      </Grid>

      <Grid cols="1fr 1fr 1fr">
        <ChartCard title={tr('ov_pict_title')} icon={Grid3x3} means={Number.isFinite(share) ? tr('ov_m_pict', share < 1 ? tr('lt1in100') : String(pct(share)), `${f.area}, ${abTxt} ${yrOf(irr)}`) : null}
          source={tr('ov_pict_legend')} table={Number.isFinite(share) ? { cols: ['', '%'], rows: [[tr('irrigated'), fmtPct(share)], [tr('rainfed'), fmtPct(100 - share)]] } : null}>
          {Number.isFinite(share) ? <Pictogram filled={pct(share)} label={`${pct(share)} / 100`} /> : <p className="plot-empty">{tr('no_data')}</p>}
        </ChartCard>
        <ChartCard title={tr('ov_method_title')} icon={Wrench}
          means={methods.length ? tr('ov_m_method', methods[0].c, fmtPct(methods[0].s, 0)) : null}
          source={tr('src_plots', f.seasons.join('+'), period, 'Rwanda')}
          table={{ cols: [tr('ov_method_title'), '%', 'n'], rows: methods.map((r) => [r.c, fmtPct(r.s), r.n]) }}>
          <Plot fig={methodFig} height={220} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('ov_crop_title')} icon={Wheat}
          tools={<Select value={crop} onChange={setCrop} options={D.yield.crops.map((c) => ({ value: c, label: c }))} width="100%" />}
          means={cropY ? tr('ov_m_crop', crop, `${f.area} ${cropY.k}`, fmtNum(cropY.y.irr), fmtNum(cropY.y.rf)) : tr('ov_crop_few', crop)}
          source={tr('src_yield')}
          table={cropY ? { cols: ['', 'kg/ha'], rows: [[tr('irrigated'), Math.round(cropY.y.irr)], [tr('rainfed'), Math.round(cropY.y.rf)]] } : null}>
          <Plot fig={cropFig} height={220} empty={tr('no_data')} />
        </ChartCard>
      </Grid>

      <Grid cols="7fr 5fr">
        <ChartCard title={tr('c_trend')} icon={ChartLine} means={trendMeans}
          tools={<Select value={trendInd} onChange={setTrendInd} options={TREND_INDS.map((i) => ({ value: i, label: tr(`ind_${i}`) }))} width="100%" />}
          source={tr(trendInd === 'irrig_any_farmer' ? 'src_farmers' : 'src_plots', f.seasons.join('+'), period, f.area)}
          table={{ cols: [tr('season'), '%', '95%', 'n'], rows: [...trendE].sort((a, b) => a.sas_year - b.sas_year || a.sas_season.localeCompare(b.sas_season)).map((r) => [`${r.sas_year}${r.sas_season}`, fmtPct(r.estimate), `${fmtPct(r.ci_low)}–${fmtPct(r.ci_high)}`, r.n]) }}>
          <Plot fig={trendFig} height={300} empty={tr('no_data')} />
        </ChartCard>
        <section className="card chart-card">
          <header className="card-head"><span className="ch-icon"><ClipboardCheck size={15} /></span><h3>{tr('ov_short_title')}</h3></header>
          <div className="card-body">
            <ol className="shortlist">
              {top5.map((r) => (
                <li key={r.district_std}>
                  <button type="button" className="link-btn" onClick={() => pickDistrict(r.district_std)}>{r.district_std}</button>
                  <span className="muted small">{r.reasons.split(',').map((x) => tr(`w_${x}`)).join(' + ')}</span>
                </li>
              ))}
            </ol>
            <p className="muted small">{tr('ov_short_note')}</p>
            <div className="btn-row">
              <Link className="btn outline sm" to="/priority"><Trophy size={14} /> {tr('act_action')}</Link>
              <Link className="btn outline sm" to="/priority#feasibility"><ClipboardCheck size={14} /> {tr('ov_feas')}</Link>
            </div>
          </div>
        </section>
      </Grid>

      <SectionTitle title={tr('s_findings')} />
      {findings && (
        <InsightGrid>
          <Insight icon={Droplet} color={brand.blue} title={tr('f1_t', in100(share, tr))}
            text={tr('f1', f.area, fmtPct(share), irr.length ? irr[0].sas_year : '–', irr.length ? fmtPct(irr[0].estimate) : '–')} />
          <Insight icon={Sprout} color={brand.green} title={tr('f2_t', findings.ya.length)} text={tr('f2', findings.ya.slice(0, 4).map((r) => r.crop_name).join(', '))} />
          <Insight icon={Users} color="#B07A1C" title={tr('f3_t')}
            text={tr('f3', fmtPct(findings.eq.find((r) => r.group === 'Female')?.estimate), fmtPct(findings.eq.find((r) => r.group === 'Male')?.estimate),
              fmtPct(findings.cs.find((r) => r.group === 'In consolidated site')?.estimate))} />
          {findings.pc.length >= 2 && (
            <Insight icon={Wheat} color="#00897B" title={tr('f5_t', `${findings.ch >= 0 ? '+' : ''}${fmtNum(findings.ch)}%`, findings.pc[0].y)}
              text={tr('f5', fmtNum(findings.pc[0].t), findings.pc[0].y, fmtNum(last(findings.pc).t), last(findings.pc).y)} />
          )}
          <Insight icon={HandCoins} color="#6A4C93" title={tr('f6_t')}
            text={tr('f6', in100(findings.hv('improved_seed', 2024), tr), in100(findings.hv('crop_insurance', 2024), tr))} />
        </InsightGrid>
      )}

      <SectionTitle title={tr('ov_more')} />
      <nav className="more-links" aria-label={tr('ov_more')}>
        {[['/map', MapPinned, 'p_map'], ['/need', CloudRain, 'p_need'], ['/evidence', Sprout, 'p_evidence'], ['/how', Waves, 'p_how'],
          ['/who', Users, 'p_who'], ['/households', House, 'p_households'], ['/explorer', Table, 'p_explorer'], ['/model', Brain, 'p_model'],
          ['/priority', Compass, 'p_priority'], ['/methods', ChartColumn, 'p_methods']].map(([to, I, k]) => {
          const Icon = I as typeof MapPinned;
          return <Link key={to as string} to={to as string} className="more-link"><Icon size={16} /> {tr(k as string)}</Link>;
        })}
      </nav>
    </>
  );
}

/** 100 squares, one per plot in every 100; the filled ones are irrigated */
function Pictogram({ filled, label }: { filled: number; label: string }) {
  const cells = Array.from({ length: 100 }, (_, i) => i);
  return (
    <svg viewBox="0 0 210 210" className="pictogram" role="img" aria-label={label}>
      {cells.map((i) => {
        const x = (i % 10) * 21, y = Math.floor(i / 10) * 21;
        return <rect key={i} x={x} y={y} width={18} height={18} rx={3} fill={i < filled ? brand.blue : '#E1E7E3'} />;
      })}
    </svg>
  );
}

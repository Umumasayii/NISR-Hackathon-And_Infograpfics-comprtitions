import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  Droplet, Sprout, Users, Wheat, HandCoins, Waves, UserCheck, Sun, ChartLine, Database, Map as MapIcon, CloudRain, House,
  MapPinned, Wrench, Trophy, ClipboardCheck, IdCard, Compass, ChartColumn, Brain, Table, FlaskConical, LandPlot, ChevronRight, ExternalLink,
} from 'lucide-react';
import type { Data } from 'plotly.js';
import { useApp } from '../data/store';
import { ChartCard, FiltersUsed, Grid, Insight, InsightGrid, Kpi, KpiRow, RelBadge, SectionTitle, Select } from '../components/ui';
import { AudioNote } from '../components/AudioNote';
import { Plot, choropleth, simpleLines, std, type Fig } from '../components/Plot';
import { ahsFor, ahsVal, cropsFor, estFor, groupBy, in100, last, yieldOf } from '../lib/stats';
import { citeShort, cite, fmtPub, pubArea, splitAtUpgrade, FIRST_UPGRADED, pubSource, seasonsOf, yearBefore, ysKey, type YS } from '../lib/official';
import { fmtNum, fmtPct } from '../lib/format';
import { brand, colIrrigated, colRainfed, seasonCols, seqBlue } from '../lib/theme';
import type { PubRow, Season } from '../data/types';

// NISR figures first: the trend can show these, or two of our own estimates (labelled)
const TREND_PUB = ['irrig_any_farmer', 'inorganic_fert_farmer', 'organic_fert_farmer', 'pesticide_farmer', 'inorganic_fert', 'cultivated_land_ha'];
const TREND_OURS = ['irrigated', 'irrig_modern'];
const IRR_TYPES = ['traditional', 'surface', 'flood', 'drip', 'sprinkler', 'pivot'];
const qKey = (q: string) => `q_${q.toLowerCase().replace(/[^a-z]/g, '')}`;

// The overview. The headline numbers, the district map and list, the 100-farmer picture
// and the irrigation types are published NISR figures for one season (picked below the
// filters; NISR publishes no figure for several seasons together). Where NISR does not
// publish a breakdown (several districts, a province) the card says so. Our own
// estimates appear only where NISR publishes nothing comparable, and are labelled.
export default function Overview() {
  const { D, O, f, tr, geo, pickDistrict } = useApp();
  const [trendInd, setTrendInd] = useState('pub:irrig_any_farmer');
  const [crop, setCrop] = useState('Maize');
  const area = pubArea(f);

  // ---- the season the published figures are for -----------------------------------------
  const ssAll = useMemo(() => seasonsOf(f), [f]);
  const ssMain = ssAll.filter((x) => x.s !== 'C');
  const [seasonKey, setSeasonKey] = useState('');
  const def = (ssMain.length ? last(ssMain) : last(ssAll)) as YS | undefined;
  const ps: YS | undefined = ssAll.find((x) => ysKey(x) === seasonKey) ?? def;
  useEffect(() => { if (seasonKey && !ssAll.some((x) => ysKey(x) === seasonKey)) setSeasonKey(''); }, [ssAll, seasonKey]);
  const psTxt = ps ? tr('season_of', ps.s, ps.y) : '–';
  const get = (ind: string, a = area, crop?: string) => (O && ps && a ? O.get(ind, ps.y, ps.s, a, crop) : undefined);
  const val = (r?: PubRow) => (r && r.value != null ? r.value : NaN);

  // ---- headline numbers (NISR) -------------------------------------------------------------
  const kp = useMemo(() => {
    const irr = get('irrig_any_farmer'), fert = get('inorganic_fert_farmer'), land = get('cultivated_land_ha'), irrLand = get('irrigated_area_ha');
    // the dry season of the same year (or the newest selected year that has one)
    const cYears = [...f.years].sort((a, b) => b - a);
    const sc = O && area ? cYears.map((y) => O.get('irrig_any_farmer', y, 'C', area)).find((r) => r && r.value != null) : undefined;
    // our combined estimate for a selection NISR does not publish (labelled as ours)
    const ours = !area && ps ? estFor(D, f, 'irrig_any_farmer', [ps.y], [ps.s])[0] : undefined;
    // share of cultivated land that is irrigated: two published NISR totals for the same season
    const landPct = irrLand?.value != null && land?.value ? (100 * irrLand.value) / land.value : NaN;
    return { irr, fert, land, irrLand, landPct, sc, ours };
  }, [O, D, f, area, ps]); // eslint-disable-line
  const prevTxt = ps ? tr('delta_vs', tr('season_of', ps.s, ps.y - 1)) : undefined;
  const chg = (r?: PubRow) => { if (!O || !r || r.value == null) return null; const b = yearBefore(O, r); return b && b.value != null ? r.value - b.value : null; };
  const pubFoot = (r: PubRow | undefined, who: string, when = psTxt) => (r && O
    ? <>{tr('k_who_pub', who, area ?? '', when)} <span className="pub-tag" title={cite(O, r)}>{citeShort(O, r)}</span></>
    : <span className="muted">{tr('pub_unavailable')}</span>);
  const pubHint = (r?: PubRow, extra?: string) => (r && O ? [cite(O, r), tr('delta_same_season'), extra].filter(Boolean).join(' ') : tr('pub_unavailable_hint'));

  // ---- district map and the same numbers in order (NISR, one season) ---------------------------
  const dist = useMemo(() => {
    if (!O || !ps) return [];
    return D.lookup.map((l) => ({ d: l.district, r: O.get('irrig_any_farmer', ps.y, ps.s, l.district) }))
      .filter((x) => x.r && x.r.value != null).map((x) => ({ d: x.d, v: x.r!.value as number, r: x.r! }))
      .sort((a, b) => b.v - a.v);
  }, [O, D, ps]);
  const nat = get('irrig_any_farmer', 'Rwanda');
  const sel = f.areaLevel !== 'national' ? f.districts : undefined;
  const distMap = useMemo<Fig | null>(() => !dist.length || !O ? null : choropleth(geo, dist.map((x) => ({
    district: x.d, value: x.v, hover: `<b>${x.d}</b><br>${fmtPct(x.v)} ${tr('of_farmers')}<br>${citeShort(O, x.r)}, ${tr('cell')} ${x.r.cell}`,
  })), { label: tr('x_pct_farmers'), colorscale: seqBlue, zmin: 0, selected: sel, unit: '%', noData: tr('pub_unavailable') }), [geo, dist, sel, tr, O]);
  const distBar = useMemo<Fig | null>(() => {
    if (!dist.length) return null;
    const d = [...dist].reverse();
    const on = new Set(sel ?? []);
    // the selected districts are marked in the label as well as in colour
    const lab = (x: string) => (on.size && on.has(x) ? `▶ ${x}` : x);
    return {
      data: [{ type: 'bar', orientation: 'h', y: d.map((r) => lab(r.d)), x: d.map((r) => r.v), customdata: d.map((r) => r.d),
        marker: { color: d.map((r) => (on.size && !on.has(r.d) ? '#BFD6EA' : brand.blue)) },
        text: d.map((r) => fmtPct(r.v, 1)), textposition: 'outside', cliponaxis: false, textfont: { size: 11, color: brand.ink },
        hovertext: d.map((r) => `<b>${r.d}</b> ${fmtPct(r.v)}`), hoverinfo: 'text' } as Data],
      layout: std({ legend: false, bargap: 0.25, margin: { l: 10, r: 40, t: 4, b: 10 }, xaxis: { visible: false, range: [0, Math.max(...d.map((r) => r.v)) * 1.22] },
        yaxis: { title: { text: '' }, tickfont: { size: 11 }, categoryorder: 'array', categoryarray: d.map((r) => lab(r.d)) } }),
    };
  }, [dist, sel]);

  // ---- the chosen district, explained ------------------------------------------------------
  const one = f.district;
  const card = useMemo(() => {
    if (!one) return null;
    const r = dist.find((x) => x.d === one);
    const ours = ps ? D.est.find((e) => e.level === 'district' && e.area === one && e.indicator === 'irrigated' && e.sas_year === ps.y && e.sas_season === ps.s) : undefined;
    return { r, ours, need: D.rain.district.find((x) => x.district_std === one),
      sc: D.screen.table.find((x) => x.district_std === one), prov: D.lookup.find((x) => x.district === one)?.province ?? '' };
  }, [one, dist, D, ps]);

  // ---- 100 farmers, irrigation types (NISR) ----------------------------------------------------
  const share = val(kp.irr);
  const types = useMemo(() => IRR_TYPES.map((t) => ({ t, r: get(`irrig_type_${t}`) })).filter((x) => x.r && x.r.value != null)
    .map((x) => ({ t: x.t, v: x.r!.value as number, r: x.r! })).sort((a, b) => b.v - a.v), [O, ps, area]); // eslint-disable-line
  const typeFig = useMemo<Fig | null>(() => {
    if (!types.length) return null;
    const d = [...types].reverse();
    return {
      data: [{ type: 'bar', orientation: 'h', y: d.map((x) => tr(`irr_type_${x.t}`)), x: d.map((x) => x.v),
        marker: { color: d.map((_, i, a) => (i === a.length - 1 ? brand.blue : '#8FB5D8')) },
        text: d.map((x) => fmtPct(x.v, 1)), textposition: 'outside', cliponaxis: false, textfont: { size: 12, color: brand.ink },
        hovertext: d.map((x) => `${tr(`irr_type_${x.t}`)}: ${fmtPct(x.v)}`), hoverinfo: 'text' } as Data],
      layout: std({ legend: false, bargap: 0.35, margin: { l: 10, r: 44, t: 4, b: 10 }, xaxis: { visible: false, range: [0, Math.max(...d.map((x) => x.v)) * 1.25] }, yaxis: { title: { text: '' } } }),
    };
  }, [types, tr]);

  // ---- our analysis: one crop's yield, irrigated vs rain-fed --------------------------------------
  const cropY = useMemo(() => {
    const ab = f.seasons.filter((s) => s !== 'C');
    const rows = cropsFor(D, { ...f, crops: [crop], cropGroups: [], seasons: ab.length ? ab : ['A', 'B'] });
    const bySeason = [...groupBy(rows, (r) => `${r.sas_year}${r.sas_season}`).values()]
      .map((g) => ({ k: `${g[0].sas_year}${g[0].sas_season}`, y: yieldOf(D, g) }))
      .filter((x) => x.y.excluded === 0 && Number.isFinite(x.y.irr) && Number.isFinite(x.y.rf) && x.y.nIrr >= 10)
      .sort((a, b) => a.k.localeCompare(b.k));
    // the season shown above when it has enough irrigated plots, else the newest that does
    return bySeason.find((x) => ps && x.k === ysKey(ps)) ?? (bySeason.length ? last(bySeason) : null);
  }, [D, f, crop, ps]);
  // the same crop compared with similar rain-fed farms (survey-weighted model, all seasons)
  const cropAdj = D.model_yield.table.find((r) => r.crop_name === crop);
  const signedPct = (v: number) => `${v >= 0 ? '+' : ''}${fmtPct(v, 0)}`;
  const cropFig = useMemo<Fig | null>(() => !cropY ? null : {
    data: [{ type: 'bar', x: [tr('rainfed'), tr('irrigated')], y: [cropY.y.rf, cropY.y.irr], marker: { color: [colRainfed, colIrrigated] },
      text: [cropY.y.rf, cropY.y.irr].map((v) => `${fmtNum(v)} kg/ha`), textposition: 'outside', cliponaxis: false, textfont: { size: 13, color: brand.ink }, hoverinfo: 'skip' } as Data],
    layout: std({ legend: false, bargap: 0.45, margin: { l: 10, r: 10, t: 24, b: 10 }, yaxis: { visible: false, rangemode: 'tozero', range: [0, Math.max(cropY.y.rf, cropY.y.irr) * 1.25] } }),
  }, [cropY, tr]);

  // ---- trend: one line per season, a season compared only with the same season ------------------------
  const isPub = trendInd.startsWith('pub:');
  const tInd = trendInd.replace(/^pub:/, '');
  const trend = useMemo(() => {
    if (isPub) {
      if (!O || !area) return [];
      // 2019 used the older survey method and is not comparable, so the series starts in 2020
      return seasonsOf(f).filter((x) => x.y >= FIRST_UPGRADED).map((x) => O.get(tInd, x.y, x.s, area)).filter((r): r is PubRow => !!r && r.value != null)
        .map((r) => ({ y: r.sas_year, s: r.sas_season, v: r.value as number, lo: NaN, hi: NaN, n: NaN, src: O ? `${citeShort(O, r)}, ${tr('cell')} ${r.cell}` : '' }));
    }
    return estFor(D, f, tInd).map((r) => ({ y: r.sas_year, s: r.sas_season, v: r.estimate, lo: r.ci_low ?? NaN, hi: r.ci_high ?? NaN, n: r.n, src: '' }));
  }, [O, D, f, area, isPub, tInd, tr]);
  const unitPct = !isPub || O?.def.get(tInd)?.unit === '%';
  const trendFig = useMemo<Fig | null>(() => {
    if (!trend.length) return null;
    const data: Data[] = [];
    for (const s of ['A', 'B', 'C'] as Season[]) {
      const sv = trend.filter((r) => r.s === s).sort((a, b) => a.y - b.y);
      const xy = isPub ? splitAtUpgrade(sv.map((r) => r.y), sv.map((r) => r.v)) : { x: sv.map((r) => r.y), y: sv.map((r) => r.v) };
      const tx = isPub ? splitAtUpgrade(sv.map((r) => r.y), sv) .y : sv;
      if (sv.length) data.push({
        x: xy.x, y: xy.y, connectgaps: false, type: 'scatter', mode: 'lines+markers', name: tr(`season_${s.toLowerCase()}`),
        line: { color: seasonCols[s], dash: s === 'C' ? 'dot' : 'solid' }, marker: { color: seasonCols[s], symbol: s === 'A' ? 'circle' : s === 'B' ? 'square' : 'diamond', size: 8 },
        text: tx.map((r) => !r ? '' : `${r.y}${s}: <b>${unitPct ? fmtPct(r.v) : fmtNum(r.v)}</b>${isPub ? `<br>${r.src}` : ` (95% CI ${fmtPct(r.lo)}–${fmtPct(r.hi)}) · n = ${fmtNum(r.n)}`}`), hoverinfo: 'text',
      });
    }
    return simpleLines(data, std({ y: isPub ? tr(`pub_ind_${tInd}`) : tr(`ind_${tInd}`), xaxis: { dtick: 1 }, yaxis: unitPct ? { ticksuffix: '%', rangemode: 'tozero' } : { rangemode: 'tozero' } }));
  }, [trend, isPub, tInd, unitPct, tr]);
  const trendMeans = useMemo(() => {
    // first and last value of the same season; no claim beyond the two published numbers
    const s = ps?.s ?? 'A';
    // a published series is compared from 2020 on (NISR upgraded the survey in 2020)
    const e = trend.filter((r) => r.s === s && (!isPub || r.y >= FIRST_UPGRADED)).sort((a, b) => a.y - b.y);
    if (e.length < 2) return null;
    const a = e[0], b = last(e), fm = (v: number) => (unitPct ? fmtPct(v) : fmtNum(v));
    if (isPub) return tr('m_pub_trend', area ?? '', tr('season_of', s, a.y), fm(a.v), tr('season_of', s, b.y), fm(b.v));
    const sig = b.lo > a.hi || b.hi < a.lo;
    return tr(!sig ? 'm_trend_stable' : b.v > a.v ? 'm_trend_up' : 'm_trend_down', f.area, `${a.y}${s}`, fm(a.v), `${b.y}${s}`, fm(b.v));
  }, [trend, ps, isPub, area, f.area, unitPct, tr]);

  // ---- our analysis ---------------------------------------------------------------------------
  const ours = useMemo(() => ({
    eq: D.equity.equity.filter((r) => r.dimension === 'gender'),
    cs: D.equity.equity.filter((r) => r.dimension === 'consolidated'),
    ya: D.model_yield.table.filter((r) => r.adjusted_low > 0).sort((x, y) => y.adjusted_pct - x.adjusted_pct),
    hv: (ind: string, y: number) => ahsVal(ahsFor(D, f), ind, y),
  }), [D, f]);

  const top5 = [...D.screen.table].sort((a, b) => a.rank - b.rank).slice(0, 5);
  // the story's payoff step: maize (the main staple) when its adjusted gain is clear, else the clearest crop
  const pay = ours.ya.find((r) => r.crop_name === 'Maize') ?? ours.ya[0];
  // the problem is always stated for the whole country, whatever the area filter says
  const natLand = get('cultivated_land_ha', 'Rwanda'), natIrrLand = get('irrigated_area_ha', 'Rwanda');
  const natLandPct = natIrrLand?.value != null && natLand?.value ? (100 * natIrrLand.value) / natLand.value : NaN;
  const natNot = Number.isFinite(val(nat)) ? Math.round(100 - val(nat)) : NaN;
  // districts where rain is least reliable and irrigation is still rare (our analysis)
  const gapDist = D.rain.district.filter((r) => r.quadrant === 'High need, low adoption').sort((a, b) => b.need_score - a.need_score).map((r) => r.district_std);
  const jump = (id: string) => document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });

  return (
    <>
      <div className="hero hero-problem">
        <div className="hero-text">
          <span className="hero-kicker"><CloudRain size={14} /> {tr('prob_k')}</span>
          <h1>{tr('prob_h1')}</h1>
          <p>{tr('prob_p')}</p>
        </div>
        <div className="prob-stats">
          {Number.isFinite(natLandPct) && (
            <div className="prob-stat"><b>{fmtPct(natLandPct, 1)}</b><span>{tr('prob_s1')}</span><em>NISR · {psTxt}</em></div>)}
          {Number.isFinite(natNot) && (
            <div className="prob-stat"><b>{natNot}</b><span>{tr('prob_s2')}</span><em>NISR · {psTxt}</em></div>)}
          {gapDist.length > 0 && (
            <div className="prob-stat"><b>{gapDist.length}</b><span>{tr('prob_s3')}</span><em>{tr('st_ours')} · CHIRPS + NISR</em></div>)}
        </div>
        {/* the data behind every number on the page, named in full */}
        <div className="hero-data">
          <span className="hero-data-label">{tr('data_used')}</span>
          <div className="hero-meta">
            {/* official catalogue pages (NISR microdata needs a free account to download) */}
            <a href="https://microdata.statistics.gov.rw/index.php/catalog/124" target="_blank" rel="noopener noreferrer"><Database size={14} /> {tr('data_sas')} <ExternalLink size={12} /></a>
            <a href="https://www.chc.ucsb.edu/data/chirps" target="_blank" rel="noopener noreferrer"><CloudRain size={14} /> {tr('data_chirps')} <ExternalLink size={12} /></a>
            <a href="https://microdata.statistics.gov.rw/index.php/catalog/123" target="_blank" rel="noopener noreferrer"><House size={14} /> {tr('data_ahs')} <ExternalLink size={12} /></a>
            <Link to="/map"><MapIcon size={14} /> {tr('data_cover')}</Link>
          </div>
        </div>
      </div>

      {/* the solution: one planning question, answered in three steps (mirrors the problem banner) */}
      <section className="solution" aria-labelledby="sol-h">
        <span className="sol-k"><Sprout size={14} /> {tr('sol_k')}</span>
        <h2 id="sol-h">{tr('ov_story')}</h2>
        <p className="sol-lead">{tr('sol_p')}</p>
        <ol className="sol-steps">
          <li>
            <Link to="/need" className="sol-step">
              <span className="sol-head"><span className="sol-n">1</span>{tr('st1_k')}</span>
              <span className="sol-big">{gapDist.length}</span>
              <span className="sol-t">{tr('st1_t')}</span>
              <span className="sol-s">{tr('st1_s', gapDist.join(', '))}</span>
              <span className="sol-go">{tr('act_gap')} <ChevronRight size={15} /></span>
            </Link>
          </li>
          {pay && (
            <li>
              <Link to="/evidence" className="sol-step">
                <span className="sol-head"><span className="sol-n">2</span>{tr('st2_k')}</span>
                <span className="sol-big">{signedPct(pay.adjusted_pct)}</span>
                <span className="sol-t">{tr('st2_t', pay.crop_name.toLowerCase())}</span>
                <span className="sol-s">{tr('st2_s', signedPct(pay.adjusted_low), signedPct(pay.adjusted_high))}</span>
                <span className="sol-go">{tr('act_payoff')} <ChevronRight size={15} /></span>
              </Link>
            </li>
          )}
          <li>
            <Link to="/priority" className="sol-step">
              <span className="sol-head"><span className="sol-n">{pay ? 3 : 2}</span>{tr('st3_k')}</span>
              <span className="sol-big sol-names">{top5.slice(0, 3).map((r) => r.district_std).join(', ')}</span>
              <span className="sol-t">{tr('st3_t')}</span>
              <span className="sol-s">{tr('st3_s')}</span>
              <span className="sol-go">{tr('act_action')} <ChevronRight size={15} /></span>
            </Link>
          </li>
        </ol>
        <p className="sol-src">{tr('sol_src')}</p>
      </section>

      <nav className="jump" aria-label={tr('jump_label')}>
        <span className="muted small">{tr('jump_label')}</span>
        {[['sec-key', 'sec_key'], ['sec-where', 'sec_where'], ['sec-how', 'sec_how'], ['sec-pay', 'sec_pay'], ['sec-ours', 's_our_analysis']].map(([id, k]) => (
          <button key={id} type="button" onClick={() => jump(id)}>{tr(k)}</button>
        ))}
      </nav>

      <AudioNote id="overview" />
      <SectionTitle id="sec-key" title={tr('sec_key')} />
      <FiltersUsed used={['years', 'seasons', 'area']} />
      <div className="toolbar season-pick">
        <Select label={tr('pub_season')} value={ps ? ysKey(ps) : ''} onChange={setSeasonKey}
          options={[...ssAll].reverse().map((x) => ({ value: ysKey(x), label: tr('season_of', x.s, x.y) }))} width={200} />
        <span className="muted small">{area ? tr('pub_for', area) : tr('pub_unavailable_hint')}</span>
      </div>
      <KpiRow>
        <Kpi label={tr('pub_ind_irrig_any_farmer')} value={area ? fmtPct(share) : '–'} icon={UserCheck} color={brand.blue} delta={chg(kp.irr)} deltaUnit=" pts" deltaTitle={prevTxt}
          foot={pubFoot(kp.irr, tr('of_farmers'))}
          hint={area ? pubHint(kp.irr, kp.irr?.project_value != null ? tr('ours_was', fmtPct(kp.irr.project_value)) : '') : `${tr('pub_unavailable_hint')} ${kp.ours ? tr('ours_combined', fmtPct(kp.ours.estimate), f.area) : ''}`} />
        <Kpi label={tr('k_land_irr')} value={area && Number.isFinite(kp.landPct) ? fmtPct(kp.landPct) : '–'} icon={LandPlot} color={brand.green}
          foot={kp.irrLand?.value != null && kp.land?.value != null && O
            ? <>{tr('k_land_foot', fmtNum(kp.irrLand.value), fmtNum(kp.land.value))} · {psTxt} <span className="pub-tag" title={cite(O, kp.irrLand)}>{citeShort(O, kp.irrLand)}</span></>
            : <span className="muted">{tr('pub_unavailable')}</span>}
          hint={kp.irrLand && kp.land && O ? `${tr('k_land_hint')} ${cite(O, kp.irrLand)}` : tr('pub_unavailable_hint')} />
        <Kpi label={tr('pub_ind_inorganic_fert_farmer')} value={area ? fmtPct(val(kp.fert)) : '–'} icon={FlaskConical} color="#6A4C93" delta={chg(kp.fert)} deltaUnit=" pts" deltaTitle={prevTxt}
          foot={pubFoot(kp.fert, tr('of_farmers'))} hint={pubHint(kp.fert)} />
        <Kpi label={tr('k_season_c_pub')} value={area ? fmtPct(val(kp.sc)) : '–'} icon={Sun} color={brand.terracotta} delta={chg(kp.sc)} deltaUnit=" pts"
          deltaTitle={kp.sc ? tr('delta_vs', tr('season_of', 'C', kp.sc.sas_year - 1)) : undefined}
          foot={pubFoot(kp.sc, tr('of_farmers'), kp.sc ? tr('season_of', 'C', kp.sc.sas_year) : '')} hint={`${tr('c_hint')} ${pubHint(kp.sc)}`} />
      </KpiRow>

      <SectionTitle id="sec-where" title={tr('sec_where')} />
      <Grid cols="7fr 5fr">
        <ChartCard title={tr('ov_map_title_pub')} icon={MapPinned}
          means={dist.length >= 2 ? tr('ov_m_map_pub', psTxt, dist[0].d, fmtPct(dist[0].v), last(dist).d, fmtPct(last(dist).v), fmtPub(O, nat)) : null}
          source={O ? pubSource(O, dist.map((x) => x.r), tr) : tr('pub_unavailable')}
          table={O ? { cols: [tr('district'), tr('x_pct_farmers'), tr('pub_cell')], rows: dist.map((x) => [x.d, fmtPct(x.v), `${citeShort(O, x.r)} · ${x.r.cell}`]) } : null}>
          <div className="map-bars">
            <Plot fig={distMap} height={360} onClick={pickDistrict} empty={tr('pub_unavailable')} />
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
                <div className="dc-big"><span className="dc-num">{card.r ? fmtPct(card.r.v) : '–'}</span><span>{tr('of_farmers_irr')} · {psTxt}</span></div>
                <div className="dc-compare" role="img" aria-label={`${one} ${card.r ? fmtPct(card.r.v) : '–'}, Rwanda ${fmtPub(O, nat)}`}>
                  {[{ k: one, v: card.r?.v ?? NaN, c: brand.blue }, { k: 'Rwanda', v: val(nat), c: brand.grey }].map((x) => (
                    <div key={x.k} className="dc-row"><span>{x.k}</span><span className="dc-track"><i style={{ width: `${Math.min(100, (100 * (x.v || 0)) / Math.max(card.r?.v ?? 0, val(nat) || 0, 1))}%`, background: x.c }} /></span><b>{fmtPct(x.v)}</b></div>
                  ))}
                </div>
                <p className="muted small">{card.r && O ? citeShort(O, card.r.r) : tr('pub_unavailable')}</p>
                <ul className="dc-facts">
                  {card.ours && <li><Droplet size={14} /> {tr('ours_plots_line', fmtPct(card.ours.estimate))} <RelBadge r={card.ours.reliability} /></li>}
                  {card.need && <li><CloudRain size={14} /> {tr('need_score')}: <b>{fmtNum(card.need.need_score, 0)}/100</b></li>}
                  {card.sc && <li><Trophy size={14} /> {tr('profile_rank', card.sc.rank, card.sc.stability)}</li>}
                </ul>
                <Link className="btn outline sm" to="/district">{tr('ov_open_profile')}</Link>
              </>
            )}
          </div>
        </section>
      </Grid>

      <SectionTitle id="sec-how" title={tr('sec_how')} />
      <Grid cols="5fr 7fr">
        <ChartCard title={tr('ov_type_title')} icon={Wrench}
          means={types.length ? tr('ov_m_type', tr(`irr_type_${types[0].t}`), fmtPct(types[0].v, 0), `${area}, ${psTxt}`) : tr('pub_unavailable')}
          source={O ? pubSource(O, types.map((x) => x.r), tr) : undefined}
          table={{ cols: [tr('ov_type_title'), '%', tr('pub_cell')], rows: types.map((x) => [tr(`irr_type_${x.t}`), fmtPct(x.v), O ? `${citeShort(O, x.r)} · ${x.r.cell}` : '']) }}>
          <Plot fig={typeFig} height={300} empty={tr('pub_unavailable')} />
        </ChartCard>
        <ChartCard title={tr('c_trend_pub')} icon={ChartLine} means={<>{trendMeans ?? (isPub && !area ? tr('pub_unavailable_hint') : '')}{isPub && f.years.includes(2019) ? ` ${tr('trend_2019')}` : ''}</>}
          tools={<Select value={trendInd} onChange={setTrendInd} width="100%" options={[
            ...TREND_PUB.map((i) => ({ value: `pub:${i}`, label: `${tr(`pub_ind_${i}`)} (NISR)` })),
            ...TREND_OURS.map((i) => ({ value: i, label: `${tr(`ind_${i}`)} (${tr('layer_est')})` })),
          ]} />}
          source={isPub ? (O ? pubSource(O, trend.length && area ? [O.get(tInd, trend[trend.length - 1].y, trend[trend.length - 1].s, area)] : [], tr) : '') : tr('src_plots', f.seasons.join('+'), f.years.length ? `${Math.min(...f.years)}–${Math.max(...f.years)}` : '–', f.area)}
          table={{ cols: [tr('season'), unitPct ? '%' : O?.def.get(tInd)?.unit ?? '', isPub ? tr('pub_cell') : '95%'],
            rows: [...trend].sort((a, b) => a.y - b.y || a.s.localeCompare(b.s)).map((r) => [`${r.y}${r.s}`, unitPct ? fmtPct(r.v) : fmtNum(r.v), isPub ? r.src : `${fmtPct(r.lo)}–${fmtPct(r.hi)}`]) }}>
          <Plot fig={trendFig} height={300} empty={isPub && !area ? tr('pub_unavailable') : tr('no_data')} />
        </ChartCard>
      </Grid>

      <SectionTitle id="sec-pay" title={tr('sec_pay')} />
      <Grid cols="5fr 7fr">
        <ChartCard title={tr('ov_crop_title')} icon={Wheat}
          tools={<Select value={crop} onChange={setCrop} options={D.yield.crops.map((c) => ({ value: c, label: c }))} width="100%" />}
          means={<>{cropY ? tr('ov_m_crop', crop, `${f.area} ${cropY.k}`, fmtNum(cropY.y.irr), fmtNum(cropY.y.rf)) : tr('ov_crop_few', crop)}
            {cropAdj ? ` ${tr('ov_adj_note', signedPct(cropAdj.adjusted_pct), signedPct(cropAdj.adjusted_low), signedPct(cropAdj.adjusted_high))}` : ''}</>}
          source={<>{tr('layer_analysis')}. {tr('src_yield')}</>}
          table={cropY ? { cols: ['', 'kg/ha'], rows: [[tr('irrigated'), Math.round(cropY.y.irr)], [tr('rainfed'), Math.round(cropY.y.rf)]] } : null}>
          <Plot fig={cropFig} height={240} empty={tr('no_data')} />
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
            <p className="muted small">{tr('layer_analysis')}. {tr('ov_short_note')}</p>
            <div className="btn-row">
              <Link className="btn outline sm" to="/priority"><Trophy size={14} /> {tr('act_action')}</Link>
              <Link className="btn outline sm" to="/priority#feasibility"><ClipboardCheck size={14} /> {tr('ov_feas')}</Link>
            </div>
          </div>
        </section>
      </Grid>

      <SectionTitle id="sec-ours" title={tr('s_our_analysis')} />
      <InsightGrid>
        <Insight icon={Sprout} color={brand.green} title={tr('f2_t', ours.ya.length)} text={tr('f2', ours.ya.slice(0, 4).map((r) => r.crop_name).join(', '))} />
        <Insight icon={Users} color="#B07A1C" title={tr('f3_t')}
          text={tr('f3', fmtPct(ours.eq.find((r) => r.group === 'Female')?.estimate), fmtPct(ours.eq.find((r) => r.group === 'Male')?.estimate),
            fmtPct(ours.cs.find((r) => r.group === 'In consolidated site')?.estimate))} />
        <Insight icon={HandCoins} color="#6A4C93" title={tr('f6_t')}
          text={tr('f6', in100(ours.hv('improved_seed', 2024), tr), in100(ours.hv('crop_insurance', 2024), tr))} />
      </InsightGrid>
      <p className="muted small">{tr('our_note')}</p>

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

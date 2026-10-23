import { useMemo, useState } from 'react';
import { TriangleAlert, SlidersHorizontal, Map as MapIcon, ArrowUpDown, Table2, ClipboardCheck, CircleHelp, RotateCcw, Download } from 'lucide-react';
import type { Data } from 'plotly.js';
import { useApp } from '../data/store';
import { ChartCard, DataTable, FiltersUsed, Grid, RelBadge, relLabel, type Col, Callout } from '../components/ui';
import { Plot, choropleth, std, type Fig } from '../components/Plot';
import { downloadCsv } from '../lib/stats';
import { normalise, scoreRow, rankOf, weightSensitivity, qSorted, stabilityLabel, SIMS, CONCENTRATION, SEED } from '../lib/ranking';
import { fmtNum, fmtPct } from '../lib/format';
import { brand, colIrrigated, seqGreen } from '../lib/theme';
import { COMP } from './District';
import type { ScreenRow } from '../data/types';

// A screening aid: which districts to visit first for a feasibility check. Not an
// allocation rule; water, schemes and costs are not in the data yet.
export default function Priority() {
  const { D, f, tr, geo, pickDistrict } = useApp();
  const w0 = D.screen.default_weights;
  const [w, setW] = useState<Record<string, number>>({ ...w0 });
  // Everything below follows the weights on screen: score, rank, the two strongest
  // reasons and the sensitivity (weight sets drawn around the chosen weights)
  // Effective weights = chosen weights / their sum. All zero = no ranking at all (no hidden
  // fallback to the defaults), so the map, table, sensitivity and CSV all say the same thing.
  const p = useMemo(() => normalise(w, COMP), [w]);
  const allZero = p == null;
  // Everything below follows the weights on screen: score, rank, the two strongest
  // reasons and the weight sensitivity (Dirichlet draws around the effective weights)
  const scored = useMemo(() => {
    if (!p) return [];
    const base = D.screen.table.map((r) => scoreRow(r, p, COMP));
    const ranks = rankOf(base);
    const sims = weightSensitivity(D.screen.table, p, COMP);
    return D.screen.table.map((r, i) => {
      const rk = sims.map((s) => s[i]).sort((a, b) => a - b);
      const p10 = qSorted(rk, 0.1), p90 = qSorted(rk, 0.9);
      const contrib = COMP.map((c) => ({ c, v: r[c] * p[c] })).sort((a, b) => b.v - a.v);
      return { ...r, score_user: base[i], rank_user: ranks[i], rank_p10_user: p10, rank_p90_user: p90,
        top5_user: (100 * rk.filter((x) => x <= 5).length) / rk.length, top10_user: (100 * rk.filter((x) => x <= 10).length) / rk.length,
        stability_user: stabilityLabel(p10, p90),
        reasons_user: contrib.filter((x) => x.v > 0).slice(0, 2).map((x) => x.c).join(',') };
    }).sort((a, b) => a.rank_user - b.rank_user);
  }, [D, p]);
  const wLabel = p ? COMP.filter((c) => p[c] > 0).map((c) => `${tr(`w_${c}`)} ${Math.round(100 * p[c])}%`).join(', ') : tr('weights_none');
  type Row = (typeof scored)[number];

  const mapFig = useMemo(() => choropleth(geo, scored.map((r) => ({ district: r.district_std, value: r.score_user,
    hover: `<b>${r.district_std}</b> #${r.rank_user}<br>${tr('score')}: ${fmtNum(r.score_user, 0)}/100<br>${tr('stability')}: ${r.stability_user}<br>${tr('ind_irrigated')}: ${fmtPct(r.adoption_pct)} (${relLabel(tr, r.adoption_reliability)})` })),
  { noData: tr('no_estimate'), label: tr('score'), colorscale: seqGreen, zmin: 0, zmax: 100, selected: f.areaLevel !== 'national' ? f.districts : undefined }), [geo, scored, f, tr]);
  const top5 = scored.slice(0, 5), moved = scored.filter((r) => r.rank_user !== r.rank).length;
  const unrel = top5.filter((r) => r.adoption_reliability === 'Unreliable').map((r) => r.district_std);

  const sensFig = useMemo<Fig>(() => {
    const d = (f.areaLevel !== 'national' ? scored.filter((r) => f.districts.includes(r.district_std)) : scored.slice(0, 15)).sort((a, b) => b.rank_user - a.rank_user)
      .map((r) => ({ ...r, rank_p10: r.rank_p10_user, rank_p90: r.rank_p90_user, stability: r.stability_user, prob_top5_pct: r.top5_user }));
    const SC: Record<string, string> = { Stable: colIrrigated, 'Moderately sensitive': '#B07A1C', 'Sensitive to weights': brand.terracotta };
    return { data: [
      ...d.map((r) => ({ type: 'scatter', mode: 'lines', x: [r.rank_p10, r.rank_p90], y: [r.district_std, r.district_std], line: { color: '#C9D3CD', width: 8 }, hoverinfo: 'skip', showlegend: false })),
      ...Object.keys(SC).map((st) => { const x = d.filter((r) => r.stability === st); return { type: 'scatter', mode: 'markers', name: st, x: x.map((r) => r.rank_user), y: x.map((r) => r.district_std),
        marker: { size: 12, color: SC[st], line: { color: '#fff', width: 1.5 } },
        text: x.map((r) => `<b>${r.district_std}</b><br>${tr('your_rank')}: ${r.rank_user}<br>${tr('rank_range')}: ${Math.round(r.rank_p10)}–${Math.round(r.rank_p90)}<br>${tr('prob_top5')}: ${Math.round(r.prob_top5_pct)}`), hoverinfo: 'text' }; }),
    ] as Data[], layout: std({ x: tr('x_rank'), xaxis: { autorange: 'reversed', dtick: 5 }, yaxis: { title: { text: '' }, tickfont: { size: 11 }, categoryorder: 'array', categoryarray: d.map((r) => r.district_std) } }) };
  }, [scored, f, tr]);
  const stable = scored.filter((r) => r.rank_user <= 10 && r.top10_user >= 80).map((r) => r.district_std);

  const why = (r: string) => r.split(',').map((x) => tr(`w_${x}`)).join(' + ');
  const prov = (d: string) => D.lookup.find((r) => r.district === d)?.province ?? '';
  const shortlist = scored.filter((r) => f.districts.includes(r.district_std));
  const missing = D.screen.feasibility_missing ?? [];
  const pct = (x: number) => Math.round(100 * x);
  const cols: Col<Row>[] = [
    { key: 'rank', label: '#', get: (r) => r.rank_user, num: true },
    { key: 'd', label: tr('district'), get: (r) => r.district_std, render: (r) => <button className="link-btn" onClick={() => pickDistrict(r.district_std)}>{r.district_std}</button> },
    { key: 'p', label: tr('province'), get: (r) => prov(r.district_std) },
    { key: 's', label: tr('score'), get: (r) => Math.round(r.score_user * 10) / 10, num: true, render: (r) => <span className="score-bar"><i style={{ width: `${r.score_user * 0.6}px` }} />{fmtNum(r.score_user, 1)}</span> },
    { key: 'why', label: tr('why_listed'), get: (r) => why(r.reasons_user) },
    ...COMP.map((c) => ({ key: c, label: tr(`w_${c}`), get: (r: ScreenRow) => pct(r[c]), num: true })),
    { key: 'adopt', label: tr('ind_irrigated'), get: (r) => r.adoption_pct, num: true, render: (r) => fmtPct(r.adoption_pct) },
    { key: 'rel', label: tr('reliability'), get: (r) => relLabel(tr, r.adoption_reliability), render: (r) => <RelBadge r={r.adoption_reliability} /> },
    { key: 'range', label: tr('rank_range'), get: (r) => `${r.rank_p10_user}–${r.rank_p90_user}` },
    { key: 'top5', label: tr('prob_top5'), get: (r) => Math.round(r.top5_user), num: true },
    { key: 'stab', label: tr('stability'), get: (r) => r.stability_user },
  ];
  // the CSV says how it was made: weights, periods, layer and what is still to check
  const dl = () => {
    if (!p) return;
    const per = D.screen.meta?.periods ?? {};
    downloadCsv(shortlist.map((r) => ({
      rank: r.rank_user, district: r.district_std, province: prov(r.district_std), score: Math.round(r.score_user * 10) / 10, why_listed: why(r.reasons_user),
      ...Object.fromEntries(COMP.map((c) => [`${c}_0to100`, pct(r[c])])),
      ...Object.fromEntries(COMP.map((c) => [`weight_${c}`, Math.round(1000 * p[c]) / 1000])),
      irrigated_plots_pct: r.adoption_pct == null ? '' : Math.round(r.adoption_pct * 10) / 10, irrigation_figure_quality: r.adoption_reliability,
      rank_range_p10_p90: `${r.rank_p10_user}-${r.rank_p90_user}`, top5_in_100_weight_sets: Math.round(r.top5_user), stability: r.stability_user,
      weight_sensitivity: `${SIMS} weight sets from Dirichlet(${CONCENTRATION} x effective weights) over the criteria above zero; zero criteria stay zero; seed ${SEED}. Preference-weight sensitivity only: not survey sampling error, not a chance of investment success`,
      periods: COMP.map((c) => `${c}: ${per[c] ?? ''}`).join('; '),
      layer: 'project_analysis (screening shortlist, not an investment ranking; not an official statistic)',
      still_to_check: missing.map((k) => tr(`feas_${k}`)).join('; '),
    })), 'smartirrigate_shortlist.csv');
  };

  return (
    <>
      <FiltersUsed used={['area']} />
      <Callout icon={TriangleAlert} kind="warn">{tr('prelim_text')}</Callout>
      {allZero && <div role="status"><Callout icon={TriangleAlert} kind="warn">{tr('weights_all_zero')}</Callout></div>}
      <Grid cols="3fr 9fr">
        <section className="card chart-card">
          <header className="card-head"><span className="ch-icon"><SlidersHorizontal size={16} /></span><h3>{tr('weights')}</h3></header>
          <div className="card-body">
            {COMP.map((c) => (
              <div className="weight" key={c}>
                <div className="weight-top"><span>{tr(`w_${c}`)}</span><b>{w[c].toFixed(2)}<small className="muted"> · {p ? `${Math.round(100 * p[c])}%` : '–'}</small></b></div>
                <input type="range" min={0} max={1} step={0.05} value={w[c]} onChange={(e) => setW({ ...w, [c]: Number(e.target.value) })} aria-label={tr(`w_${c}`)} />
              </div>
            ))}
            <button className="btn outline sm" onClick={() => setW({ ...w0 })}><RotateCcw size={14} /> {tr('reset_weights')}</button>
            <p className="muted small">{tr('weights_help')}</p>
            <p className="muted small">{tr('weights_effective')}</p>
          </div>
        </section>
        <Grid cols="1fr 1fr">
          <ChartCard title={tr('c_priority_map')} icon={MapIcon} source={tr('src_screen', wLabel)}
            table={{ cols: ['#', tr('district'), tr('score'), tr('why_listed')], rows: scored.map((r) => [r.rank_user, r.district_std, Math.round(r.score_user), why(r.reasons_user)]) }}
            means={<>{tr('m_priority', top5.map((r) => r.district_std).join(', '))} {moved ? tr('m_priority_moved', moved) : tr('m_priority_default')}{unrel.length ? ` ${tr('m_unrel_districts', unrel.join(', '))}` : ''}</>}>
            <Plot fig={mapFig} height={380} onClick={pickDistrict} />
          </ChartCard>
          <ChartCard title={tr('c_sensitivity')} icon={ArrowUpDown} means={<>{tr('m_sens', stable.length ? stable.join(', ') : '–')} {tr('sens_scope')}</>}
            table={{ cols: [tr('district'), tr('your_rank'), tr('rank_range'), tr('prob_top5')], rows: scored.slice(0, 15).map((r) => [r.district_std, r.rank_user, `${r.rank_p10_user}–${r.rank_p90_user}`, Math.round(r.top5_user)]) }}>
            <Plot fig={sensFig} height={380} onClick={pickDistrict} />
          </ChartCard>
        </Grid>
      </Grid>
      <ChartCard title={tr('c_priority_table')} icon={Table2} tools={<button className="btn outline sm" onClick={dl} disabled={allZero} aria-disabled={allZero}><Download size={14} /> {tr('dl_shortlist')}</button>}>
        <DataTable rows={shortlist} cols={cols} pageSize={10} />
      </ChartCard>
      <div style={{ height: 16 }} />
      <section className="card chart-card" id="feasibility">
        <header className="card-head"><span className="ch-icon"><ClipboardCheck size={16} /></span><h3>{tr('feas_title')}</h3></header>
        <div className="card-body"><p>{tr('feas_intro')}</p>
          <ul className="feas-list">{missing.map((k) => <li key={k}><CircleHelp size={15} /> {tr(`feas_${k}`)}</li>)}</ul>
        </div>
      </section>
    </>
  );
}


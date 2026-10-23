import { useEffect, useMemo, useState } from 'react';
import { ClipboardCheck, FileDown, TriangleAlert, ListChecks, Target, Download, RotateCcw } from 'lucide-react';
import { useApp } from '../data/store';
import { Callout, Grid, RelBadge, Select, relLabel } from '../components/ui';
import { downloadCsv } from '../lib/stats';
import { normalise, scoreRow, rankOf, weightSensitivity, qSorted } from '../lib/ranking';
import { fmtNum, fmtPct } from '../lib/format';
import { COMP } from './District';

// Step 4 and 5 of the planner's journey: record what is known about a shortlisted
// district, separate measured / documented / assumed / unknown, and export a brief.
// Nothing here is a field finding: every check starts as "Unknown" and only the
// planner's own entries change it. Entries stay in this browser only.

export const CHECKS = ['water_source', 'schemes', 'land', 'lift_energy', 'coop', 'crops_markets', 'costs', 'environment'] as const;
export const STATUS = ['unknown', 'assumed', 'documented', 'measured'] as const;
type Status = (typeof STATUS)[number];
interface Check { status: Status; evidence: string; source: string; date: string; next: string }
type Store = Record<string, Partial<Record<string, Check>>>;
const KEY = 'si-assess-v1';
const empty = (): Check => ({ status: 'unknown', evidence: '', source: '', date: '', next: '' });
const load = (): Store => { try { return JSON.parse(localStorage.getItem(KEY) || '{}') as Store; } catch { return {}; } };
const save = (s: Store) => { try { localStorage.setItem(KEY, JSON.stringify(s)); } catch { /* private mode: entries live until reload */ } };

export default function Assess() {
  const { D, tr, f } = useApp();
  // default screening (the published default weights) so the brief does not depend on slider state;
  // weights are shown as effective shares (they sum to 100%), as on the Priority page
  const pEff = useMemo(() => normalise(D.screen.default_weights, COMP), [D]);
  const ranked = useMemo(() => {
    const p = pEff;
    if (!p) return [];
    const base = D.screen.table.map((r) => scoreRow(r, p, COMP));
    const rk = rankOf(base), sims = weightSensitivity(D.screen.table, p, COMP);
    return D.screen.table.map((r, i) => {
      const s = sims.map((x) => x[i]).sort((a, b) => a - b);
      return { r, score: base[i], rank: rk[i], p10: qSorted(s, 0.1), p90: qSorted(s, 0.9),
        reasons: COMP.map((c) => ({ c, v: r[c] * p[c] })).sort((a, b) => b.v - a.v).filter((x) => x.v > 0).slice(0, 2).map((x) => x.c) };
    }).sort((a, b) => a.rank - b.rank);
  }, [D, pEff]);
  const [dist, setDist] = useState(f.district || ranked[0]?.r.district_std || '');
  useEffect(() => { if (f.district) setDist(f.district); }, [f.district]);
  const [store, setStore] = useState<Store>(load);
  const checks = (d: string) => Object.fromEntries(CHECKS.map((k) => [k, { ...empty(), ...(store[d]?.[k] ?? {}) }])) as Record<string, Check>;
  const cur = checks(dist);
  const set = (k: string, patch: Partial<Check>) => {
    const next = { ...store, [dist]: { ...store[dist], [k]: { ...cur[k], ...patch } } };
    setStore(next); save(next);
  };
  const clear = () => { const next = { ...store }; delete next[dist]; setStore(next); save(next); };

  const row = ranked.find((x) => x.r.district_std === dist);
  const nd = D.rain.district.find((r) => r.district_std === dist);
  const per = D.screen.meta?.periods ?? {};
  const counts = Object.fromEntries(STATUS.map((s) => [s, CHECKS.filter((k) => cur[k].status === s).length])) as Record<Status, number>;
  const ver = `${D.meta.built} · code ${__SITE_VERSION__}`;

  const briefRows = () => CHECKS.map((k) => ({
    district: dist, check: tr(`as_${k}`), status: tr(`st_${cur[k].status}`), evidence: cur[k].evidence,
    source: cur[k].source, evidence_date: cur[k].date, next_action: cur[k].next,
  }));
  const brief = () => {
    if (!row) return;
    const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c] as string);
    const comp = COMP.map((c) => `<tr><td>${esc(tr(`w_${c}`))}</td><td>${Math.round(100 * row.r[c])}</td><td>${Math.round(100 * (pEff?.[c] ?? 0))}%</td><td>${esc(per[c] ?? '')}</td></tr>`).join('');
    const chk = CHECKS.map((k) => `<tr class="${cur[k].status}"><td>${esc(tr(`as_${k}`))}</td><td><b>${esc(tr(`st_${cur[k].status}`))}</b></td><td>${esc(cur[k].evidence) || '–'}</td><td>${esc(cur[k].source) || '–'}</td><td>${esc(cur[k].date) || '–'}</td><td>${esc(cur[k].next) || '–'}</td></tr>`).join('');
    const unknown = CHECKS.filter((k) => cur[k].status === 'unknown' || cur[k].status === 'assumed').map((k) => `<li>${esc(tr(`as_${k}`))} (${esc(tr(`st_${cur[k].status}`))})</li>`).join('');
    const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(tr('as_brief_title', dist))}</title>
<style>body{font:14px/1.5 system-ui,sans-serif;color:#1B2C2A;background:#fff;max-width:900px;margin:24px auto;padding:0 16px}h1{color:#176B45;margin-bottom:0}h2{color:#176B45;border-bottom:2px solid #E3E8E4;padding-bottom:4px;margin-top:28px}
table{border-collapse:collapse;width:100%;margin:8px 0}td,th{border:1px solid #D5DCD7;padding:6px 8px;text-align:left;vertical-align:top}th{background:#F7F9F6}.unknown b{color:#B65F47}.assumed b{color:#9A6B12}.documented b{color:#1976B9}.measured b{color:#176B45}
.note{background:#FFF7E8;border-left:4px solid #D39A32;padding:8px 12px}.muted{color:#5F6B66;font-size:12px}@media print{body{margin:0}}</style></head><body>
<h1>${esc(tr('as_brief_title', dist))}</h1><p class="muted">${esc(row.r.province)} · ${esc(tr('as_generated'))} ${new Date().toISOString().slice(0, 10)} · ${esc(tr('as_data_version'))} ${esc(ver)} · SmartIrrigate Rwanda</p>
<p class="note">${esc(tr('as_scope'))}</p>
<h2>1. ${esc(tr('as_s_why'))}</h2>
<p>${esc(tr('as_rank_line', row.rank, D.screen.table.length, fmtNum(row.score, 1), row.p10, row.p90))} ${esc(tr('as_reasons', row.reasons.map((c) => tr(`w_${c}`)).join(' + ')))}</p>
<table><tr><th>${esc(tr('as_criterion'))}</th><th>${esc(tr('as_score_0_100'))}</th><th>${esc(tr('as_weight'))}</th><th>${esc(tr('as_period_source'))}</th></tr>${comp}</table>
<h2>2. ${esc(tr('as_s_evidence'))}</h2><table>
<tr><td>${esc(tr('as_ev_irrig'))}</td><td>${row.r.adoption_pct == null ? '–' : fmtPct(row.r.adoption_pct)} (${esc(relLabel(tr, row.r.adoption_reliability))}${nd?.adoption_low != null ? `, 95% CI ${fmtPct(nd.adoption_low)}–${fmtPct(nd.adoption_high)}` : ''}${nd?.adoption_n ? `, n = ${nd.adoption_n} plots` : ''})</td><td>${esc(tr('as_kind_measured'))}</td></tr>
<tr><td>${esc(tr('as_ev_rain'))}</td><td>${nd ? `${fmtNum(nd.rain_normal_ab_mm, 0)} mm · CV ${fmtNum(nd.rain_cv_pct, 1)}% · ${nd.dry_seasons_2016_2025} / 20` : '–'}</td><td>${esc(tr('as_kind_measured_sat'))}</td></tr>
<tr><td>${esc(tr('as_ev_area'))}</td><td>${fmtNum(row.r.cultivated_area_ha, 0)} ha</td><td>${esc(tr('as_kind_measured'))}</td></tr></table>
<p class="muted">${esc(tr('as_ev_note'))}</p>
<h2>3. ${esc(tr('as_s_checks'))}</h2><p>${esc(tr('as_counts', counts.measured, counts.documented, counts.assumed, counts.unknown))}</p>
<table><tr><th>${esc(tr('as_check'))}</th><th>${esc(tr('as_status'))}</th><th>${esc(tr('as_evidence'))}</th><th>${esc(tr('as_source'))}</th><th>${esc(tr('as_date'))}</th><th>${esc(tr('as_next'))}</th></tr>${chk}</table>
<h2>4. ${esc(tr('as_s_unknowns'))}</h2>${unknown ? `<ul>${unknown}</ul>` : `<p>${esc(tr('as_none_open'))}</p>`}
<h2>5. ${esc(tr('as_s_limits'))}</h2><ul><li>${esc(tr('as_lim_1'))}</li><li>${esc(tr('as_lim_2'))}</li><li>${esc(tr('as_lim_3'))}</li><li>${esc(tr('as_lim_4'))}</li></ul>
<p class="muted">${esc(tr('disclaimer'))}</p></body></html>`;
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([html], { type: 'text/html;charset=utf-8' }));
    a.download = `district_assessment_brief_${dist}.html`; a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  };

  return (
    <>
      <Callout icon={TriangleAlert} kind="warn">{tr('as_scope')}</Callout>
      <section className="card pad assess-head">
        <Select label={tr('district')} value={dist} onChange={setDist}
          options={ranked.map((x) => ({ value: x.r.district_std, label: `#${x.rank} ${x.r.district_std}` }))} />
        <div className="assess-actions">
          <button className="btn" onClick={brief}><FileDown size={15} /> {tr('as_export_brief')}</button>
          <button className="btn outline sm" onClick={() => downloadCsv(briefRows(), `district_checks_${dist}.csv`)}><Download size={14} /> CSV</button>
          <button className="btn outline sm" onClick={clear}><RotateCcw size={14} /> {tr('as_clear')}</button>
        </div>
      </section>
      {row && (
        <Grid cols="5fr 7fr">
          <section className="card chart-card">
            <header className="card-head"><span className="ch-icon"><Target size={16} /></span><h3>{tr('as_s_why')}</h3></header>
            <div className="card-body">
              <p className="lead">{tr('as_rank_line', row.rank, D.screen.table.length, fmtNum(row.score, 1), row.p10, row.p90)}</p>
              <p>{tr('as_reasons', row.reasons.map((c) => tr(`w_${c}`)).join(' + '))}</p>
              <table className="mini-table"><thead><tr><th>{tr('as_criterion')}</th><th>{tr('as_score_0_100')}</th><th>{tr('as_weight')}</th></tr></thead>
                <tbody>{COMP.map((c) => <tr key={c}><td title={per[c]}>{tr(`w_${c}`)}</td><td><span className="score-bar"><i style={{ width: `${row.r[c] * 60}px` }} />{Math.round(100 * row.r[c])}</span></td><td>{Math.round(100 * (pEff?.[c] ?? 0))}%</td></tr>)}</tbody></table>
              <p className="muted small">{tr('as_irrig_line', row.r.adoption_pct == null ? '–' : fmtPct(row.r.adoption_pct))} <RelBadge r={row.r.adoption_reliability} /></p>
              <p className="muted small">{tr('as_ev_note')}</p>
            </div>
          </section>
          <section className="card chart-card">
            <header className="card-head"><span className="ch-icon"><ListChecks size={16} /></span><h3>{tr('as_s_checks')}</h3></header>
            <div className="card-body">
              <p className="muted small">{tr('as_checks_help')}</p>
              <div className="status-strip" role="img" aria-label={tr('as_counts', counts.measured, counts.documented, counts.assumed, counts.unknown)}>
                {STATUS.slice().reverse().map((s) => counts[s] ? <span key={s} className={`st st-${s}`} style={{ flex: counts[s] }}>{counts[s]} {tr(`st_${s}`)}</span> : null)}
              </div>
              {CHECKS.map((k) => (
                <details key={k} className={`check st-border-${cur[k].status}`}>
                  <summary><ClipboardCheck size={15} /> <span>{tr(`as_${k}`)}</span> <b className={`st-text-${cur[k].status}`}>{tr(`st_${cur[k].status}`)}</b></summary>
                  <p className="muted small">{tr(`as_${k}_q`)}</p>
                  <div className="check-grid">
                    <label>{tr('as_status')}<select value={cur[k].status} onChange={(e) => set(k, { status: e.target.value as Status })}>
                      {STATUS.map((s) => <option key={s} value={s}>{tr(`st_${s}`)}</option>)}</select></label>
                    <label>{tr('as_date')}<input type="date" value={cur[k].date} onChange={(e) => set(k, { date: e.target.value })} /></label>
                    <label className="wide">{tr('as_evidence')}<textarea rows={2} value={cur[k].evidence} onChange={(e) => set(k, { evidence: e.target.value })} /></label>
                    <label className="wide">{tr('as_source')}<input value={cur[k].source} onChange={(e) => set(k, { source: e.target.value })} /></label>
                    <label className="wide">{tr('as_next')}<input value={cur[k].next} onChange={(e) => set(k, { next: e.target.value })} /></label>
                  </div>
                </details>
              ))}
              <p className="muted small">{tr('as_local_only')}</p>
            </div>
          </section>
        </Grid>
      )}
    </>
  );
}

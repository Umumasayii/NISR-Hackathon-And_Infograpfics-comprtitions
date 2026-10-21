import { useMemo, useState } from 'react';
import { Sprout, Workflow, TriangleAlert, Ruler, Bot, Download, Scale } from 'lucide-react';
import { useApp } from '../data/store';
import { DataTable, RelBadge, Select, Tabs, type Col } from '../components/ui';
import { citeShort, pubCsv } from '../lib/official';
import type { PubRow } from '../data/types';
import { downloadCsv } from '../lib/stats';
import { fmtNum, fmtPct } from '../lib/format';

/** the one general Data Source (SCRIPTS/app/DATA_SOURCE.md): paragraphs, bold, italics, links */
function mdToHtml(md: string) {
  const esc = md.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  return esc.split(/\n\s*\n/).map((p) => `<p>${p
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>').replace(/\*(.+?)\*/g, '<em>$1</em>')
    .replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>')
    .replace(/\n/g, '<br>')}</p>`).join('');
}

export default function Methods() {
  const { D, O, tr, dataSource } = useApp();
  const [tab, setTab] = useState('about');
  const tabs = [
    { id: 'about', label: tr('t_about'), icon: Sprout }, { id: 'pipeline', label: tr('t_pipeline'), icon: Workflow },
    { id: 'traps', label: tr('t_traps'), icon: TriangleAlert }, { id: 'kpi', label: tr('t_kpi'), icon: Ruler },
    { id: 'register', label: tr('reg_title'), icon: Scale }, { id: 'ai', label: tr('t_ai'), icon: Bot }, { id: 'downloads', label: tr('t_downloads'), icon: Download },
  ];
  return (
    <section className="card pad prose">
      <Tabs tabs={tabs} active={tab} onChange={setTab} />
      {tab === 'about' && <About />}
      {tab === 'pipeline' && <ol className="pipeline">{[1, 2, 3, 4, 5, 6, 7].map((i) => <li key={i}><strong>{tr(`pipe_${i}_t`)}</strong> {tr(`pipe_${i}`)}</li>)}</ol>}
      {tab === 'traps' && <Traps />}
      {tab === 'kpi' && <KpiDefs />}
      {tab === 'ai' && <><p>{tr('ai_text')}</p><ul>{[1, 2, 3, 4].map((i) => <li key={i}>{tr(`ai_${i}`)}</li>)}</ul></>}
      {tab === 'register' && <Register />}
      {tab === 'downloads' && <Downloads />}
    </section>
  );

  function About() {
    return (
      <div className="grid" style={{ ['--cols' as string]: '7fr 5fr' }}>
        <div>
          <h4>{tr('about_title')}</h4><p>{tr('about_text')}</p>
          <h5>{tr('personas')}</h5>
          <ul>
            <li><strong>{tr('persona_farmer')}</strong> {tr('persona_farmer_txt')}</li>
            <li><strong>{tr('persona_planner')}</strong> {tr('persona_planner_txt')}</li>
            <li><strong>{tr('persona_research')}</strong> {tr('persona_research_txt')}</li>
          </ul>
          <h5>{tr('team')}</h5><p>{tr('footer_by')}</p>
        </div>
        <div>
          <h5>{tr('sources')}</h5>
          {dataSource ? <div className="data-source" dangerouslySetInnerHTML={{ __html: mdToHtml(dataSource) }} />
            : <table className="ptable"><tbody>{D.meta.sources.map((s) => <tr key={s.source}><td>{s.source}</td><td>{s.use}</td></tr>)}</tbody></table>}
          <h5>{tr('reliability')}</h5>
          <p><RelBadge r="Good" /> {tr('rel_good')}</p><p><RelBadge r="Use with caution" /> {tr('rel_caution')}</p>
          <p><RelBadge r="Unreliable" /> {tr('rel_unreliable')}</p><p><RelBadge r="Published" /> {tr('rel_published')}</p>
        </div>
      </div>
    );
  }

  function Traps() {
    type R = Record<string, unknown>;
    const mk = (rows: R[], keys: string[]): Col<R>[] => keys.filter((k) => rows.length && k in rows[0]).map((k) => ({ key: k, label: k, get: (r) => (r[k] == null ? null : typeof r[k] === 'number' ? (r[k] as number) : String(r[k])), num: typeof rows[0][k] === 'number' }));
    const skip = D.meta.skip_audit, joins = D.meta.join_log;
    return (
      <>
        <ul>{[1, 2, 3, 4, 5, 6, 7, 8, 9].map((i) => <li key={i}>{tr(`trap_${i}`)}</li>)}</ul>
        <h5>{tr('cov_title')}</h5><p className="muted">{tr('cov_help')}</p>
        <table className="ptable"><thead><tr><th>{tr('season')}</th><th>%</th><th /></tr></thead>
          <tbody>{D.meta.season_quality.map((q) => (
            <tr key={`${q.sas_year}${q.sas_season}`}><td>{q.sas_year}{q.sas_season}</td><td>{Math.round(q.area_coverage_pct)}%</td>
              <td>{q.yield_usable ? '✓' : tr('yield_excluded', `${q.sas_year}${q.sas_season}`)}</td></tr>))}</tbody></table>
        <h5>{tr('skip_audit')}</h5><p className="muted">{tr('skip_audit_help')}</p>
        <DataTable rows={skip} cols={mk(skip, ['variable', 'ys', 'skip_confirmed', 'blanks_set_to_no', 'rows', 'gate_present_pct', 'gate_no', 'answered_when_gate_no'])} pageSize={8} />
        <h5>{tr('join_log')}</h5><p className="muted">{tr('join_log_help')}</p>
        <DataTable rows={joins} cols={mk(joins, Object.keys(joins[0] ?? {}))} pageSize={8} />
      </>
    );
  }

  function KpiDefs() {
    const k = ['irrigated', 'irrig_any_farmer', 'irrig_modern', 'irrigated_area_ha', 'yield', 'adjusted', 'sales', 'need', 'priority'];
    return (
      <>
        <p>{tr('kpi_rule')}</p>
        <table className="ptable"><thead><tr><th>KPI</th><th>{tr('definition')}</th></tr></thead>
          <tbody>{k.map((x) => <tr key={x}><td><strong>{tr(`kd_${x}_n`)}</strong></td><td>{tr(`kd_${x}`)}</td></tr>)}</tbody></table>
      </>
    );
  }

  /** every published NISR figure the app uses, our estimate beside it where the definition is the same */
  function Register() {
    const [ind, setInd] = useState('irrig_any_farmer');
    const [lvl, setLvl] = useState('national');
    const all = O?.rows ?? [];
    const inds = useMemo(() => [...new Set(all.map((r) => r.indicator))].sort(), [all]);
    const rows = useMemo(() => all.filter((r) => r.indicator === ind && r.level === lvl), [all, ind, lvl]);
    if (!O) return <p className="muted">{tr('pub_unavailable')}</p>;
    type R = PubRow;
    const u = O.def.get(ind)?.unit ?? '';
    const fv = (v: number | null) => (v == null ? null : u === '%' ? fmtPct(v) : fmtNum(v));
    const gap = (r: R) => (r.value == null || r.project_value == null || r.d !== 'cross_check' ? null : r.value - r.project_value);
    const cols: Col<R>[] = [
      { key: 'ys', label: tr('season'), get: (r) => `${r.sas_year}${r.sas_season}` },
      { key: 'area', label: tr('area'), get: (r) => r.area },
      ...(rows.some((r) => r.crop_name) ? [{ key: 'crop', label: tr('crop'), get: (r: R) => (r.crop_name ?? '') + (r.is_group ? ` · ${tr('subtotal')}` : '') }] : []),
      { key: 'pub', label: tr('reg_published'), get: (r) => r.value, num: true, render: (r) => fv(r.value) ?? tr('pub_blank') },
      { key: 'ours', label: tr('reg_ours'), get: (r) => r.project_value, num: true, render: (r) => fv(r.project_value) ?? '–' },
      { key: 'gap', label: tr('reg_gap'), get: (r) => gap(r), num: true, render: (r) => { const g = gap(r); return g == null ? '–' : u === '%' ? `${g > 0 ? '+' : ''}${fmtNum(g, 1)} pts` : `${g > 0 ? '+' : ''}${fmtNum((100 * g) / (r.value as number), 0)}%`; } },
      { key: 'dec', label: tr('reg_decision'), get: (r) => tr(`dec_${r.d ?? 'none'}`) },
      { key: 'src', label: tr('reg_source'), get: (r) => `${citeShort(O, r)} · ${r.cell}` },
    ];
    const d = O.def.get(ind);
    return (
      <>
        <p>{tr('reg_note')}</p>
        <ul>{[1, 2, 3, 4, 5, 6].map((i) => <li key={i}>{tr(`rec_${i}`)}</li>)}</ul>
        <div className="toolbar">
          <Select label={tr('indicator')} value={ind} onChange={setInd} options={inds.map((i) => ({ value: i, label: tr(`pub_ind_${i}`) }))} width={300} />
          <Select label={tr('area')} value={lvl} onChange={setLvl} options={[{ value: 'national', label: 'Rwanda' }, { value: 'district', label: tr('districts') }]} width={160} />
        </div>
        {d && <p className="muted small"><strong>{tr('definition')}:</strong> {d.definition}. <strong>{tr('who')}:</strong> {d.population}. {tr('unit')}: {d.unit}. {d.comparable ? tr('reg_same_def') : tr('reg_diff_def')}</p>}
        <DataTable rows={rows} cols={cols} pageSize={12} csvName={`smartirrigate_register_${ind}_${lvl}.csv`} csvRows={() => pubCsv(O, rows)} />
        <p className="muted small">{tr('reg_full')}</p>
      </>
    );
  }

  function Downloads() {
    type Rows = Record<string, unknown>[];
    const tag = (rows: unknown[], layer: string, source: string): Rows =>
      (rows as Rows).map((r) => ({ ...r, layer, source, scope: 'statistics 2019-2025; not official NISR statistics unless layer = published' }));
    const w = Object.entries(D.screen.default_weights).map(([k, v]) => `${k}=${v}`).join(' ');
    const sets: Record<string, () => Rows> = {
      est_plot: () => tag(D.est, 'project_estimate', 'SAS 2019-2025 microdata, survey-weighted'),
      totals: () => tag(D.totals, 'project_estimate', 'SAS 2019-2025 microdata, survey-weighted totals'),
      crop_season: () => tag(D.crop, 'project_estimate', 'SAS 2019-2025 microdata; crop rows only, no group subtotals'),
      priority_screening: () => tag(D.screen.table, 'project_analysis', `screening score, default weights ${w}; ${D.screen.meta?.sensitivity ?? ''}`),
      need_adoption: () => tag(D.rain.district, 'project_analysis', 'CHIRPS v2 1991-2020 season-specific variability + SAS 2023-2025'),
      yield_adjusted: () => tag(D.model_yield.table, 'model_output', 'survey-weighted log yield model, SAS 2019-2025 (2024B, 2024C excluded)'),
      model_validation: () => tag(D.model.performance, 'model_output', 'out-of-time validation'),
      ...(O ? { published_nisr: () => pubCsv(O, O.rows.filter((r) => r.level === 'national')) } : {}),
    };
    return (
      <>
        <p>{tr('downloads_text')}</p>
        <div className="dl-grid">{Object.entries(sets).map(([k, get]) => (
          <button key={k} className="btn outline" onClick={() => downloadCsv(get(), `smartirrigate_${k}.csv`)}><Download size={15} /> {tr(`dl_${k}`)}</button>))}</div>
      </>
    );
  }
}

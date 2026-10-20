import { useState } from 'react';
import { useLocation } from 'react-router-dom';
import { Sprout, Workflow, TriangleAlert, Ruler, Bot, Download, ShieldAlert } from 'lucide-react';
import { useApp } from '../data/store';
import { DataTable, RelBadge, Tabs, type Col } from '../components/ui';
import { downloadCsv } from '../lib/stats';
import { SOURCES, provColumns, pubSrc, type Prov, type SrcId } from '../lib/sources';
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
  const { D, tr, dataSource } = useApp();
  // the Overview's "Limits" step opens this page on the Limitations tab
  const loc = useLocation();
  const [tab, setTab] = useState(() => ((loc.state as { tab?: string } | null)?.tab ?? 'about'));
  const tabs = [
    { id: 'about', label: tr('t_about'), icon: Sprout }, { id: 'limits', label: tr('t_limits'), icon: ShieldAlert }, { id: 'pipeline', label: tr('t_pipeline'), icon: Workflow },
    { id: 'traps', label: tr('t_traps'), icon: TriangleAlert }, { id: 'kpi', label: tr('t_kpi'), icon: Ruler },
    { id: 'ai', label: tr('t_ai'), icon: Bot }, { id: 'downloads', label: tr('t_downloads'), icon: Download },
  ];
  return (
    <section className="card pad prose">
      <Tabs tabs={tabs} active={tab} onChange={setTab} />
      {tab === 'about' && <About />}
      {tab === 'limits' && <><p>{tr('lim_intro')}</p><ol className="limits">{[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map((i) => <li key={i}>{tr(`lim_${i}`)}</li>)}</ol></>}
      {tab === 'pipeline' && <ol className="pipeline">{[1, 2, 3, 4, 5, 6, 7].map((i) => <li key={i}><strong>{tr(`pipe_${i}_t`)}</strong> {tr(`pipe_${i}`)}</li>)}</ol>}
      {tab === 'traps' && <Traps />}
      {tab === 'kpi' && <KpiDefs />}
      {tab === 'ai' && <><p>{tr('ai_text')}</p><ul>{[1, 2, 3, 4].map((i) => <li key={i}>{tr(`ai_${i}`)}</li>)}</ul></>}
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
          <p><RelBadge r="Unreliable" /> {tr('rel_unreliable')}</p><p><RelBadge r="Not assessed" /> {tr('rel_not_assessed')}</p>
          <p><RelBadge r="Published" /> {tr('rel_published')}</p>
          <p className="muted">{tr('disclaimer')}</p>
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
    const P = D.meta.published;
    const nm: Record<string, string> = { irrig_any_farmer: 'ind_irrig_any_farmer', inorganic_fert: 'ind_inorganic_fert', organic_fert: 'ind_organic_fert', pesticide: 'ind_pesticide', cultivated_area_ha: 'pub_cultivated', modern_irrig_area_ha: 'pub_modern_area', modern_irrig_share: 'def_nisr_modern', irrig_dsp_nisr: 'def_dsp' };
    const h = P.headline.filter((r) => r.indicator in nm).map((r) => ({ i: r.indicator, s: `${r.sas_year}${r.sas_season}`, v: r.unit === '%' ? fmtPct(r.value) : `${fmtNum(r.value)} ha` }));
    // drip + sprinkler + pivot: summed by the team from the NISR irrigation-type table, kept apart from the survey's "modern tools" series
    D.est.filter((r) => r.level === 'national' && r.indicator === 'irrig_dsp_nisr' && r.source === 'nisr').forEach((r) => h.push({ i: 'irrig_dsp_nisr', s: `${r.sas_year}${r.sas_season}`, v: fmtPct(r.estimate) }));
    const off = D.meta.official ?? [];
    const seas = [...new Set(h.map((r) => r.s))].sort(), inds = [...new Set(h.map((r) => r.i))];
    const big = P.production_alignment.filter((r) => Math.abs(r.survey_vs_published_pct) >= 10).sort((a, b) => a.season.localeCompare(b.season) || a.crop_name.localeCompare(b.crop_name));
    return (
      <>
        <p>{tr('kpi_rule')}</p>
        <table className="ptable"><thead><tr><th>KPI</th><th>{tr('definition')}</th></tr></thead>
          <tbody>{k.map((x) => <tr key={x}><td><strong>{tr(`kd_${x}_n`)}</strong></td><td>{tr(`kd_${x}`)}</td></tr>)}</tbody></table>
        <h5>{tr('pub_title')}</h5><p className="muted">{tr('pub_note')}</p>
        <table className="ptable"><thead><tr><th>{tr('indicator')}</th>{seas.map((s) => <th key={s}>{s}</th>)}</tr></thead>
          <tbody>{inds.map((i) => <tr key={i}><td>{tr(nm[i])}</td>{seas.map((s) => <td key={s}>{h.find((r) => r.i === i && r.s === s)?.v ?? '–'}</td>)}</tr>)}</tbody></table>
        {off.length > 0 && <>
          <h5>{tr('off_title')}</h5><p className="muted">{tr('off_note')}</p>
          <DataTable rows={off} pageSize={15} csvName="smartirrigate_nisr_published_figures.csv" caption={tr('off_title')}
            cols={[
              { key: 'season', label: tr('season'), get: (r) => `${r.sas_year}${r.sas_season}` },
              { key: 'ind', label: tr('indicator'), get: (r) => r.note ?? r.indicator },
              { key: 'value', label: tr('value'), get: (r) => r.value, render: (r) => `${fmtNum(r.value, 2)}${r.unit === '%' ? '%' : ` ${r.unit}`}`, num: true },
              { key: 'den', label: tr('recon_def_unit'), get: (r) => r.denominator },
              { key: 'pub', label: tr('src_source').replace(':', ''), get: (r) => `${r.publication}, ${r.table_or_section}`, render: (r) => <a href={r.url} target="_blank" rel="noopener noreferrer">{r.publication}, {r.table_or_section}</a> },
              { key: 'acc', label: tr('accessed'), get: (r) => r.accessed },
            ]} />
        </>}
        <h5>{tr('pub_align_title')}</h5><p className="muted">{tr('pub_align_note')}</p>
        <table className="ptable"><thead><tr><th>{tr('season')}</th><th>{tr('pub_survey')}</th><th>{tr('pub_published')}</th><th>{tr('pub_diff')}</th></tr></thead>
          <tbody>{P.totals_alignment.map((a) => <tr key={a.season}><td>{a.season}</td><td>{fmtNum(a.survey_t / 1000)} kt</td><td>{fmtNum(a.published_t / 1000)} kt</td><td>{a.survey_vs_published_pct}%</td></tr>)}</tbody></table>
        {big.length > 0 && <p className="muted">{tr('pub_align_crops', big.map((c) => `${c.crop_name} ${c.season} (${c.survey_vs_published_pct}%)`).join(', '))}</p>}
        <h5>{tr('bench_title')}</h5><p className="muted">{tr('bench_note')}</p>
        <table className="ptable"><tbody>{D.meta.benchmarks.map((b) => (
          <tr key={b.key}><td>{tr(`bench_${b.key}`)}</td><td><strong>{b.unit === 'ha' ? `${fmtNum(b.value)} ha` : fmtPct(b.value)}</strong></td><td>{b.period}</td>
            <td><a href={b.url} target="_blank" rel="noopener">{b.source}</a></td></tr>))}</tbody></table>
      </>
    );
  }

  function Downloads() {
    type Row = Record<string, unknown>;
    // published production and areas for 2024B–2026B come from the 2026 workbooks (SCRIPTS/11_NISR_Published_Tables.R)
    const PUB_2026: SrcId[] = ['sas2026a', 'sas2026b'];
    // every row says what it is and where it comes from (published rows link to their own NISR table)
    const withProv = (rows: unknown[], p: Prov) => (rows as Row[]).map((r) => ({ ...r, ...provColumns(p, tr(`kind_${p.kind}`)) }));
    const perRow = (rows: unknown[], isPub: (r: Row) => boolean, pubFrom: (r: Row) => SrcId[], survey: Prov) => (rows as Row[]).map((r) => {
      if (!isPub(r)) return { ...r, ...provColumns(survey, tr(`kind_${survey.kind}`)) };
      const src = pubFrom(r);
      return { ...r, estimate_type: tr('kind_official'), source: src.map((s) => SOURCES[s].title).join('; '), source_url: src.map((s) => SOURCES[s].url).join(' '), caveat: '' };
    });
    const sv = (unit: string, note?: string): Prov => ({ unit: tr(unit), period: '2019–2025', kind: 'survey', src: ['sas_micro'], note });
    const sets: Record<string, () => Row[]> = {
      est_plot: () => perRow(D.est, (r) => r.source === 'nisr', (r) => pubSrc(`${r.sas_year}${r.sas_season}`), sv('u_ha_t', tr('n_irrig_def'))),
      totals: () => perRow(D.totals, (r) => r.totals_source === 'nisr', () => PUB_2026, sv('u_ha_t', tr('n_area'))),
      crop_season: () => perRow(D.crop, (r) => r.production_source === 'nisr', () => PUB_2026, sv('u_ha_t', tr('n_yield_excl'))),
      priority_screening: () => withProv(D.screen.table, { unit: tr('u_score'), period: '2023–2025', kind: 'derived', src: ['screen', 'sas_micro', 'chirps'], note: `${tr('n_screen')} ${tr('n_sens')}` }),
      need_adoption: () => withProv(D.rain.district, { unit: tr('u_need'), period: '1981–2025', kind: 'derived', src: ['chirps', 'sas_micro'], note: tr('n_rain') }),
      yield_adjusted: () => withProv(D.model_yield.table, { unit: tr('u_yield_diff'), period: '2019–2025', kind: 'model', src: ['model', 'sas_micro'], note: `${tr('n_assoc')} ${tr('n_yield_excl')}` }),
      model_validation: () => withProv(D.model.performance, { unit: tr('u_auc'), period: '2024–2025', kind: 'model', src: ['model', 'sas_micro'], note: tr('n_model_ci') }),
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

import { useMemo } from 'react';
import { Users, MapPinned } from 'lucide-react';
import type { Data } from 'plotly.js';
import { useApp } from '../data/store';
import { ChartCard, FiltersUsed, Grid, relLabel } from '../components/ui';
import type { Prov } from '../lib/sources';
import { Plot, simpleLines, std, type Fig } from '../components/Plot';
import { fmtNum, fmtPct } from '../lib/format';
import { brand } from '../lib/theme';

const DIMS = ['gender', 'age_band', 'plot_size', 'erosion', 'consolidated'];
const DCOL: Record<string, string> = { gender: '#0F7044', age_band: '#1976B9', plot_size: '#B07A1C', erosion: '#B65F47', consolidated: '#6A4C93' };
const GC: Record<string, string> = { Female: '#B07A1C', Male: '#1976B9' };

export default function Who() {
  const { D, f, tr } = useApp();
  const eq = useMemo(() => D.equity.equity.filter((r) => DIMS.includes(r.dimension))
    .map((r) => ({ ...r, lbl: `${tr(`dim_${r.dimension}`)}: ${r.group}` }))
    .sort((a, b) => DIMS.indexOf(a.dimension) - DIMS.indexOf(b.dimension) || a.estimate - b.estimate), [D, tr]);
  const eqFig = useMemo<Fig>(() => ({
    data: [{ type: 'bar', orientation: 'h', y: eq.map((r) => r.lbl), x: eq.map((r) => r.estimate), marker: { color: eq.map((r) => DCOL[r.dimension]) },
      hovertext: eq.map((r) => `${r.lbl}<br><b>${fmtPct(r.estimate)}</b> (95% CI ${fmtPct(r.ci_low)}–${fmtPct(r.ci_high)})<br>n = ${fmtNum(r.n)} · ${r.reliability}`), hoverinfo: 'text',
      text: eq.map((r) => fmtPct(r.estimate)), textposition: 'outside', cliponaxis: false, textfont: { size: 11, color: brand.ink } }],
    layout: std({ x: tr('x_pct_plots'), legend: false, bargap: 0.3, yaxis: { title: { text: '' }, tickfont: { size: 11 }, categoryorder: 'array', categoryarray: [...eq.map((r) => r.lbl)].reverse() },
      xaxis: { range: [0, Math.max(...eq.map((r) => r.estimate)) * 1.2] } }),
  }), [eq, tr]);
  const g = (dim: string, grp: string) => eq.find((r) => r.dimension === dim && r.group === grp)?.estimate;

  const gt = D.equity.equity.filter((r) => r.dimension === 'gender_trend' && f.years.includes(r.sas_year!));
  const gtFig = useMemo<Fig | null>(() => {
    if (!gt.length) return null;
    const data: Data[] = ['Female', 'Male'].map((s) => { const x = gt.filter((r) => r.group === s).sort((a, b) => a.sas_year! - b.sas_year!); return {
      type: 'scatter', mode: 'lines+markers', name: tr(s.toLowerCase()), x: x.map((r) => r.sas_year), y: x.map((r) => r.estimate), line: { color: GC[s], shape: 'spline', smoothing: 0.5 }, marker: { color: GC[s] },
      text: x.map((r) => `${tr(s.toLowerCase())} ${r.sas_year}: ${fmtPct(r.estimate)}<br>n = ${fmtNum(r.n)}`), hoverinfo: 'text' } as Data; });
    return simpleLines(data, std({ y: tr('y_pct_plots_ab'), xaxis: { dtick: 1 } }));
  }, [gt, tr]);
  const gtYears = [...new Set(gt.map((r) => r.sas_year!))];
  const maleAhead = gtYears.filter((y) => (gt.find((r) => r.sas_year === y && r.group === 'Male')?.estimate ?? 0) > (gt.find((r) => r.sas_year === y && r.group === 'Female')?.estimate ?? 0)).length;

  const gd = D.equity.gender_district.filter((r) => f.districts.includes(r.district_std));
  const w = useMemo(() => [...new Set(gd.map((r) => r.district_std))].map((d) => ({ d, F: gd.find((r) => r.district_std === d && r.gender === 'Female')?.estimate ?? NaN, M: gd.find((r) => r.district_std === d && r.gender === 'Male')?.estimate ?? NaN })).sort((a, b) => a.M - b.M), [gd]);
  const gdFig = useMemo<Fig | null>(() => {
    if (!gd.length) return null;
    return {
      data: [
        ...w.map((r) => ({ type: 'scatter', mode: 'lines', x: [r.F, r.M], y: [r.d, r.d], line: { color: '#D5DBD7', width: 4 }, hoverinfo: 'skip', showlegend: false })),
        ...['Female', 'Male'].map((s) => { const x = gd.filter((r) => r.gender === s); return { type: 'scatter', mode: 'markers', name: tr(s.toLowerCase()), x: x.map((r) => r.estimate), y: x.map((r) => r.district_std),
          marker: { size: 11, color: GC[s], symbol: x.map((r) => (r.reliability === 'Unreliable' ? 'circle-open' : 'circle')), line: { color: x.map((r) => (r.reliability === 'Unreliable' ? GC[s] : '#fff')), width: 1.5 } },
          text: x.map((r) => `${r.district_std} · ${s}: ${fmtPct(r.estimate)}<br>n = ${fmtNum(r.n)} · ${r.reliability}`), hoverinfo: 'text' }; }),
      ] as Data[],
      layout: std({ x: tr('x_pct_plots_2325'), yaxis: { title: { text: '' }, tickfont: { size: 10.5 }, categoryorder: 'array', categoryarray: w.map((r) => r.d) } }),
    };
  }, [gd, w, tr]);
  const gaps = w.map((r) => ({ ...r, gap: r.M - r.F })).filter((r) => Number.isFinite(r.gap)).sort((a, b) => b.gap - a.gap);
  const sp = (unit: string, period: string, note?: string): Prov => ({ unit: tr(unit), period, kind: 'survey', src: ['sas_micro'], note: [tr('n_who_desc'), note].filter(Boolean).join(' ') });
  type E = { estimate: number; ci_low?: number | null; ci_high?: number | null; n: number; reliability: string };
  const eCols = [
    { label: '%', get: (r: E) => fmtPct(r.estimate), num: true }, { label: '95% CI', get: (r: E) => (r.ci_low == null ? null : `${fmtPct(r.ci_low)}–${fmtPct(r.ci_high)}`), num: true },
    { label: 'n', get: (r: E) => fmtNum(r.n), num: true }, { label: tr('quality'), get: (r: E) => relLabel(tr, r.reliability) },
  ];

  return (
    <>
      <FiltersUsed used={['years', 'area']} />
      <Grid cols="1fr 1fr">
        <ChartCard title={tr('c_equity')} icon={Users}
          means={tr('m_equity', fmtPct(g('gender', 'Female')), fmtPct(g('gender', 'Male')), fmtPct(g('consolidated', 'In consolidated site')), fmtPct(g('consolidated', 'Not consolidated')))}
          prov={sp('u_pct_plots', '2023–2025')}
          table={{ name: 'irrigation_by_group', rows: eq, cols: [{ label: tr('group'), get: (r: { lbl: string }) => r.lbl }, ...eCols] }}>
          <Plot fig={eqFig} height={400} />
        </ChartCard>
        <ChartCard title={tr('c_gender_trend')} icon={Users} means={gtYears.length ? tr('m_gender_trend', maleAhead, gtYears.length) : null}
          prov={sp('u_pct_plots_ab', gtYears.length ? `${Math.min(...gtYears)}–${Math.max(...gtYears)}` : '')}
          table={{ name: 'irrigation_by_gender_year', rows: [...gt].sort((a, b) => a.sas_year! - b.sas_year! || a.group.localeCompare(b.group)), cols: [
            { label: tr('year'), get: (r: { sas_year?: number | null }) => r.sas_year ?? null }, { label: tr('group'), get: (r: { group: string }) => tr(r.group.toLowerCase()) }, ...eCols] }}>
          <Plot fig={gtFig} height={400} empty={tr('no_data')} />
        </ChartCard>
      </Grid>
      <ChartCard title={tr('c_gender_district')} icon={MapPinned}
        means={gaps.length ? <>{tr('m_gender_district', gaps.filter((r) => r.gap > 0).length, gaps.length, gaps.slice(0, 3).map((r) => r.d).join(', '))} {tr('m_open_unreliable')}</> : null}
        prov={sp('u_pct_plots', '2023–2025', tr('n_district_small'))}
        table={{ name: 'irrigation_by_gender_district', rows: [...gd].sort((a, b) => a.district_std.localeCompare(b.district_std) || a.gender.localeCompare(b.gender)), cols: [
          { label: tr('district'), get: (r: { district_std: string }) => r.district_std }, { label: tr('group'), get: (r: { gender: string }) => tr(r.gender.toLowerCase()) }, ...eCols] }}>
        <Plot fig={gdFig} height={Math.max(300, 22 * w.length + 80)} empty={tr('no_data')} />
      </ChartCard>
    </>
  );
}

import { useMemo } from 'react';
import { Users, MapPinned } from 'lucide-react';
import type { Data } from 'plotly.js';
import { useApp } from '../data/store';
import { ChartCard, FiltersUsed, Grid } from '../components/ui';
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

  return (
    <>
      <FiltersUsed used={['years', 'area']} />
      <Grid cols="1fr 1fr">
        <ChartCard title={tr('c_equity')} icon={Users} source={tr('period_pooled', '2023–2025, Seasons A+B')}
          table={{ cols: [tr('group'), tr('ind_irrigated'), 'n'], rows: eq.map((r) => [r.lbl, fmtPct(r.estimate), r.n]) }}
          means={tr('m_equity', fmtPct(g('gender', 'Female')), fmtPct(g('gender', 'Male')), fmtPct(g('consolidated', 'In consolidated site')), fmtPct(g('consolidated', 'Not consolidated')))}>
          <Plot fig={eqFig} height={400} />
        </ChartCard>
        <ChartCard title={tr('c_gender_trend')} icon={Users} means={gtYears.length ? tr('m_gender_trend', maleAhead, gtYears.length) : null}>
          <Plot fig={gtFig} height={400} empty={tr('no_data')} />
        </ChartCard>
      </Grid>
      <ChartCard title={tr('c_gender_district')} icon={MapPinned} source={tr('src_plots', 'A+B', '2023–2025', tr('n_districts', gd.length / 2 | 0))}
        means={gaps.length ? <>{tr('m_gender_district', gaps.filter((r) => r.gap > 0).length, gaps.length, gaps.slice(0, 3).map((r) => r.d).join(', '))} {tr('m_open_unreliable')}</> : null}>
        <Plot fig={gdFig} height={Math.max(300, 22 * w.length + 80)} empty={tr('no_data')} />
      </ChartCard>
    </>
  );
}

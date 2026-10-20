import { useMemo, useState } from 'react';
import { Info, Layers, ChartColumn, Coins, Waves, MapPinned } from 'lucide-react';
import type { Data } from 'plotly.js';
import { useApp } from '../data/store';
import { Callout, ChartCard, FiltersUsed, Grid, Select } from '../components/ui';
import { Plot, simpleLines, std, legendBottom, narrow, type Fig } from '../components/Plot';
import { groupBy, mean, sum, wm } from '../lib/stats';
import { fmtNum, fmtPct } from '../lib/format';
import { catCols, colIrrigated, extraCols } from '../lib/theme';

const DIMS = ['irrig_tool_level', 'irrig_technique', 'irrig_source'];

export default function How() {
  const { D, f, tr } = useApp();
  const [dim, setDim] = useState('irrig_tool_level');
  const Y = new Set(f.years), S = new Set<string>(f.seasons);

  // the selected seasons pooled into one share per year (weighted plot counts)
  const mix = useMemo(() => {
    const d = D.tech.mix.filter((r) => r.period == null && r.dimension === dim && Y.has(r.sas_year) && S.has(r.sas_season));
    const out: { y: number; cat: string; share: number; n: number; nGroup: number }[] = [];
    for (const g of groupBy(d, (r) => String(r.sas_year)).values()) {
      const W = sum(g.map((r) => r.w)), nG = sum(g.map((r) => r.n));
      for (const c of groupBy(g, (r) => r.category).values()) out.push({ y: g[0].sas_year, cat: c[0].category, share: (100 * sum(c.map((r) => r.w))) / W, n: sum(c.map((r) => r.n)), nGroup: nG });
    }
    return out;
  }, [D, dim, f]); // eslint-disable-line
  const mixFig = useMemo<Fig | null>(() => {
    if (!mix.length) return null;
    const cats = [...new Set(mix.map((r) => r.cat))].sort(), cols = catCols(cats);
    return {
      data: cats.map((c) => { const x = mix.filter((r) => r.cat === c).sort((a, b) => a.y - b.y); return {
        type: 'bar', name: c, x: x.map((r) => String(r.y)), y: x.map((r) => r.share), marker: { color: cols[c] },
        text: x.map((r) => `${r.y} · ${c}: ${fmtPct(r.share)}<br>${tr('irrigated_plots_n')} ${fmtNum(r.nGroup)}`), hoverinfo: 'text', textposition: 'none' } as Data; }),
      layout: std({ y: tr('y_share_irrigated'), barmode: 'group', bargap: 0.22, xaxis: { title: { text: '' }, tickangle: -45, type: 'category' }, yaxis: { ticksuffix: '%' },
        legend: narrow() ? legendBottom(-0.3) : { orientation: 'v', x: 1.02, xanchor: 'left', y: 0.5, yanchor: 'middle', font: { size: 11 } } }),
    };
  }, [mix, tr]);
  const mixTop = [...groupBy(mix, (r) => r.cat).values()].map((g) => ({ c: g[0].cat, s: wm(g.map((r) => r.share), g.map((r) => r.nGroup)) })).sort((a, b) => b.s - a.s);
  const small = mix.filter((r) => r.nGroup < 100).length;
  const oth = D.tech.other_share.filter((r) => r.dimension === dim && Y.has(r.sas_year)).map((r) => r.other_pct);

  const cost = D.tech.cost;
  const costFig = useMemo<Fig>(() => {
    const ys = cost.map((r) => r.irrig_tool_level);
    return {
      data: [
        ...cost.map((r) => ({ type: 'scatter', mode: 'lines', x: [r.p25 / 1000, r.p75 / 1000], y: [r.irrig_tool_level, r.irrig_tool_level], line: { color: '#9DB8A9', width: 10 }, hoverinfo: 'skip', showlegend: false })),
        { type: 'scatter', mode: 'markers', x: cost.map((r) => r.median / 1000), y: ys, marker: { color: colIrrigated, size: 13, symbol: 'line-ns', line: { width: 3, color: colIrrigated } }, showlegend: false,
          text: cost.map((r) => `${r.irrig_tool_level}<br>${tr('median')}: ${fmtNum(r.median / 1000)}k RWF/ha<br>${tr('iqr')}: ${fmtNum(r.p25 / 1000)}k–${fmtNum(r.p75 / 1000)}k<br>n = ${fmtNum(r.n)}`), hoverinfo: 'text' },
      ] as Data[],
      layout: std({ x: tr('x_cost'), legend: false, yaxis: { title: { text: '' }, categoryorder: 'array', categoryarray: [...ys].reverse() } }),
    };
  }, [cost, tr]);
  const costS = [...cost].sort((a, b) => a.median - b.median);

  const src = useMemo(() => [...groupBy(D.tech.sources_any.filter((r) => Y.has(r.sas_year) && S.has(r.sas_season)), (r) => `${r.source}|${r.sas_year}`).values()]
    .map((g) => ({ s: g[0].source, y: g[0].sas_year, share: wm(g.map((r) => r.share), g.map((r) => r.n)), n: sum(g.map((r) => r.n)) })), [D, f]); // eslint-disable-line
  const srcCats = [...groupBy(src, (r) => r.s).values()].map((g) => ({ c: g[0].s, s: mean(g.map((r) => r.share)) })).sort((a, b) => b.s - a.s);
  const srcFig = useMemo<Fig | null>(() => {
    if (!src.length) return null;
    const data: Data[] = srcCats.map(({ c }, i) => { const x = src.filter((r) => r.s === c).sort((a, b) => a.y - b.y); return {
      type: 'scatter', mode: 'lines+markers', name: c, x: x.map((r) => r.y), y: x.map((r) => r.share), line: { color: extraCols[i % extraCols.length], shape: 'spline', smoothing: 0.5 },
      marker: { color: extraCols[i % extraCols.length] }, text: x.map((r) => `${c} ${r.y}: ${fmtPct(r.share)} · n = ${fmtNum(r.n)}`), hoverinfo: 'text' } as Data; });
    return simpleLines(data, std({ y: tr('y_share_irrigated'), xaxis: { dtick: 1 } }));
  }, [src, srcCats, tr]);

  const dist = useMemo(() => {
    const d = D.tech.mix.filter((r) => r.period === '2023-2025' && r.dimension === dim && f.districts.includes(r.district_std!));
    // clustered bars stay readable for up to 8 districts: the 8 with the most irrigated plots
    const keep = [...new Map(d.map((r) => [r.district_std!, r.n_group])).entries()].sort((a, b) => b[1] - a[1]).slice(0, 8);
    return { d: d.filter((r) => keep.some(([k]) => k === r.district_std)), ord: keep.map(([k]) => k), thin: keep.filter(([, n]) => n < 30).length };
  }, [D, dim, f.districts]);
  const distFig = useMemo<Fig | null>(() => {
    if (!dist.d.length) return null;
    const cats = [...new Set(dist.d.map((r) => r.category))].sort(), cols = catCols(cats);
    return {
      data: cats.map((c) => { const x = dist.d.filter((r) => r.category === c); return {
        type: 'bar', name: c, x: x.map((r) => r.district_std), y: x.map((r) => r.share), marker: { color: cols[c] },
        text: x.map((r) => `${r.district_std} · ${c}: ${fmtPct(r.share)}<br>${tr('irrigated_plots_n')} ${fmtNum(r.n_group)}`), hoverinfo: 'text', textposition: 'none' } as Data; }),
      layout: std({ y: tr('y_share_irrigated'), barmode: 'group', bargap: 0.22, xaxis: { title: { text: '' }, tickangle: -30, categoryorder: 'array', categoryarray: dist.ord }, yaxis: { ticksuffix: '%' }, legend: legendBottom(-0.25) }),
    };
  }, [dist, tr]);

  return (
    <>
      <FiltersUsed used={['years', 'seasons', 'area']} />
      <Callout icon={Info} kind="soft">{tr('how_intro')}</Callout>
      <div className="toolbar">
        <span className="tb-label"><Layers size={16} /> {tr('show_by')}</span>
        <Select value={dim} onChange={setDim} options={DIMS.map((d) => ({ value: d, label: tr(`dim_${d}`) }))} width={300} />
      </div>
      <Grid cols="7fr 5fr">
        <ChartCard title={tr('c_mix_trend')} icon={ChartColumn}
          means={mixTop.length ? <><p>{tr('m_mix', mixTop[0].c, fmtPct(mixTop[0].s, 0))}{small ? ` ${tr('m_mix_small')}` : ''}</p><p className="muted small">{tr('named_only', oth.length ? fmtPct(mean(oth), 0) : '–')}</p></> : null}>
          <Plot fig={mixFig} height={330} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('c_cost')} icon={Coins} source={tr('period_pooled', '2019–2025')}
          table={{ cols: [tr('c_cost'), 'p25', tr('median'), 'p75', 'n'], rows: cost.map((r) => [r.irrig_tool_level, Math.round(r.p25), Math.round(r.median), Math.round(r.p75), r.n]) }} means={costS.length ? tr('m_cost', costS[0].irrig_tool_level, fmtNum(costS[0].median / 1000), fmtNum(Math.max(...cost.map((r) => r.median)) / 1000)) : null}>
          <Plot fig={costFig} height={330} />
        </ChartCard>
      </Grid>
      <Grid cols="1fr 1fr">
        <ChartCard title={tr('c_sources_any')} icon={Waves} means={srcCats.length >= 2 ? tr('m_sources', srcCats[0].c, fmtPct(srcCats[0].s, 0), srcCats[1].c, fmtPct(srcCats[1].s, 0)) : null}>
          <Plot fig={srcFig} height={380} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('c_mix_district')} icon={MapPinned} means={dist.d.length ? <>{tr('m_mix_district')}{dist.thin ? ` ${tr('m_thin', dist.thin)}` : ''}</> : null}>
          <Plot fig={distFig} height={380} empty={tr('no_data')} />
        </ChartCard>
      </Grid>
    </>
  );
}

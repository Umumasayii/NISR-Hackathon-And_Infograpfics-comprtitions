import { useMemo, useState } from 'react';
import { Filter, Network, Trophy, ChartLine, Table2, Wheat, Sprout, Store, Scale, ListChecks } from 'lucide-react';
import type { Data } from 'plotly.js';
import { useApp } from '../data/store';
import { Callout, ChartCard, DataTable, FiltersUsed, Grid, Kpi, KpiRow, Select, type Col } from '../components/ui';
import { Plot, simpleLines, std, legendBottom, type Fig } from '../components/Plot';
import { cropsFor, groupBy, mean, sum, wm } from '../lib/stats';
import { fmtNum, fmtPct, shortSet } from '../lib/format';
import { brand, catCols, seasonCols } from '../lib/theme';
import type { Crop } from '../data/types';

const MEASURES = ['production_t', 'crop_area_ha', 'yield_kg_ha', 'yield_irrigated_kg_ha', 'yield_rainfed_kg_ha', 'sold_t', 'sold_share_pct', 'price_rwf_kg', 'sales_value_mrwf', 'improved_seed_pct'] as const;
type M = (typeof MEASURES)[number];
const SUMS: M[] = ['production_t', 'crop_area_ha', 'sold_t', 'sales_value_mrwf'];

type Agg = Record<M | 'n_irrigated_yield' | 'n_crop_plots', number>;
// sums for t/ha; ratios recomputed. A sum of nothing but missing values stays missing (2026 has no crop area)
const sumNA = (x: (number | null | undefined)[]) => (x.some((v) => Number.isFinite(v as number)) ? sum(x) : NaN);
function agg(d: Crop[]): Agg {
  const sum = sumNA;
  const production_t = sum(d.map((r) => r.production_t)), sold_t = sum(d.map((r) => r.sold_t));
  return {
    production_t, crop_area_ha: sum(d.map((r) => r.crop_area_ha)),
    yield_kg_ha: wm(d.map((r) => r.yield_kg_ha), d.map((r) => r.crop_area_ha)),
    yield_irrigated_kg_ha: wm(d.map((r) => r.yield_irrigated_kg_ha), d.map((r) => r.n_irrigated_yield)),
    yield_rainfed_kg_ha: wm(d.map((r) => r.yield_rainfed_kg_ha), d.map((r) => r.crop_area_ha)),
    sold_t, price_rwf_kg: wm(d.map((r) => r.price_rwf_kg), d.map((r) => r.sold_t)),
    sales_value_mrwf: sum(d.map((r) => r.sales_value_mrwf)), improved_seed_pct: wm(d.map((r) => r.improved_seed_pct), d.map((r) => r.crop_area_ha)),
    n_crop_plots: sum(d.map((r) => r.n_crop_plots)), n_irrigated_yield: sum(d.map((r) => r.n_irrigated_yield)),
    sold_share_pct: production_t ? (100 * sold_t) / production_t : NaN,
  };
}
const num = (x: number | string | null | undefined) => (typeof x === 'number' && Number.isFinite(x) ? x : NaN);

export default function Explorer() {
  const { D, f, tr } = useApp();
  const [m, setM] = useState<M>('production_t');
  const cr = useMemo(() => cropsFor(D, f), [D, f]);
  const grpCols = useMemo(() => catCols([...new Set(D.crop.map((r) => r.crop_group))].sort()), [D]);
  const label = f.crops.length ? shortSet(f.crops) : f.cropGroups.length ? shortSet(f.cropGroups) : tr('all_crops');
  const dec = m === 'sold_share_pct' || m === 'improved_seed_pct' ? 1 : 0;

  const k = useMemo(() => {
    if (!cr.length) return null;
    const ny = new Set(cr.map((r) => r.sas_year)).size, a = agg(cr);
    return { ny, a, nCrops: new Set(cr.map((r) => r.crop_name)).size };
  }, [cr]);

  const byCrop = useMemo(() => [...groupBy(cr, (r) => `${r.crop_group}|${r.crop_name}`).values()].map((g) => ({ crop_group: g[0].crop_group, crop_name: g[0].crop_name, ...agg(g) })), [cr]);
  const treeFig = useMemo<Fig | null>(() => {
    const tm: M = SUMS.includes(m) ? m : 'production_t';
    const d = byCrop.filter((r) => num(r[tm]) > 0);
    if (!d.length) return null;
    const g = [...groupBy(d, (r) => r.crop_group).entries()].map(([k2, x]) => ({ k: k2, v: sum(x.map((r) => num(r[tm]))) }));
    return {
      data: [{ type: 'treemap', ids: [...g.map((x) => x.k), ...d.map((r) => `${r.crop_group}/${r.crop_name}`)], labels: [...g.map((x) => x.k), ...d.map((r) => r.crop_name)],
        parents: [...g.map(() => ''), ...d.map((r) => r.crop_group)], values: [...g.map((x) => x.v), ...d.map((r) => num(r[tm]))], branchvalues: 'total',
        marker: { colors: [...g.map((x) => grpCols[x.k]), ...d.map((r) => grpCols[r.crop_group])], line: { color: '#fff', width: 2 } },
        textinfo: 'label+percent root', hovertemplate: `<b>%{label}</b><br>${tr(`ms_${tm}`)}: %{value:,.0f}<br>%{percentRoot:.1%} <extra></extra>`,
        textfont: { color: '#FFFFFF', size: 13 }, pathbar: { visible: true, textfont: { size: 12 } } } as unknown as Data],
      layout: { margin: { l: 0, r: 0, t: 24, b: 0 }, paper_bgcolor: 'rgba(0,0,0,0)' },
    };
  }, [byCrop, m, grpCols, tr]);

  const top = useMemo(() => byCrop.filter((r) => Number.isFinite(num(r[m])) && r.n_crop_plots >= 30).sort((a, b) => num(b[m]) - num(a[m])), [byCrop, m]);
  const barFig = useMemo<Fig | null>(() => {
    const d = top.slice(0, 15).reverse(); if (!d.length) return null;
    const grps = [...new Set(d.map((r) => r.crop_group))];
    return {
      data: grps.map((g) => { const x = d.filter((r) => r.crop_group === g); return {
        type: 'bar', orientation: 'h', name: g, y: x.map((r) => r.crop_name), x: x.map((r) => num(r[m])), marker: { color: grpCols[g] },
        text: x.map((r) => `<b>${r.crop_name}</b> (${g})<br>${tr(`ms_${m}`)}: ${fmtNum(num(r[m]), dec)}<br>n = ${fmtNum(r.n_crop_plots)}`), hoverinfo: 'text', textposition: 'none' } as Data; }),
      layout: std({ x: tr(`ms_${m}`), legend: legendBottom(-0.25), bargap: 0.3, yaxis: { title: { text: '' }, tickfont: { size: 11 }, categoryorder: 'array', categoryarray: d.map((r) => r.crop_name) } }),
    };
  }, [top, m, grpCols, dec, tr]);

  const trendD = useMemo(() => [...groupBy(cr, (r) => `${r.sas_year}|${r.sas_season}`).values()].map((g) => ({ y: g[0].sas_year, s: g[0].sas_season, ...agg(g) })).filter((r) => Number.isFinite(num(r[m]))), [cr, m]);
  const trendFig = useMemo<Fig | null>(() => {
    if (!trendD.length) return null;
    const data: Data[] = ['A', 'B', 'C'].map((s) => { const x = trendD.filter((r) => r.s === s).sort((a, b) => a.y - b.y); return x.length ? {
      type: 'scatter', mode: 'lines+markers', name: tr(`season_${s.toLowerCase()}`), x: x.map((r) => r.y), y: x.map((r) => num(r[m])),
      line: { color: seasonCols[s], shape: 'spline', smoothing: 0.5 }, marker: { color: seasonCols[s] }, text: x.map((r) => `${r.y}${s}: ${fmtNum(num(r[m]), 1)}`), hoverinfo: 'text' } as Data : null; }).filter(Boolean) as Data[];
    return simpleLines(data, std({ y: tr(`ms_${m}`), xaxis: { dtick: 1 } }));
  }, [trendD, m, tr]);
  const trendMeans = (() => {
    const d = trendD.filter((r) => r.s !== 'C'); const ys = d.map((r) => r.y);
    if (new Set(ys).size < 2) return null;
    const a = mean(d.filter((r) => r.y === Math.min(...ys)).map((r) => num(r[m]))), b = mean(d.filter((r) => r.y === Math.max(...ys)).map((r) => num(r[m])));
    const ch = 100 * (b / a - 1);
    return <>{tr('m_measure_trend', tr(`ms_${m}`), Math.min(...ys), Math.max(...ys), `${ch > 0 ? '+' : ''}${fmtNum(ch, 0)}%`)} {tr('m_measure_caveat')}</>;
  })();

  const table = useMemo(() => [...groupBy(cr, (r) => `${r.sas_year}|${r.sas_season}|${r.crop_group}|${r.crop_name}`).values()]
    .map((g) => ({ sas_year: g[0].sas_year, sas_season: g[0].sas_season, crop_group: g[0].crop_group, crop_name: g[0].crop_name, ...agg(g) }))
    .sort((a, b) => b.sas_year - a.sas_year || a.sas_season.localeCompare(b.sas_season) || num(b.production_t) - num(a.production_t)), [cr]);
  type Row = (typeof table)[number];
  const r1 = (x: number | string | null) => { const v = num(x); return Number.isFinite(v) ? Math.round(v * 10) / 10 : null; };
  const cols: Col<Row>[] = [
    { key: 'y', label: tr('year'), get: (r) => r.sas_year, num: true }, { key: 's', label: tr('season'), get: (r) => r.sas_season },
    { key: 'g', label: tr('crop_group'), get: (r) => r.crop_group }, { key: 'c', label: tr('crop'), get: (r) => r.crop_name },
    { key: 'n', label: 'n', get: (r) => r.n_crop_plots, num: true },
    ...MEASURES.map((x) => ({ key: x, label: tr(`ms_${x}`), get: (r: Row) => r1(r[x]), num: true, render: (r: Row) => fmtNum(num(r[x]), x.endsWith('pct') ? 1 : 0) })),
  ];

  return (
    <>
      <FiltersUsed used={['years', 'seasons', 'area', 'crop']} />
      <Callout icon={Filter} kind="soft">{tr('explorer_intro')}</Callout>
      {k ? (
        <KpiRow>
          <Kpi label={tr('ms_production_t')} value={`${fmtNum(num(k.a.production_t) / k.ny / 1000)} kt`} icon={Wheat} color="#B07A1C" foot={tr('k_per_year', label, f.area)} />
          <Kpi label={tr('ms_crop_area_ha')} value={`${fmtNum(num(k.a.crop_area_ha) / k.ny / 1000, 1)}k ha`} icon={Sprout} color={brand.green} foot={tr('k_per_year', label, f.area)} />
          <Kpi label={tr('ms_sold_share_pct')} value={fmtPct(num(k.a.sold_share_pct))} icon={Store} color={brand.blue} foot={tr('k_sold_sub', fmtNum(num(k.a.sold_t) / k.ny / 1000), fmtNum(num(k.a.sales_value_mrwf) / k.ny / 1000, 1))} />
          {f.crops.length === 1
            ? <Kpi label={tr('ms_yield_kg_ha')} value={`${fmtNum(num(k.a.yield_kg_ha))} kg/ha`} icon={Scale} color="#6A4C93" foot={tr('k_yield_sub', fmtNum(k.a.n_crop_plots))} />
            : <Kpi label={tr('k_n_crops')} value={String(k.nCrops)} icon={ListChecks} color="#6A4C93" foot={tr('k_n_crops_sub')} />}
        </KpiRow>
      ) : <p className="muted">{tr('no_data')}</p>}
      <div className="toolbar">
        <Select label={tr('c_top_crops')} value={m} onChange={setM} options={MEASURES.map((x) => ({ value: x, label: tr(`ms_${x}`) }))} width={320} />
      </div>
      <ChartCard title={tr('c_treemap')} icon={Network} means={tr('m_tree')}><Plot fig={treeFig} height={360} empty={tr('no_data')} /></ChartCard>
      <div style={{ height: 16 }} />
      <Grid cols="1fr 1fr">
        <ChartCard title={tr('c_top_crops')} icon={Trophy}
          means={top.length ? <>{tr('m_bycrop', top[0].crop_name, tr(`ms_${m}`))}{SUMS.includes(m) ? tr('m_bycrop_share', fmtPct((100 * num(top[0][m])) / sum(top.map((r) => num(r[m]))), 0)) : ''} {tr('m_bycrop_note')}</> : null}>
          <Plot fig={barFig} height={380} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('c_measure_trend')} icon={ChartLine} means={trendMeans}><Plot fig={trendFig} height={380} empty={tr('no_data')} /></ChartCard>
      </Grid>
      <ChartCard title={tr('c_table')} icon={Table2}>
        <DataTable rows={table} cols={cols} csvName={`smartirrigate_crops_${f.area.replace(/\W+/g, '_')}.csv`} />
      </ChartCard>
    </>
  );
}

import { useMemo, useState } from 'react';
import { Filter, Trophy, ChartLine, Table2, Store, Scale, ListChecks, BookOpen, Calculator } from 'lucide-react';
import type { Data } from 'plotly.js';
import { useApp } from '../data/store';
import { Callout, ChartCard, DataTable, FiltersUsed, Grid, Kpi, KpiRow, SectionTitle, Select, type Col } from '../components/ui';
import { citeShort, cite, pubArea, pubCsv, pubSource, seasonsOf, splitAtUpgrade, ysKey, type YS } from '../lib/official';
import { Plot, simpleLines, std, legendBottom, type Fig } from '../components/Plot';
import { cropsFor, downloadCsv, groupBy, mean, sum, yieldOf } from '../lib/stats';
import { fmtNum, fmtPct, shortSet } from '../lib/format';
import { brand, catCols, seasonCols } from '../lib/theme';
import type { AppData, Crop, PubRow } from '../data/types';

const MEASURES = ['production_t', 'crop_area_ha', 'yield_kg_ha', 'yield_irrigated_kg_ha', 'yield_rainfed_kg_ha', 'sold_t', 'sold_share_pct', 'price_rwf_kg', 'sales_value_mrwf', 'improved_seed_pct'] as const;
// NISR publishes production, harvested area and yield by crop: those come from NISR (above).
// Our microdata section keeps only what NISR does not publish (sales, prices, irrigated vs rain-fed yield).
const OUR_ONLY = ['sold_share_pct', 'price_rwf_kg', 'sales_value_mrwf', 'sold_t', 'yield_irrigated_kg_ha', 'yield_rainfed_kg_ha', 'improved_seed_pct'] as const;
const PUB_M = ['production_t', 'harvested_crop_ha', 'yield_kg_ha'] as const;
type M = (typeof MEASURES)[number];
const SUMS: M[] = ['production_t', 'crop_area_ha', 'sold_t', 'sales_value_mrwf'];

type Agg = Record<M | 'n_irrigated_yield' | 'n_crop_plots', number> & { yield_exact: boolean };
// sums for t and ha; ratios recomputed from sums. A sum of nothing but missing values stays missing.
// Yields come from yieldOf (summed harvest / summed eligible area, unusable seasons left out);
// a share without its denominator (improved seed) is shown for one row only, never averaged.
const sumNA = (x: (number | null | undefined)[]) => (x.some((v) => Number.isFinite(v as number)) ? sum(x) : NaN);
function agg(D: AppData, d: Crop[]): Agg {
  const sum = sumNA;
  const production_t = sum(d.map((r) => r.production_t)), sold_t = sum(d.map((r) => r.sold_t)), value = sum(d.map((r) => r.sales_value_mrwf));
  const y = yieldOf(D, d);
  return {
    production_t, crop_area_ha: sum(d.map((r) => r.crop_area_ha)),
    yield_kg_ha: y.all, yield_irrigated_kg_ha: y.irr, yield_rainfed_kg_ha: y.rf, yield_exact: y.exact,
    sold_t, price_rwf_kg: sold_t > 0 ? (1e6 * value) / (1000 * sold_t) : NaN,
    sales_value_mrwf: value, improved_seed_pct: d.length === 1 ? d[0].improved_seed_pct ?? NaN : NaN,
    n_crop_plots: sum(d.map((r) => r.n_crop_plots)), n_irrigated_yield: y.nIrr,
    sold_share_pct: production_t ? (100 * sold_t) / production_t : NaN,
  };
}
const num = (x: number | string | null | undefined) => (typeof x === 'number' && Number.isFinite(x) ? x : NaN);

export default function Explorer() {
  const { D, f, tr } = useApp();
  const [m, setM] = useState<M>('sold_share_pct');
  const cr = useMemo(() => cropsFor(D, f), [D, f]);
  const grpCols = useMemo(() => catCols([...new Set(D.crop.map((r) => r.crop_group))].sort()), [D]);
  const label = f.crops.length ? shortSet(f.crops) : f.cropGroups.length ? shortSet(f.cropGroups) : tr('all_crops');
  const dec = m === 'sold_share_pct' || m === 'improved_seed_pct' ? 1 : 0;

  const k = useMemo(() => {
    if (!cr.length) return null;
    const ny = new Set(cr.map((r) => r.sas_year)).size, a = agg(D, cr);
    return { ny, a, nCrops: new Set(cr.map((r) => r.crop_name)).size };
  }, [D, cr]);

  const byCrop = useMemo(() => [...groupBy(cr, (r) => `${r.crop_group}|${r.crop_name}`).values()].map((g) => ({ crop_group: g[0].crop_group, crop_name: g[0].crop_name, ...agg(D, g) })), [cr]);
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

  const trendD = useMemo(() => [...groupBy(cr, (r) => `${r.sas_year}|${r.sas_season}`).values()].map((g) => ({ y: g[0].sas_year, s: g[0].sas_season, ...agg(D, g) })).filter((r) => Number.isFinite(num(r[m]))), [cr, m]);
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
    .map((g) => ({ sas_year: g[0].sas_year, sas_season: g[0].sas_season, crop_group: g[0].crop_group, crop_name: g[0].crop_name, ...agg(D, g) }))
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
      <PublishedCrops />
      <SectionTitle title={tr('s_our_crops')} />
      <p className="muted small">{tr('our_crops_note')}</p>
      {k ? (
        <KpiRow>
          <Kpi label={tr('ms_sold_share_pct')} value={fmtPct(num(k.a.sold_share_pct))} icon={Store} color={brand.blue} foot={tr('k_sold_sub', fmtNum(num(k.a.sold_t) / k.ny / 1000), fmtNum(num(k.a.sales_value_mrwf) / k.ny / 1000, 1))} />
          <Kpi label={tr('ms_price_rwf_kg')} value={`${fmtNum(num(k.a.price_rwf_kg))} RWF/kg`} icon={Scale} color="#6A4C93" foot={`${label} · ${f.area}`} />
          <Kpi label={tr('k_n_crops')} value={String(k.nCrops)} icon={ListChecks} color={brand.green} foot={tr('layer_est')} />
        </KpiRow>
      ) : <p className="muted">{tr('no_data')}</p>}
      <div className="toolbar">
        <Select label={tr('c_top_crops')} value={m} onChange={setM} options={OUR_ONLY.map((x) => ({ value: x, label: tr(`ms_${x}`) }))} width={320} />
      </div>
      <Grid cols="1fr 1fr">
        <ChartCard title={tr('c_top_crops')} icon={Trophy}
          means={top.length ? <>{tr('m_bycrop', top[0].crop_name, tr(`ms_${m}`))}{SUMS.includes(m) ? tr('m_bycrop_share', fmtPct((100 * num(top[0][m])) / sum(top.map((r) => num(r[m]))), 0)) : ''} {tr('m_bycrop_note')}</> : null}>
          <Plot fig={barFig} height={380} empty={tr('no_data')} />
        </ChartCard>
        <ChartCard title={tr('c_measure_trend')} icon={ChartLine} means={trendMeans}><Plot fig={trendFig} height={380} empty={tr('no_data')} /></ChartCard>
      </Grid>
      <ChartCard title={tr('c_table_ours')} icon={Table2}>
        <DataTable rows={table} cols={cols} csvName={`smartirrigate_crops_project_estimate_${f.area.replace(/\W+/g, '_')}.csv`}
          csvRows={() => table.map((r) => ({ ...r, area: f.area, layer: 'project estimate from SAS microdata (not an official NISR statistic)' }))} />
      </ChartCard>
    </>
  );
}

/** NISR's published crop figures for the selection: one season, crop rows only (group subtotals listed apart, never added) */
function PublishedCrops() {
  const { O, f, tr } = useApp();
  const [pm, setPm] = useState<(typeof PUB_M)[number]>('production_t');
  const [seasonKey, setSeasonKey] = useState('');
  const [crop, setCrop] = useState('Maize');
  const area = pubArea(f);
  const ss = useMemo(() => seasonsOf(f), [f]);
  const ps: YS | undefined = ss.find((x) => ysKey(x) === seasonKey) ?? [...ss].reverse().find((x) => x.s !== 'C') ?? ss[ss.length - 1];
  const want = new Set(f.crops);
  const rows = useMemo(() => (!O || !ps || !area ? [] : O.of(pm).filter((r) => r.area === area && r.sas_year === ps.y && r.sas_season === ps.s && r.value != null && r.crop_name)),
    [O, ps, area, pm]);
  const crops = rows.filter((r) => !r.is_group && (!want.size || want.has(r.crop_name!))).sort((a, b) => (b.value as number) - (a.value as number));
  const groups = rows.filter((r) => r.is_group);
  const unit = pm === 'production_t' ? 't' : pm === 'harvested_crop_ha' ? 'ha' : 'kg/ha';
  const fig = useMemo<Fig | null>(() => {
    const d = crops.slice(0, 15).reverse(); if (!d.length || !O) return null;
    return {
      data: [{ type: 'bar', orientation: 'h', y: d.map((r) => r.crop_name), x: d.map((r) => r.value as number), marker: { color: brand.amber },
        text: d.map((r) => fmtNum(r.value)), textposition: 'outside', cliponaxis: false, textfont: { size: 11, color: brand.ink },
        hovertext: d.map((r) => `<b>${r.crop_name}</b>: ${fmtNum(r.value)} ${unit}<br>${citeShort(O, r)}, ${tr('cell')} ${r.cell}`), hoverinfo: 'text' } as Data],
      layout: std({ x: `${tr(`pub_ind_${pm}`)} (${unit})`, legend: false, bargap: 0.3, margin: { l: 10, r: 70, t: 4, b: 36 },
        xaxis: { range: [0, Math.max(...d.map((r) => r.value as number)) * 1.2] }, yaxis: { title: { text: '' }, categoryorder: 'array', categoryarray: d.map((r) => r.crop_name) } }),
    };
  }, [crops, O, pm, unit, tr]);
  const cropList = useMemo(() => [...new Set((O?.of(pm) ?? []).filter((r) => !r.is_group && r.crop_name).map((r) => r.crop_name as string))].sort(), [O, pm]);
  const series = useMemo(() => (!O || !area ? [] : seasonsOf(f).map((x) => O.get(pm, x.y, x.s, area, crop)).filter((r): r is PubRow => !!r && r.value != null)), [O, f, area, pm, crop]);
  const tfig = useMemo<Fig | null>(() => {
    if (!series.length || !O) return null;
    const data: Data[] = (['A', 'B', 'C'] as const).map((s) => { const x = series.filter((r) => r.sas_season === s); return x.length ? {
      type: 'scatter', mode: 'lines+markers', name: tr(`season_${s.toLowerCase()}`), connectgaps: false,
      x: splitAtUpgrade(x.map((r) => r.sas_year), x).x, y: splitAtUpgrade(x.map((r) => r.sas_year), x.map((r) => r.value as number)).y,
      line: { color: seasonCols[s], dash: s === 'C' ? 'dot' : 'solid' }, marker: { color: seasonCols[s], symbol: s === 'A' ? 'circle' : s === 'B' ? 'square' : 'diamond', size: 8 },
      text: splitAtUpgrade(x.map((r) => r.sas_year), x).y.map((r) => !r ? '' : `${r.sas_year}${s}: ${fmtNum(r.value)} ${unit}<br>${citeShort(O, r)}, ${tr('cell')} ${r.cell}`), hoverinfo: 'text' } as Data : null; }).filter(Boolean) as Data[];
    return simpleLines(data, std({ y: `${tr(`pub_ind_${pm}`)} (${unit})`, xaxis: { dtick: 1 }, yaxis: { rangemode: 'tozero' } }));
  }, [series, O, pm, unit, tr]);
  if (!O) return null;
  const when = ps ? tr('season_of', ps.s, ps.y) : '–';
  return (
    <>
      <SectionTitle title={tr('s_pub_crops')} />
      <div className="toolbar">
        <Select label={tr('measure')} value={pm} onChange={setPm} options={PUB_M.map((x) => ({ value: x, label: tr(`pub_ind_${x}`) }))} width={220} />
        <Select label={tr('pub_season')} value={ps ? ysKey(ps) : ''} onChange={setSeasonKey} options={[...ss].reverse().map((x) => ({ value: ysKey(x), label: tr('season_of', x.s, x.y) }))} width={170} />
        {!area && <span className="muted small">{tr('pub_unavailable_hint')}</span>}
      </div>
      <Grid cols="1fr 1fr">
        <ChartCard title={tr('c_pub_crops', when)} icon={BookOpen}
          means={crops.length ? tr('m_pub_crops', area ?? '', when, crops[0].crop_name ?? '', fmtNum(crops[0].value), unit) : tr('pub_unavailable')}
          source={<>{pubSource(O, crops, tr)} {groups.length ? tr('pub_groups_apart', groups.map((g) => `${g.crop_name} ${fmtNum(g.value)}`).join('; ')) : ''}</>}
          table={{ cols: [tr('crop'), unit, tr('pub_cell')], rows: crops.map((r) => [r.crop_name, Math.round(r.value as number), `${citeShort(O, r)} · ${r.cell}`]) }}>
          <Plot fig={fig} height={380} empty={tr('pub_unavailable')} />
        </ChartCard>
        <ChartCard title={tr('c_pub_crop_trend')} icon={ChartLine}
          tools={<Select value={crop} onChange={setCrop} options={cropList.map((c) => ({ value: c, label: c }))} width="100%" />}
          means={series.length >= 2 ? `${tr('m_pub_crop_trend', crop, area ?? '')} ${series.some((r) => r.sas_year < 2020) ? tr('usas_break') : ''}` : !area ? tr('pub_unavailable_hint') : null}
          source={pubSource(O, series, tr)}
          table={{ cols: [tr('season'), unit, tr('pub_cell')], rows: series.map((r) => [`${r.sas_year}${r.sas_season}`, Math.round(r.value as number), `${citeShort(O, r)} · ${r.cell}`]) }}>
          <Plot fig={tfig} height={380} empty={tr('pub_unavailable')} />
        </ChartCard>
      </Grid>
      {crops.length > 0 && (
        <p className="muted small"><Calculator size={13} /> <button type="button" className="link-btn" title={crops[0] ? cite(O, crops[0]) : ''}
          onClick={() => downloadCsv(pubCsv(O, [...crops, ...groups]), `smartirrigate_nisr_${pm}_${area}_${ps ? ysKey(ps) : ''}.csv`)}>{tr('dl_pub_csv')}</button></p>
      )}
    </>
  );
}

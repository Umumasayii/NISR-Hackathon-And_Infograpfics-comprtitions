import { useEffect, useRef, useState } from 'react';
import type { Data, Layout, Config } from 'plotly.js';
import { brand, FONT } from '../lib/theme';

// plotly.js is large, so it loads once, after the page shell is on screen
type PlotlyLib = typeof import('plotly.js');
let lib: Promise<PlotlyLib> | null = null;
const getPlotly = () => (lib ??= import('plotly.js-dist-min').then((m) => (m.default ?? m) as unknown as PlotlyLib));

export interface Fig { data: Data[]; layout?: Partial<Layout>; config?: Partial<Config> }

export const narrow = () => typeof window !== 'undefined' && window.innerWidth < 700;

const baseConfig: Partial<Config> = {
  displaylogo: false, responsive: true,
  modeBarButtonsToRemove: ['lasso2d', 'select2d', 'autoScale2d', 'toggleSpikelines', 'hoverCompareCartesian', 'hoverClosestCartesian'],
  toImageButtonOptions: { format: 'png', filename: 'smartirrigate_chart', scale: 2 },
  // the base-map file is an empty topology served with the app: only the district
  // shapes are drawn, and maps also work offline (no call to cdn.plot.ly)
  topojsonURL: `${import.meta.env.BASE_URL}topojson/`,
};

export function Plot({ fig, height = 320, onClick, empty }: {
  fig: Fig | null; height?: number; onClick?: (key: string) => void; empty?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const click = useRef(onClick); click.current = onClick;
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let alive = true;
    const el = ref.current;
    if (!el || !fig) return;
    getPlotly().then((P) => {
      if (!alive) return;
      // rounded data ends on every bar chart, unless a figure sets its own
      const layout = { barcornerradius: 4, ...fig.layout, height, autosize: true } as Partial<Layout>;
      P.react(el, fig.data, layout, { ...baseConfig, ...fig.config }).then(() => {
        if (!alive) return;
        setReady(true);
        const gd = el as unknown as { removeAllListeners?: (e: string) => void; on: (e: string, cb: (ev: unknown) => void) => void };
        gd.removeAllListeners?.('plotly_click');
        gd.on('plotly_click', (ev) => {
          const p = (ev as { points?: { customdata?: unknown; location?: string }[] }).points?.[0];
          const key = p && ((Array.isArray(p.customdata) ? p.customdata[0] : p.customdata) ?? p.location);
          if (key != null && click.current) click.current(String(key));
        });
      });
    });
    return () => { alive = false; };
  }, [fig, height]);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const ro = new ResizeObserver(() => { getPlotly().then((P) => { if (el.isConnected && (el as unknown as { data?: unknown }).data) P.Plots.resize(el); }); });
    ro.observe(el);
    return () => { ro.disconnect(); getPlotly().then((P) => P.purge(el)); };
  }, []);

  if (!fig) return <div className="plot-empty" style={{ height }}>{empty}</div>;
  return (
    <div className="plot-wrap" style={{ minHeight: height }}>
      {!ready && <div className="plot-skeleton" style={{ height }} />}
      <div ref={ref} className="plot" />
    </div>
  );
}

// ---- standard layout (plotly_std() in the Shiny app) ----------------------------------
export function std(opts: { x?: string; y?: string; legend?: boolean | Partial<Layout['legend']>; xaxis?: Partial<Layout['xaxis']>; yaxis?: Partial<Layout['yaxis']> } & Omit<Partial<Layout>, 'legend' | 'xaxis' | 'yaxis'> = {}): Partial<Layout> {
  const { x, y, legend = true, xaxis, yaxis, ...rest } = opts;
  const axis = (title?: string) => ({
    title: { text: title ?? '', font: { size: 12, color: '#5E6A66' } }, gridcolor: '#EEF1ED', zeroline: false,
    linecolor: '#D5DDD8', tickfont: { color: '#5E6A66' }, automargin: true,
  });
  return {
    font: { family: FONT, size: 13, color: brand.ink },
    paper_bgcolor: 'rgba(0,0,0,0)', plot_bgcolor: 'rgba(0,0,0,0)',
    showlegend: legend !== false, legend: typeof legend === 'object' ? legend : { orientation: 'h', y: -0.2, x: 0 },
    hoverlabel: { font: { family: FONT, size: 13 }, bgcolor: '#FFFFFF', bordercolor: '#D5DDD8' },
    margin: { l: 10, r: 10, t: 10, b: 10 },
    ...rest,
    xaxis: { ...axis(x), ...xaxis } as Layout['xaxis'],
    yaxis: { ...axis(y), rangemode: 'tozero', ...yaxis } as Layout['yaxis'],
  };
}

/** Trend lines: thin line, one marker shape per series, legend at the right */
export function simpleLines(data: Data[], layout: Partial<Layout>): Fig {
  const syms = ['circle', 'diamond', 'square', 'triangle-up', 'cross', 'star'];
  let k = 0;
  const d = data.map((t) => {
    const s = t as { type?: string; mode?: string; marker?: object; line?: object };
    if (s.type === 'scatter' && (s.mode || '').includes('lines')) {
      const sym = syms[k++ % syms.length];
      return { ...s, marker: { ...s.marker, symbol: sym, size: 7, line: { width: 0 } }, line: { ...s.line, width: 2.2 } } as Data;
    }
    return t;
  });
  const legend = narrow()
    ? { orientation: 'h' as const, y: -0.22, x: 0, font: { size: 11.5 } }
    : { orientation: 'v' as const, x: 1.02, xanchor: 'left' as const, y: 0.5, yanchor: 'middle' as const, font: { size: 11.5 }, bgcolor: 'rgba(0,0,0,0)' };
  return { data: d, layout: { ...layout, showlegend: true, legend, hovermode: 'x unified' } };
}

/** Bottom legend that wraps (several series) */
export const legendBottom = (y = -0.2): Partial<Layout['legend']> => ({ orientation: 'h', y, x: 0, font: { size: 11 } });

// ---- district maps ---------------------------------------------------------------------
export interface MapRow { district: string; value: number | null; hover?: string; /** rests on few plots: drawn paler */ weak?: boolean }
export function choropleth(geo: unknown, rows: MapRow[], o: {
  label: string; colorscale: [number, string][]; zmin?: number; zmax?: number; selected?: string[]; unit?: string; dec?: number; noData?: string;
}): Fig {
  const d = rows.filter((r) => r.value != null && Number.isFinite(r.value));
  const hl = !!o.selected && o.selected.length > 0 && o.selected.length < 30;
  // a district without an estimate is drawn in plain grey and says so; it is never
  // left blank (which reads as zero) or filled with another area's value
  const all = ((geo as { features?: { properties: { district: string } }[] }).features ?? []).map((x) => x.properties.district);
  const have = new Set(d.map((r) => r.district));
  const none = all.filter((x) => !have.has(x));
  return {
    data: [...(none.length ? [{
      type: 'choropleth', geojson: geo, featureidkey: 'properties.district', locations: none, z: none.map(() => 0),
      colorscale: [[0, '#E4E7E5'], [1, '#E4E7E5']], showscale: false, customdata: none,
      text: none.map((x) => `<b>${x}</b><br>${o.noData ?? 'No estimate'}`), hoverinfo: 'text',
      marker: { line: { color: '#FFFFFF', width: 1 } },
    } as unknown as Data] : []), {
      type: 'choropleth', geojson: geo, featureidkey: 'properties.district',
      locations: d.map((r) => r.district), z: d.map((r) => r.value as number),
      zmin: o.zmin, zmax: o.zmax, colorscale: o.colorscale, customdata: d.map((r) => r.district),
      text: d.map((r) => r.hover ?? `<b>${r.district}</b><br>${o.label}: ${(r.value as number).toFixed(o.dec ?? 1)}${o.unit ?? ''}`),
      hoverinfo: 'text',
      marker: { opacity: d.map((r) => (r.weak ? 0.45 : 1)), line: { color: d.map((r) => (hl && o.selected!.includes(r.district) ? brand.ink : '#FFFFFF')), width: d.map((r) => (hl ? (o.selected!.includes(r.district) ? 2.5 : 0.8) : 1)) } },
      colorbar: { title: { text: o.label, side: 'top' }, thickness: 10, len: 0.6, orientation: 'h', x: 0.5, xanchor: 'center', y: -0.02, yanchor: 'top' },
    } as unknown as Data],
    layout: {
      geo: { fitbounds: 'locations', visible: false, bgcolor: 'rgba(0,0,0,0)', projection: { type: 'mercator' } } as Layout['geo'],
      margin: { l: 0, r: 0, t: 0, b: 40 }, paper_bgcolor: 'rgba(0,0,0,0)', font: { family: FONT, color: brand.ink },
      hoverlabel: { font: { family: FONT, size: 13 }, bgcolor: '#FFFFFF', bordercolor: '#D5DDD8' },
    },
    config: { scrollZoom: false },
  };
}

// Team NiyoIshimwe brand. Data-mark colours are the brand hues nudged to pass a
// colour-blind check on the canvas (same values as the Shiny app, fct_helpers.R).
export const brand = {
  green: '#176B45', blue: '#1976B9', amber: '#D39A32', terracotta: '#B65F47',
  canvas: '#F7F9F6', ink: '#1B2C2A', grey: '#858F8A', white: '#FFFFFF',
};
export const seriesCols = ['#0F7044', '#B07A1C', '#1976B9', '#B65F47', '#6A4C93', '#00897B'];
export const extraCols = [...seriesCols, '#858F8A', '#7FA88F', '#C2A06A', '#7DA7CC'];
export const colIrrigated = '#0F7044';
export const colRainfed = '#858F8A';
export const seasonCols: Record<string, string> = { A: '#0F7044', B: '#1976B9', C: '#B07A1C' };
export const provinceCols: Record<string, string> = { East: '#0F7044', Kigali: '#6A4C93', North: '#1976B9', South: '#B07A1C', West: '#B65F47' };
export const relCols: Record<string, string> = { Good: '#0F7044', 'Use with caution': '#B07A1C', Unreliable: '#B65F47', Published: '#1976B9' };

type Scale = [number, string][];
export const seqGreen: Scale = [[0, '#EAF4EE'], [0.5, '#5FA97F'], [1, '#0B4F30']];
export const seqBlue: Scale = [[0, '#E8F1F9'], [0.5, '#5B9BD0'], [1, '#0D4C80']];
export const seqAmber: Scale = [[0, '#FBF3E4'], [0.5, '#D9A44A'], [1, '#7A5210']];
export const divRain: Scale = [[0, '#8C5A2B'], [0.5, '#ECEDE8'], [1, '#1976B9']];
export const divGap: Scale = [[0, '#1976B9'], [0.5, '#F2F2EE'], [1, '#B07A1C']];

export const FONT = "'Segoe UI Variable Text', 'Segoe UI', system-ui, -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif";

/** a fixed colour per category, in the order given */
export const catCols = (cats: string[], pal = extraCols) =>
  Object.fromEntries(cats.map((c, i) => [c, pal[i % pal.length]]));

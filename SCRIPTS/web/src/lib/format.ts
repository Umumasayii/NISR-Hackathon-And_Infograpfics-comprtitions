const DASH = '–';
const isNum = (x: unknown): x is number => typeof x === 'number' && Number.isFinite(x);

export const fmtNum = (x: number | null | undefined, d = 0) =>
  isNum(x) ? x.toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d }) : DASH;
export const fmtPct = (x: number | null | undefined, d = 1) => (isNum(x) ? `${x.toFixed(d)}%` : DASH);
export const signed = (x: number, d = 0) => `${x >= 0 ? '+' : ''}${fmtNum(x, d)}`;
export const seasonLabel = (y: number, s: string) => `${y}${s}`;

/** "Kirehe", "Kirehe, Ngoma", "Kirehe + 3" */
export const shortSet = (x: string[], maxShow = 2) =>
  x.length <= maxShow ? x.join(', ') : `${x[0]} + ${x.length - 1}`;

export { isNum, DASH };

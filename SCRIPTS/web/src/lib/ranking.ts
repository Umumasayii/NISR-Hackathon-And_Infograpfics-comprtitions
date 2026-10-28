// District screening score and its sensitivity to the preference weights.
// Pure functions (no React), so tests/ranking.test.ts can run them with node --test.
//
// What the sensitivity measures: how much a district's rank moves when the planner's
// preference weights are perturbed around the chosen ones. It is NOT sampling
// uncertainty of the survey estimates and NOT a probability that an investment works.

export type Weights = Record<string, number>;

/** Effective weights: the chosen weights divided by their sum (exactly 0 stays 0).
 *  Returns null when every weight is zero, so the caller must show "no ranking". */
export function normalise(w: Weights, comps: readonly string[]): Weights | null {
  const tot = comps.reduce((a, c) => a + Math.max(0, w[c] ?? 0), 0);
  if (!(tot > 0)) return null;
  return Object.fromEntries(comps.map((c) => [c, Math.max(0, w[c] ?? 0) / tot]));
}

/** Score 0-100: weighted mean of the 0-1 component scores, with normalised weights */
export function scoreRow<R extends object>(r: R, p: Weights, comps: readonly string[]): number {
  const x = r as Record<string, unknown>;
  return 100 * comps.reduce((a, c) => a + (Number(x[c]) || 0) * (p[c] ?? 0), 0);
}

/** Rank 1 = highest; ties share the better rank */
export const rankOf = (x: number[]) => x.map((v) => 1 + x.filter((y) => y > v).length);

export function mulberry32(seed: number) {
  let a = seed >>> 0;
  return () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
function normal(rnd: () => number) {
  const u1 = rnd() || 1e-12, u2 = rnd();
  return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
}
/** Gamma(shape a, scale 1). Marsaglia-Tsang for a >= 1; for a < 1 the boost
 *  Gamma(a) = Gamma(a + 1) * U^(1/a), so small weights are drawn correctly. */
export function gamma(a: number, rnd: () => number): number {
  if (!(a > 0)) return 0;
  if (a < 1) return gamma(a + 1, rnd) * Math.pow(rnd() || 1e-12, 1 / a);
  const d = a - 1 / 3, c = 1 / Math.sqrt(9 * d);
  for (;;) {
    let x: number, v: number;
    do { x = normal(rnd); v = 1 + c * x; } while (v <= 0);
    v = v * v * v;
    const u = rnd();
    if (u < 1 - 0.0331 * x ** 4 || Math.log(u) < 0.5 * x * x + d * (1 - v + Math.log(v))) return d * v;
  }
}

export const SIMS = 1000;
export const CONCENTRATION = 20;
export const SEED = 2026;

/** One weight set from Dirichlet(CONCENTRATION * p) over the criteria with p > 0.
 *  Criteria set to zero stay exactly zero; the mean of the draws equals p. */
export function drawWeights(p: Weights, comps: readonly string[], rnd: () => number, k = CONCENTRATION): Weights {
  const g = comps.map((c) => (p[c] > 0 ? gamma(k * p[c], rnd) : 0));
  const t = g.reduce((a, b) => a + b, 0);
  return Object.fromEntries(comps.map((c, i) => [c, t > 0 ? g[i] / t : 0]));
}

/** Ranks under SIMS perturbed weight sets: out[s][i] = rank of row i in draw s */
export function weightSensitivity<R extends object>(rows: R[], p: Weights, comps: readonly string[], sims = SIMS, seed = SEED): number[][] {
  const rnd = mulberry32(seed);
  const out: number[][] = [];
  for (let s = 0; s < sims; s++) {
    const v = drawWeights(p, comps, rnd);
    out.push(rankOf(rows.map((r) => scoreRow(r, v, comps))));
  }
  return out;
}

/** p-th quantile of a sorted array (nearest rank below) */
export const qSorted = (s: number[], q: number) => s[Math.min(s.length - 1, Math.floor(q * (s.length - 1)))];

export function stabilityLabel(p10: number, p90: number) {
  return p90 - p10 <= 4 ? 'Stable' : p90 - p10 <= 10 ? 'Moderately sensitive' : 'Sensitive to weights';
}

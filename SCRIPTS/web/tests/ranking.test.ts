// Run: node --experimental-strip-types --test tests/   (Node 22+)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalise, drawWeights, weightSensitivity, mulberry32, gamma, scoreRow, rankOf } from '../src/lib/ranking.ts';

const C = ['a', 'b', 'c', 'd'] as const;

test('all-zero weights give no ranking (null), never a silent fallback', () => {
  assert.equal(normalise({ a: 0, b: 0, c: 0, d: 0 }, C), null);
});

test('effective weights sum to 1 and zero stays zero', () => {
  const p = normalise({ a: 0.5, b: 0.25, c: 0, d: 0.25 }, C)!;
  assert.equal(p.c, 0);
  assert.ok(Math.abs(Object.values(p).reduce((x, y) => x + y, 0) - 1) < 1e-12);
});

test('Dirichlet draws keep zero-weight criteria exactly zero', () => {
  const p = normalise({ a: 1, b: 0, c: 0.3, d: 0 }, C)!;
  const rnd = mulberry32(1);
  for (let i = 0; i < 2000; i++) {
    const v = drawWeights(p, C, rnd);
    assert.equal(v.b, 0); assert.equal(v.d, 0);
    assert.ok(Math.abs(v.a + v.c - 1) < 1e-9);
  }
});

test('Dirichlet draws are centred on the chosen weights (mean = p)', () => {
  const p = normalise({ a: 0.6, b: 0.05, c: 0.35, d: 0 }, C)!;
  const rnd = mulberry32(7), n = 20000, m: Record<string, number> = { a: 0, b: 0, c: 0, d: 0 };
  for (let i = 0; i < n; i++) { const v = drawWeights(p, C, rnd); for (const k of C) m[k] += v[k] / n; }
  for (const k of C) assert.ok(Math.abs(m[k] - p[k]) < 0.006, `${k}: ${m[k]} vs ${p[k]}`);
});

test('gamma sampler mean matches the shape, also below 1', () => {
  for (const a of [0.2, 0.7, 1, 3.5]) {
    const rnd = mulberry32(11); let s = 0; const n = 40000;
    for (let i = 0; i < n; i++) s += gamma(a, rnd);
    assert.ok(Math.abs(s / n - a) < 0.05 * Math.max(1, a), `shape ${a}: mean ${s / n}`);
  }
});

test('a single active criterion gives identical ranks in every draw', () => {
  const rows = [{ a: 0.9, b: 0.1, c: 0, d: 0 }, { a: 0.2, b: 0.9, c: 0, d: 0 }, { a: 0.5, b: 0.5, c: 0, d: 0 }];
  const p = normalise({ a: 1, b: 0, c: 0, d: 0 }, C)!;
  const base = rankOf(rows.map((r) => scoreRow(r, p, C)));
  for (const s of weightSensitivity(rows, p, C, 200)) assert.deepEqual(s, base);
});

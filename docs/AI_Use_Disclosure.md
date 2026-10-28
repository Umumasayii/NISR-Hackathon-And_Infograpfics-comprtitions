# AI-use disclosure

Team NiyoIshimwe used Claude (Anthropic), through Claude Code, as a coding and analysis assistant.

## What the AI assistant did

- Wrote and revised R scripts (data preparation, survey estimates, reconciliation with NISR tables,
  models, web export, build manifest) and the React/TypeScript website, under the team's direction.
- Investigated differences between project estimates and NISR published figures by recomputing them
  from the microdata several ways, and drafted the explanations in the methods documents.
- Drafted documentation and the French and Kinyarwanda interface text.
- Ran the pipeline, unit tests and browser checks in a cloud build environment.

## What the team did and is responsible for

- Chose the question, the users, the indicators and the design rules (for example: NISR published
  figures first; no 2026 data; no causal claims; plain language).
- Obtained the NISR data and published tables, and decided every change that reached the live site.
- Reviews and owns all results, text and code submitted.

## Checks on AI output

- Every NISR comparison is reproducible from `SCRIPTS/15_Reconcile_With_NISR.R` and listed cell by
  cell in `docs/Reconciliation_Register_2019_2025.csv`.
- The pooled-season variance was checked against `survey::svymean` (`SCRIPTS/tests/test_pooled_variance.R`).
- The ranking code has unit tests (`SCRIPTS/web/tests/ranking.test.ts`).
- French and Kinyarwanda text has **not** yet been reviewed by native speakers; it is marked as a draft.

No data were sent to the AI assistant beyond what was needed for the build environment; microdata
are never published.

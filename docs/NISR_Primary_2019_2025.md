# NISR figures first, 2019–2025

Branch `nisr-published-primary` (local review branch; not pushed, not deployed). Built 2026-10-21.

## What changed for the reader

- **Published NISR figures are the primary figures.** Where NISR publishes a figure with the same definition as one of ours, every view (headline number, chart, map, list, table, sentence and CSV) is built from the NISR value. Our estimate stays in the Methods register as a cross-check.
- **Every NISR figure carries its citation**: publication, table number and title, file, sheet, cell and the column wording NISR prints, plus who the figure describes (farmers, plots, land, harvested area) and its unit.
- **One season at a time.** NISR publishes each season on its own, so published views show one season (a "Season shown" picker). No NISR percentage is averaged across seasons, and land is never added across Seasons A and B.
- **Places NISR does not publish.** NISR publishes Rwanda and each district. For several districts or a province the app shows "Published breakdown unavailable" and, where useful, a separately labelled project estimate. A national value is never copied into a district, crop or group.
- **Our analysis stays, labelled.** Plots irrigated, motorised/modern methods, irrigated vs rain-fed yields, gender and consolidation gaps, the model and the screening shortlist are project estimates or analysis, labelled as such.
- **Trends only within comparable periods.** A season is compared only with the same season. NISR upgraded the survey in 2020 (USAS 2020), so published series are not drawn as one line across 2019 and 2020, and headline changes are read from 2020 on.
- **No 2026 statistics** anywhere: the 2026 workbooks, the old 2026 cell map and 2026 benchmark text are removed; any release or season after 2025 is skipped on read (R and browser).

### Pages

| Page | Now shows |
|---|---|
| Overview | Four NISR headline tiles (farmers who irrigated, dry Season C, farmers using chemical fertiliser, cultivated land for one season); NISR district map beside the same values sorted and labelled; district card (NISR district vs Rwanda, our plot estimate labelled); 100-farmer picture; NISR irrigation types; trend of NISR series (one line per season) or our two plot series (labelled); "What NISR reports" (figures quoted with table) separate from "Our analysis". |
| Map | NISR indicators first (one season, with year animation of the same season); our estimates labelled; profile table with citations; CSV of the NISR figures with table and cell. |
| District | NISR tiles (farmers irrigated, chemical fertiliser, cultivated land) with Rwanda beside them; NISR trend district vs Rwanda by season; NISR practices district vs Rwanda; NISR top crops by production. Rain risk, radar and screening rank stay (our analysis). |
| Crops (Explorer) | NISR production, harvested area and yield by crop for one season (group subtotals listed apart, never added) and one crop over time; our section keeps only what NISR does not publish (sales, prices, irrigated vs rain-fed yields). |
| Methods | Register tab: every published figure by indicator and level, NISR value, our value, gap, decision and table/cell; CSV keeps all citation columns. Six reconciliation findings. New download: published NISR figures (national). |

## Decision rule (register `decision`)

| Decision | Meaning | National rows | All rows |
|---|---|---:|---:|
| NISR value shown; project estimate kept as cross-check | Same definition: NISR replaces ours everywhere | 762 | 17,967 |
| NISR value shown under its own label; not compared | Different definition (e.g. NISR irrigation types, area under irrigation, cultivated area by crop, practices published per farmer where ours is per plot) | 491 | 16,185 |
| NISR value shown; no project estimate | Same definition, but our value is not in the current build (per-farmer and per-hectare input measures, district crop rows) | 485 | 20,966 |
| Published cell blank: shown as unavailable | NISR printed no number: shown as unavailable, never zero | 8 | 2,435 |

Our estimates **retained as labelled estimates** (NISR publishes nothing comparable): share of plots irrigated, plots irrigated by motorised pump/machine, drip, sprinkler or pivot, irrigated plot area, irrigated vs rain-fed yield, sales and prices by crop, gender/consolidation gaps, AHS household indicators, model outputs, screening scores.

## Reconciliation findings (national, NISR vs ours)

1. **Chemical fertiliser, % of plots**: within 1 point in 17 of 21 seasons. NISR is 22–24 points higher in 2025A and 2025B (56.5% vs 34.4%; 52.8% vs 29.0%). The questionnaire variables did not change between 2024 and 2025, so the cause is not established. NISR's value is shown.
2. **Pesticides, % of plots**: within 1 point through 2022B (except 2019); from 2022C NISR is 28–36 points higher. NISR printed no 2023A/2023B plot figure: unavailable, not zero.
3. **Organic fertiliser, % of plots**: equal 2020A–2022B; ours 5–10 points higher in 2019 and 7–18 points lower from 2022C.
4. **Farmers who irrigated**: ours 0–2 points lower in Seasons A and B, 4–19 points lower in Season C (2020–2025).
5. **Cultivated land**: ours 3–12% below NISR from 2020, about 21% above in 2019. Harvested area by crop is close for most crops; cassava is the main exception (ours up to 5 times NISR's in Season A).
6. **Maize production**: within 10% in 12 of 14 main seasons; 2019A ours 35% lower, 2024B ours 10% higher. Our 2024B paddy rice yield is far off (crop areas incomplete), which is why 2024B and 2024C stay out of our yield analysis.

The pattern (exact agreement for years, then a jump in one season) points to a change in NISR's tabulation or ours for those indicators, not sampling noise. `SCRIPTS/15_Reconcile_With_NISR.R` recomputes each input eight ways (plot, answered-only, small-scale only, crop module, unweighted, farmer with two weightings, land) by district and season, and splits production gaps into area and yield, so the device rebuild can say which definition NISR used. It needs the microdata and was not run here.

## Files changed

R pipeline
- `SCRIPTS/11_NISR_Published_Tables.R`: reads every NISR table cell by cell (file, sheet, Excel cell, table, row, column, season); skips any release or season after 2025.
- `SCRIPTS/14_Official_Reference.R`: rule-based mapping (`DATA/NISR_published/indicator_rules.csv`) to app indicators with unit, population, definition and comparability; crop groups flagged and renamed "(all)", including a parent printed in a different table from its parts (SAS 2019 Beans/Bananas); latest release wins, earlier value kept in `revised_from`.
- `SCRIPTS/15_Reconcile_With_NISR.R` (new): reconciliation of fertiliser, pesticide and crop production nationally and by district.
- `SCRIPTS/06_Merge_Master_Data.R`, `07_Build_App_Data.R`: per-farmer and per-hectare input estimates; section 10 joins NISR figures to ours and writes `official`.
- `SCRIPTS/09_Run_All.R`: runs 11, 14, 15 when 2019–2025 workbooks are present. `SCRIPTS/12_Export_Web_Data.R`: writes `official.json`.
- `SCRIPTS/tests/test_official.R` (new, 13 checks), `test_core.R`, `test_crop.R`.
- `SCRIPTS/app/R/*`: 2026 benchmark line removed from the Shiny overview; comments updated.

Data
- `DATA/NISR_published/`: the seven SAS annual table workbooks 2019–2025 (as supplied from NISR_downloads) and `indicator_rules.csv`. Removed: `Tables_2026 Season A.xlsx`, `Tables_2026 Season B.xlsx`, `official_cell_map.csv`.
- `SCRIPTS/web/public/data/official.json` (new): 57,553 published figures, 1,888 source tables. `app_data.json`: old `official` and `register` removed, interim note updated.
- `docs/Reconciliation_Register_2019_2025.csv`: national register (1,746 rows). Full register (57,553 rows) in the delivery folder.

Website
- `src/lib/official.ts` (new): lookup, citation, unavailable rule, CSV with provenance.
- `src/data/store.tsx`, `src/data/types.ts`: load and type `official.json`.
- `src/pages/Overview.tsx`, `MapPage.tsx`, `District.tsx`, `Explorer.tsx`, `Methods.tsx`: NISR-first as above.
- `src/lib/webI18n.ts`: 112 new or rewritten EN/FR/RW strings. `src/styles.css`: citation tag.
- `SCRIPTS/web/tools/interim_official.py` (new): builds `official.json` and the registers from `official_reference.csv` and the committed `app_data.json` when the microdata are not at hand.
- `SCRIPTS/app/DATA_SOURCE.md`, `public/data/data_source.md`: which figure is shown and why.

## Tests and build

- R: `test_official.R` 13/13, `test_core.R` 6/6, `test_crop.R` 5/5 pass.
- `npm run build` (tsc + Vite): passes, no type errors.
- Browser checks (Playwright, Chromium), all passing: KPI equals the NISR cell (national 2025B; season picker 2025A; one district); two districts show "Published breakdown unavailable" and no national value; map table has 30 districts each equal to the NISR cell and sorted; a season NISR did not publish is absent, never 0; Explorer shows NISR maize production and never lists a subtotal as a crop; screening ranks change with the weights; all 12 pages at 390 px wide in EN, FR and RW with no sideways scroll, no untranslated keys and no console errors.

## Limitations

- **Full pipeline not run here**: the cloud copy has no survey microdata. Published figures were read from the real NISR workbooks; our estimates come from the last full build. Per-farmer and per-hectare input estimates and script 15 need the rebuild.
- The 2025A/B fertiliser and 2022C+ pesticide gaps are documented, not explained.
- NISR province tables, AHS published tables and SAS 2017/2018 were not mapped (out of scope or not supplied).
- FR and RW wording are drafts awaiting a native-speaker check. Comprehension was not tested with users.
- No Kinyarwanda recordings exist yet, so no audio was added (nothing autoplays).
- The Shiny app (`SCRIPTS/app`) still shows our estimates; the website is the NISR-first deliverable.
- The diagnostic report mentioned in the request was not received.

## For the full rebuild (on the laptop)

1. Keep the seven workbooks in `DATA/NISR_published/` (2019–2025 only).
2. Run `SCRIPTS/09_Run_All.R` with the SAS 2019–2025 microdata in `DATA/SAS`.
3. Read `DATA/processed/official/reconcile_inputs_best.csv` and `reconcile_production.csv` for the cause of each gap.
4. Run `SCRIPTS/12_Export_Web_Data.R`, then `npm run build` in `SCRIPTS/web`.

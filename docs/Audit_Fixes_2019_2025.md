# SmartIrrigate Rwanda: audit fixes for the 2019-2025 statistics

Review branch `audit-fixes-2019-2025`, one local commit on top of `master` (d612e1b).
**Nothing was pushed, deployed or published, and the device folder was not touched.**
The live site is unchanged.

## 1. What changed, in short

| Audit finding | What was wrong (checked against the code and data) | Fix |
|---|---|---|
| Crop double counting | The NISR overlay (07 section 10) added parent rows ("Vegetables (all)", "Fruits (all)", "Fodder crops", "Yams & taro") beside their own crops for 2024B, 2025A, 2025B. 2025A vegetables summed to 291,155 t instead of 141,345 t. | Overlay removed. 12 refuses to export group subtotals. Interim data: 12 parent rows dropped. |
| Published figures written over estimates | 2024B, 2025A, 2025B national production and 2026 estimates came from the published tables, labelled as ours. | Survey values restored (48 rows). Published figures now form a separate layer read cell by cell (`14_Official_Reference.R`) and are shown only beside, never instead of, our estimates. |
| 2026 statistics | 309 estimate rows, 62 totals, 38 crop and 1,140 district-crop rows from SAS 2026; 2026 benchmarks; "23 seasons, 2019–2026". | All removed. The website also drops any row later than 2025 when it loads. Script 11 is retired. Competition dates are unaffected. |
| Yield aggregation and masks | Web averaged yields with the wrong weights (irrigated yields weighted by plot count, rain-fed by all crop area); masks differed between tables. | 06 uses one mask (yield_ok and usable season) and exports harvest and area sums; the web divides summed harvest by summed area (`yieldOf`). Until the rebuild, combinations of rows are left empty instead of averaged. |
| Rainfall variability | One CV over A and B totals counted the normal A/B difference as risk (Rusizi 31%). | CV within each season against 1991–2020, averaged over A and B (Rusizi 14.8%: A 11.5%, B 18.1%). Need score, quadrants and shortlist recomputed. |
| Cultivated land A+B | District profile summed A and B land (Kirehe 130,380 ha). | Average per main season (65,190 ha); same rule on the map, Need bubbles and overview. |
| Rankings not following weights | Reasons, rank ranges and "chance of top 5" stayed at the default weights. | Reasons, ranges, stability and top-5 frequency recomputed live from 1,000 weight sets drawn around the chosen weights (seeded). CSV now carries weights, periods, layer and method. Default weight of "current input use" set to 0 while fertiliser is unreconciled. |
| Charts ignoring filters | Equity and cost charts are pooled national figures but looked filtered. | Each says "Pooled …, whole country: the filters do not change this chart". |
| Missing treated as zero | District sums counted a missing district as 0; maps left missing districts blank. | Totals are empty unless every selected district has a value; maps draw missing districts grey with "No estimate"; unreliable districts paler. |
| AHS trend across the 2024 break | "Inputs are spreading", "Better seed is spreading", changes 2017→2024. | 2024 shown on its own; change only 2017→2020. "Improved seed is common; crop insurance remains rare". |
| AUC ties, model evaluation | AUC gave 0 or 1 for a tied pair depending on order; Brier shown without a baseline. | Tie-corrected AUC (tested), average precision, top-10% precision/recall/lift, Brier baselines. Web shows the constant-guess Brier (0.0240 vs model 0.0229) and flags the AUC as pre-correction until the rebuild. |
| Causal wording | "Fair comparison", "not chance", "What irrigation adds". | "Adjusted comparison", "raw difference", "the 95% intervals do not overlap", "an association, not proof". |
| Provenance lost in export | No layer or source on charts and CSVs. | `meta.layers`; source lines on the overview, shortlist, yield, equity and cost charts; layer/source/scope columns in every Methods CSV and the shortlist CSV; a reconciliation register tab on Methods. |
| Modern irrigation label | Called "modern" and described as "pumps, pivots or channels". | "Pump, machine, drip, sprinkler or pivot", with a note that NISR's "modern irrigation" is wider. |
| Affiliation | "for the NISR 2026 Big Data Hackathon", "Official" badges. | Footer and Methods say the project is independent, not affiliated with or endorsed by NISR. |

Other fixes found on the way: the AHS survey helper crashed on AHS data (no `sas_year`);
sold share used mismatched plot sets; script 12 pushed to GitHub by default (now only with
`SI_AUTO_PUSH=TRUE`); hard-coded Windows paths in 01 and 02.

## 2. Overview page

Same look and colours, fewer words. From top: four headline numbers, each with its population
and period written under it and a tap-to-open definition; the district map beside the same
values in order (tap either to pick a district); a card that explains the chosen district
(its share against Rwanda, rain risk, screening rank, link to the profile); three small
pictures (100 squares for 100 plots, how irrigated plots get water, irrigated vs rain-fed
yield of one crop on zero-based bars); the season trend; the five-district shortlist with a
link to the feasibility checklist; findings; links to the detailed pages.

Accessibility: the overview charts, the shortlist charts, and the yield, equity and cost charts
have a source line and a "Show as table" view, so they can be read without hovering (the other
pages' charts still rely on labels and hover; the same two props add it there); sortable table headers work from the keyboard and announce their order; KPI notes open
on tap; the filter drawer takes and returns focus; touch targets 44 px and body text 16 px on
phones; low-contrast hint icons darkened. Optional human-recorded Kinyarwanda audio
(`AudioNote`, manifest-driven, no autoplay, transcript always shown); none recorded yet, see
`docs/Audio_Recording_Script.md`.

## 3. Data reconciliation register

`docs/Reconciliation_Register_2019_2025.csv` (116 lines; the Methods tab shows the 28
comparable ones). Columns give the source title and URL, workbook, sheet, cell, year, season,
area, unit, published population and definition, our population, whether it measures the same
thing, both values, the gap and the decision. Summary:

* **Flagged for clarification (not replaced):** SAS 2025 chemical fertiliser A/B (−22 and
  −24 pts), organic fertiliser A/B/C (−8 to −14 pts), pesticide A/B/C (−28 to −31 pts),
  farmers irrigating 2025C (−4.4 pts); maize production 2019A (−35%), 2023B (−9%), 2024A
  (+8%), Nyagatare maize 2024B (+37%), Musanze potato 2024B (−15%).
* **Retained as derived, consistent:** farmers irrigating 2025A and 2025B, chemical
  fertiliser 2025C.
* **Retained as derived, different definition:** AHS 2024 "irrigates" (published 14.13% of
  crop-producing household-season records vs our 27.1% of farm households).
* **Flagged, definition to confirm:** AHS 2024 improved seed, chemical fertiliser,
  agroforestry, erosion control.
* **Flagged, inconsistency inside the official tables (not corrected):** AHS 2024 Table 30
  cooperative membership (national 11.8% above both male 3.8% and female 4.8%); Table 40
  Kigali households (590.5 vs 37.1 thousand).
* **Unavailable here:** 81 production cells located in the 2026 release's prior-season
  columns. They were not read or used; the same figures should be read from the SAS 2024 and
  2025 Annual Tables.
* **Changed in the app data:** the 7 removal and replacement steps listed in section 1.

All published values are **audit-reported, not verified**: statistics.gov.rw is blocked from
this environment and the SAS 2019-2025 and AHS 2024 workbooks are not in the repository.
`14_Official_Reference.R` reads them cell by cell once they are saved in
`DATA/NISR_published/`, warns where a cell does not hold the audit's value, and only then
fills the published layer.

## 4. Checks run

* **Audit numbers re-run on the app data:** all 40 reproduced before the fixes. After the
  fixes: group sums no longer double count, 2026 rows gone, season CVs as above, survey
  production restored (`verify_after.txt`).
* **R unit tests (all pass):** tied AUC = 0.5 either way (old code gave 0 and 1); weighted
  AUC with ties equals the brute-force pair count (0.847978; old 0.850356); average precision
  of a random score ≈ prevalence; top-10% selection; survey helper equals `svyby` for SAS
  seasons and AHS rounds; `crop_measures` yields are summed harvest over summed eligible area,
  an unusable season gives no yield, season sums recombine to the pooled yield, sold share in
  0-100, irrigated + rain-fed plots = all yield plots.
* **14_Official_Reference.R:** with no workbooks, every cell reports "workbook missing" or
  "later release, not read"; with a synthetic workbook it reads the cells, writes the layer
  and warns on a cell that does not match the audit.
* **All edited R scripts parse.** TypeScript type check and production build pass.
* **Browser (Playwright, built site):** 14 screenshots, desktop 1366 px and phone 390 px,
  EN/RW/FR, a district selected (Kirehe), a weight set to 0 (reasons and ranges update);
  no page errors.

## 5. Not done or not verifiable here

* The full pipeline was **not run**: the SAS and AHS microdata are only on your computer. The
  website data are an interim correction (`SCRIPTS/web/tools/interim_app_data.py`). Still
  waiting for the rebuild: yield sums (combined yields show as empty meanwhile), the
  tie-corrected AUC and new model metrics, and fertiliser/pesticide reconciliation.
* The cause of the 20-30 point fertiliser and pesticide gaps is not established. Likely
  places to look: the denominator (plots in the input module vs all plots), skip-rule blanks
  set to "No", and module joins.
* No official cell was verified (site blocked). The 2026 workbooks are still in the
  repository but are no longer read; deleting them is your call.
* Shiny app (`SCRIPTS/app`) not run or tested. 07 and 12 now give it empty benchmarks and no
  NISR overlay.
* Not tested: screen readers, 200% zoom, a full contrast audit, usability with people with
  limited literacy (no such claim is made). Kinyarwanda and French still need a native check.

## 6. To finish on your computer

1. Use a fresh clone of this branch (not the Hackathon folder, which still holds the earlier
   upgrade you turned down), or apply `audit_fixes.patch` to a clean checkout of `master`.
2. Download into `DATA/NISR_published/`: SAS 2025 Annual Tables, the SAS 2019-2024 annual or
   seasonal tables, and the AHS 2024 tables. Names only need to match the patterns in
   `official_cell_map.csv` (for example `SAS*2025*Annual*Tables*.xlsx`).
3. Run `source("SCRIPTS/09_Run_All.R")`. It never pushes. Check the warnings from step 14.
4. Look at the site locally (`cd SCRIPTS/web; npm ci; npm run dev`) before deciding whether
   anything goes to `master`.

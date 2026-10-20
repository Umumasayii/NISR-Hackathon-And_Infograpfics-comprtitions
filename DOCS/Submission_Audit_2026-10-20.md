# Submission audit and upgrade log (2026-10-20)

SmartIrrigate Rwanda · Team NiyoIshimwe · NISR 2026 Big Data Hackathon, Track 1 (Agricultural Productivity)

This file records what was checked before the upgrade, what was found, and what was changed.
Everything marked **verified** was checked against a file or an official page on 2026-10-20.
Everything marked **not verified** still needs a person to check it.

## 1. Competition requirements (official brief)

Source: NISR, *2026 Hackathon Competition*, https://statistics.gov.rw/about/hackathon/2026-hackathon-competition (read 2026-10-20).

| Requirement | What the brief says | Where this repo answers it |
|---|---|---|
| Track | Track 1 Agricultural Productivity; small-scale irrigation is a suggested area; solutions must use NISR data, optionally with climate data | README "Competition track" |
| Eligibility | Teams of 2 undergraduate or master's students, at least one Rwandan citizen, proof of student status; past top-3 winners not eligible | **Only the team can confirm.** README marks it as "to be completed by the team" |
| Submission | Public GitHub repository link, deployed app link, documentation, signed originality declaration | README; the declaration is a separate signed document the team must provide |
| AI use | Allowed as an assistant; must be disclosed; team stays fully responsible; non-disclosure means disqualification | README "AI-use disclosure", app Methods > AI tab |
| Judging (100 pts) | 20 each: problem understanding & relevance, data use & methodology, tech innovation, usability & design, tangible impact | README maps each criterion to the app |
| Dates | Registration 20 Oct 2026 23:59; submission 30 Oct 2026 23:59; review 1–5 Nov; shortlist 13 Nov; awards 11 Dec | README |
| IP | Entrants assign all IP rights in the submission to NISR; NISR may use, modify and publish it | README "Licence and intellectual property" (no open-source licence file added, because it would conflict with the assignment) |

## 2. Repository and deployment state

* **Verified.** GitHub `master` is at commit `4291450`. The deployed site is the React/TypeScript app in `SCRIPTS/web`, hosted on Vercel (project root `SCRIPTS/web`, settings in `SCRIPTS/web/vercel.json`). Every file the build uses (`src/`, `public/`, `index.html`, `package.json`, `package-lock.json`, `vite.config.ts`, `tsconfig.json`) is tracked on `master`.
* **Verified.** The local folder on the team laptop was behind GitHub: its last local commit is `085b12c`, and its `SCRIPTS/web` copy matched the older commit `fd38de2` (before the redesign) and was untracked. The R scripts were identical to `master` apart from Windows line endings. Nothing in the local folder was lost or overwritten: the files written by this upgrade are `master` plus the changes below.
* **Verified.** `SCRIPTS/web/deploy-web.yml` exists only in the local folder (untracked). It is an old GitHub Pages workflow that conflicts with the Vercel set-up; it is not used by anything. Delete it when convenient.
* **Not verified.** Which commit Vercel production is serving today. Earlier checks found production serving an older commit; the site footer shows `v <commit>` so this can be checked in a browser.
* **Risk.** `SCRIPTS/12_Export_Web_Data.R` ends by calling `SCRIPTS/13_Push_To_GitHub.R`, which commits and pushes every change in the folder unless `SI_AUTO_PUSH=FALSE`. This upgrade did not change that default (it was a team decision), but 13 now refuses to commit microdata-type files even if `.gitignore` misses them. See README "Refresh the data".

## 3. Official statistics compared with the app

Indicator definitions matter: NISR publishes "% of farmers who practiced irrigation" (one farmer counted once). The app's main survey series is "% of plots irrigated" (each plot counted). These are different indicators and are never shown as one series.

### 3.1 Farmers who practiced irrigation (% of farmers, all farmer types)

| Season | NISR published | Source (table / page) | App survey estimate (95% CI) | Difference | Likely explanation |
|---|---|---|---|---|---|
| 2024A | 7.5% | SAS 2024 Annual Report, Executive summary, Table 0 | 6.1% (5.4–6.9) | −1.4 pts | Different farmer record: the app counts a farmer once from the plot file (weight = mean plot weight); NISR uses its own farmer weights. Published value is outside the app's CI, so the gap is not sampling noise alone. |
| 2024B | 12.1% | same | 11.4% (10.3–12.5) | −0.7 pts | Within ~1 pt; same reason. |
| 2024C | 58.2% | same | 54.5% (48.7–60.2) | −3.7 pts | Season C sample is small; published value is inside the CI. |
| 2025A | 13.4% | SAS 2025A Final report, Section 4.1, Figure 4 | 13.5% (12.4–14.7) | +0.1 pts | Agrees. |
| 2025B | not checked | SAS 2025 Annual Report could not be opened from the build environment | 10.9% | — | **Not verified.** Needs the SAS 2025 Annual Tables. |
| 2025C | not checked | same | 54.5% | — | **Not verified.** |
| 2026A | 14.4% (14.39) | SAS 2026A Tables, Table 31 | no microdata | — | Official only. |
| 2026B | 13.1% (13.08) | SAS 2026B Tables, Table 29 | no microdata | — | Official only. |

**How it is shown now:** the official figure is drawn as its own series ("NISR published", diamond markers) beside the app's survey line, with a reconciliation table on the Overview page and in Methods. The survey estimate keeps its own label and CI. Nothing is substituted silently, and the two series are never joined into one line.

### 3.2 Modern irrigation: two different definitions

* App survey 2019–2025: irrigated plots using a motorised pump or machine, drip, sprinkler or pivot ÷ irrigated plots (tool-based).
* NISR 2026 Tables (Table 32 in 2026A, Table 30 in 2026B, % of irrigated plots by type): "modern" = surface + flood + drip + sprinkler + pivot = 66.4% (2026A) and 56.9% (2026B). Drip + sprinkler + pivot alone = 17.1% in both seasons (6.57 + 7.54 + 3.02 and 5.53 + 7.25 + 4.35; the equal totals were checked cell by cell).
* NISR 2025A report (Section 4.1): 55.5% of **farmers who irrigated** used modern irrigation (a farmer-level share).

**Before:** the 2026 drip + sprinkler + pivot share was stored under the same indicator as the survey's tool-based share and shown in the same KPI and trend. **Now:** it is a separate indicator (`irrig_dsp_nisr`), shown only in the reconciliation table with its own definition; the "Modern irrigation" KPI and trend use the survey definition only.

### 3.3 Input use (plot-level): series break between 2025 and 2026

| Indicator (% of plots) | App survey 2025A | NISR 2026A (plot column) | NISR 2025A report (farmer level) |
|---|---|---|---|
| Inorganic fertiliser | 34.4% | 53.5% (Table 25) | 63.2% of farmers |
| Organic fertiliser | 70.1% | 76.1% (Table 24) | 88.0% of farmers |
| Pesticides | 19.6% | 43.8% (Table 29) | 41.9% of farmers |

The jump from 2025 (survey) to 2026 (official) is too large to be a one-season change; the most likely cause is a difference in plot definition or question routing between the app's plot file and NISR's tabulation. **Not explained yet.** The app now labels the 2026 points "different source, not a trend continuation", and trend text never compares a survey season with an official season.

### 3.4 Production and cultivated area

* National production 2024B, 2025A, 2025B: the app's survey totals were 2.1%, 8.9% and 4.1% below NISR's published totals. The published totals are shown (labelled "NISR published"); the survey totals stay in the downloads (`production_survey_t`).
* Several crops differ by 10% or more (listed in Methods > Definitions). Wheat and sweet potato showed the largest gaps.
* 2026 cultivated area is NISR's "physical cultivated land" (Table 9 / Table 7), which is not the same definition as the survey's sum of plot areas.
* **Mixed-source years.** In 2024 Season A production is a survey estimate and Season B is official. Year totals that add A + B now say "mixed: survey + official" next to the number.

## 4. Statistical-method findings

| # | Finding | Severity | Fix |
|---|---|---|---|
| S1 | The web app relabelled combined (multi-district) estimates "Good" from n and CV only, ignoring the number of survey clusters (PSUs) that the R pipeline requires (≥ 12 for Good, ≥ 5 at all). | High | `n_psu` is now exported and the web rule matches `00_Config.R`. A survey estimate with no standard error is "Not assessed". |
| S2 | AHS 2020 has no cluster identifiers; households are treated as PSUs, so its standard errors are too small and its "Good" labels are not supported. | High | 2020 AHS estimates are labelled "Not assessed" (pipeline and app); their CIs are not shown. |
| S3 | Trend text said a change "is real, not chance" when two 95% CIs did not overlap. | Medium | Rewritten as "the 95% intervals do not overlap" / "the intervals overlap, so the change may be sampling noise". |
| S4 | "Better seed is spreading" compared AHS 2020 with AHS 2024 across a questionnaire break (also "Inputs are spreading", "rose the most between the first and last round"). | High | Removed; practice changes are only compared within 2017–2020, and 2024 is described on its own. |
| S5 | "Irrigation is growing, but slowly", "Women and small farms are falling behind", "Irrigated plots give bigger harvests" stated causes or trends the data do not test. | Medium | Rewritten as descriptive or associational statements with the comparison named. |
| S6 | Logistic-model odds-ratio intervals come from an ordinary weighted `glm` (ignore clustering; weights rescaled), so they are too narrow. | Medium | The chart and its source line say the intervals are approximate and too narrow because survey clustering is not used. |
| S7 | "Fairness" panel only reports AUC and calibration gap by gender and province. | Medium | Renamed "Model accuracy by group"; text says no fairness criterion was tested. |
| S8 | "Prediction gap" map: district is a model feature and the model is trained on 2020–2023, so the gap mostly reflects change over time and model error, not unmet potential. | Medium | Retitled and explained. |
| S9 | Simulator "with land consolidation and fertiliser" read like a programme effect. | Medium | Now says the model's prediction for a different plot profile, not the effect of an intervention. |
| S10 | Priority "Chance of being in the top 5" and rank ranges are shares of 2,000 random weight sets, not probabilities. | Medium | Renamed "share of random weight sets"; formula, default weights and the missing feasibility inputs are shown on the page; text says weight changes do not include data uncertainty. |
| S11 | Harvest-change finding added survey years and official years. | Medium | Restricted to years from one source, or flagged as mixed. |
| S12 | Dry Season C text: "Farmers already know how to water in the dry season" (not measured). | Low | Rewritten. |
| S13 | Combined estimates in the browser use 1.96 instead of the design's t quantile. | Low | Kept (design df for combined areas is in the hundreds); documented in `SCRIPTS/web/src/lib/stats.ts`. |

## 5. Accessibility and readability findings

| # | Finding | Fix |
|---|---|---|
| A1 | Units, denominators, season, source and caveats only in hover or on Methods. | Every chart card and KPI on the decision path now has a visible source line: what is measured, unit and denominator, period, source with link, estimate type, key caveat. |
| A2 | No text or table alternative for charts and maps. | Each chart card has "Show the numbers" with an accessible table and CSV including source columns. Charts carry `role="img"` and a text label. |
| A3 | Reliability badges in amber and terracotta at 11px failed WCAG contrast (about 3.4:1 and 4.3:1). | Darker text colours (≥ 4.5:1) and an icon so status is not colour alone. |
| A4 | Table sorting by clicking a header cell was mouse-only. | Header buttons with `aria-sort`. |
| A5 | No skip link; language buttons gave no pressed state; the hidden filter drawer stayed in the tab order. | Skip link, `aria-pressed` + `lang` on language buttons, hidden drawer made `inert`. |
| A6 | Season, period, crop-group and stability series used colour alone. | Different marker shapes per series (Overview trend, province and production charts, rank-sensitivity chart); direction in the yield-gap and odds-ratio charts is also shown by marker shape. |
| A7 | Missing values all showed as "–". | "No data", "No microdata" and "Not comparable" are now written out in tables and the reconciliation panel; zero stays 0. |

## 6. Implementation checklist

- [x] Read the official brief; record track, eligibility, materials, AI disclosure, rubric, dates, IP
- [x] Compare displayed 2024–2026 irrigation figures with NISR reports and tables
- [x] Add a cited file of official headline figures (`DATA/NISR_published/nisr_report_headlines.csv`) and export it
- [x] Separate the NISR drip + sprinkler + pivot share from the survey's modern-irrigation indicator
- [x] Export `n_psu`, `survey_estimate`, `nisr_table` and source fields; align web reliability with the pipeline; add "Not assessed"
- [x] AHS 2020 reliability "Not assessed"
- [x] Source registry and visible source lines on charts, KPIs, maps and model outputs; source columns in CSV downloads
- [x] Reconciliation panel (official vs project estimate)
- [x] Rewrite causal, sensational and break-crossing claims (EN/FR/RW)
- [x] Model page: rename fairness, label intervals, explain prediction gap and simulator
- [x] Priority page: formula, weights, rationale, sensitivity wording, missing feasibility inputs
- [x] Opening screen: one decision question and a four-step path
- [x] Menus: decision path first, technical analysis under "Supporting analysis"
- [x] Accessibility fixes A1–A7
- [x] Root README with purpose, demo, track, data, method, reproducibility, AI disclosure, limitations, IP
- [x] Push-script guard against committing microdata
- [ ] **Team:** confirm eligibility, names of both members, and sign the originality declaration
- [ ] **Team:** check SAS 2025B and 2025C official irrigation figures (SAS 2025 Annual Tables) and add them to `nisr_report_headlines.csv`
- [ ] **Team:** native-speaker review of Kinyarwanda and French (see `DOCS/Translation_Review.md`)
- [ ] **Team:** GADM boundaries licence (see README "Data licences")
- [ ] **Team:** rerun `12_Export_Web_Data.R` once on the laptop to confirm the exported JSON matches (see README)
- [ ] **Team:** rerun `09_Run_All.R` so the Shiny app's own data also separates the NISR drip + sprinkler + pivot share (the committed `.rds` files predate this change; the web JSON was patched to match what the updated scripts produce)
- [ ] **Team:** the Shiny app (`SCRIPTS/app`) keeps its older wording; this upgrade changed the web app only
- [ ] **Team:** decide whether `12_Export_Web_Data.R` should keep pushing to GitHub by default (`SI_AUTO_PUSH`)
- [ ] **Team:** confirm the Vercel production deployment serves the latest `master` commit (footer version)
- [ ] Not run in this upgrade, by request: type check, build, tests, R pipeline, deploy

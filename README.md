# SmartIrrigate Rwanda

**Where could a district planner look first when deciding where irrigation field assessments are needed?**

SmartIrrigate Rwanda turns NISR farm-survey data and satellite rainfall records into a shortlist of
districts for irrigation field assessment. It shows where rain often falls short, who irrigates
today, what the data cannot tell you, and which districts rank first on a transparent, adjustable
screening score. It suggests where to look; it does not decide where to invest.

This is an independent team project for the NISR 2026 Big Data Hackathon. It is **not an official
NISR product, and NISR does not endorse its suggestions.**

| | |
|---|---|
| Live app | https://niyoishimwe.vercel.app (English, Kinyarwanda, French; works on phones and offline). The footer shows the build date and version, so you can check it matches the latest `master` commit. |
| Competition | NISR 2026 Big Data Hackathon, **Track 1: Agricultural Productivity** (small-scale irrigation) |
| Team | Team NiyoIshimwe. *Member names, student status and eligibility: to be completed by the team.* |
| Repository | https://github.com/Umumasayii/NISR-Hackathon-And_Infograpfics-comprtitions (branch `master`) |

## Contents

1. [What the app does](#what-the-app-does)
2. [Data sources](#data-sources)
3. [Methodology](#methodology)
4. [Limitations](#limitations)
5. [Reproduce the results](#reproduce-the-results)
6. [Deployment](#deployment)
7. [AI-use disclosure](#ai-use-disclosure)
8. [Data licences](#data-licences)
9. [Licence and intellectual property](#licence-and-intellectual-property)
10. [Judging criteria and where the app addresses them](#judging-criteria-and-where-the-app-addresses-them)

## What the app does

The opening screen asks one decision question and gives a four-step path:

1. **The problem:** where rain often falls short (Need page; CHIRPS rainfall 1981–2025).
2. **NISR evidence:** who irrigates today, by district and province (Map page; SAS 2019–2025 microdata and NISR published figures for 2024–2026).
3. **Limits:** what the data cannot tell you (Methods > Limitations).
4. **Shortlist:** districts to assess in the field first (Field-assessment shortlist page), with the formula, default weights, their rationale, a weight-sensitivity check and the feasibility inputs that are still missing.

Supporting analysis (yield comparisons, irrigation methods and costs, groups, household survey,
crop explorer and the adoption model) sits under "Supporting analysis" in the menu.

Every chart and number card states, next to it: what is measured and over whom (the
denominator), the period, the kind of number (project survey estimate, NISR published figure,
model output or team index), the source with a link, and the main caveat. Every chart has a
"Show the numbers" table and a CSV download that repeats those source fields on each row.

## Data sources

| Source | Used for | Link |
|---|---|---|
| NISR Seasonal Agricultural Survey (SAS) 2019–2025 microdata, Seasons A, B, C | Survey-weighted estimates computed by the team: irrigation, practices, yields, production, area | [NISR microdata catalogue](https://microdata.statistics.gov.rw/index.php/catalog) |
| NISR SAS 2024 Annual Report | Published share of farmers who practised irrigation, 2024 A/B/C (Table 0) | [PDF](http://www.statistics.gov.rw/sites/default/files/documents/2025-02/SAS%202024%20Annual.pdf) |
| NISR SAS 2025 Season A Final Report | Published share of farmers who irrigated, 2025A; modern irrigation among irrigating farmers; fertiliser use | [PDF](https://statistics.gov.rw/sites/default/files/documents/2025-05/SAS%202025A_Final%20%20report.pdf) |
| NISR SAS 2026 Season A Tables (released 28 April 2026) | 2026A published figures (no microdata), and published production for earlier seasons | [XLSX](https://statistics.gov.rw/sites/default/files/documents/2026-04/Tables_2026%20Season%20A.xlsx) |
| NISR SAS 2026 Season B Tables (released 22 September 2026) | 2026B published figures | [XLSX](https://statistics.gov.rw/sites/default/files/documents/2026-09/Tables_2026%20Season%20B.xlsx) |
| NISR Agricultural Household Survey (AHS) 2017, 2020, 2024 microdata | Household-level shares (irrigation, seed, fertiliser, services, finance) | [NISR microdata catalogue](https://microdata.statistics.gov.rw/index.php/catalog) |
| CHIRPS v2.0 monthly rainfall, 1981–2025 | Season rainfall, anomalies and the need score, averaged by district | [Climate Hazards Center](https://www.chc.ucsb.edu/data/chirps) |
| GADM 4.1 boundaries | District map shapes | [gadm.org](https://gadm.org/) |

Every NISR published figure shown in the app is listed with its publication, table and link in
`DATA/NISR_published/nisr_report_headlines.csv` (headline figures checked against the
publications on 2026-10-20) and in the published-table extract made by
`SCRIPTS/11_NISR_Published_Tables.R`. The app shows them as published and labels them "NISR
published"; project estimates are never substituted for them, and the two are never joined into
one series. The Overview page compares them side by side.

## Methodology

* **Survey estimates.** Design-based ratio estimates with the SAS weights, strata (district) and
  primary sampling units (segments), using the R `survey` package (`SCRIPTS/00_Config.R`,
  `SCRIPTS/07_Build_App_Data.R`). 95% confidence intervals use the design's t quantile.
* **Quality labels.** Reliable: n ≥ 50, at least 12 PSUs and CV ≤ 20%. Use with care: CV ≤ 35%.
  Not reliable: n < 30, fewer than 5 PSUs or CV > 35%. Not assessed: no design-based standard
  error (for example AHS 2020, which has no cluster identifiers). The labels follow
  `reliability()` in `SCRIPTS/00_Config.R`, and the web app applies the same rule when it
  combines districts.
* **Indicators are kept apart.** "% of plots irrigated" (survey, each plot counted), "% of farmers
  who irrigated" (NISR, each farmer counted once) and "% of farm households that irrigate" (AHS)
  have different denominators. "Modern irrigation" has three definitions (project tool-based,
  NISR's surface + flood + drip + sprinkler + pivot, and drip + sprinkler + pivot only); they are
  listed side by side and never joined.
* **Yield comparisons** are associations, not effects: a survey-weighted log-yield regression
  adjusted for fertiliser, improved seed, crop area, district and year-season
  (`SCRIPTS/08_Models.R`). 2024 Seasons B and C are left out because crop area is missing on most
  plots.
* **Adoption model.** Weighted logistic regression and a random forest, trained on 2020–2023 plots
  and tested on 2024–2025 plots (AUC, Brier score, calibration, performance by group). It
  describes what predicts irrigation; its intervals are approximate because survey clustering is
  not used.
* **Screening score.** Five parts, each rescaled 0–1 across the 30 districts, weighted and added:
  rainfall need (0.30), irrigation gap (0.30), cultivated area (0.20), gender gap (0.10) and
  current fertiliser use as a proxy for input access (0.10). Users can change the weights. A
  sensitivity check ranks districts under 2,000 random weight sets; it shows sensitivity to the
  weights, not uncertainty in the data. Water availability, schemes, infrastructure, costs and
  local conditions are not in the data, so the result is a shortlist for field assessment.

A full audit of figures, definitions and claims is in
[`DOCS/Submission_Audit_2026-10-20.md`](DOCS/Submission_Audit_2026-10-20.md).

## Limitations

* Survey estimates have sampling error; district and Season C estimates rest on fewer plots.
* 2026 figures come only from NISR published tables (no microdata) and are not used to claim a trend.
* For chemical fertiliser, organic fertiliser and pesticides, the 2026 published plot shares are
  much higher than the 2025 survey estimates; the cause is not yet explained, so no change is claimed.
* AHS 2024 used a new questionnaire and is not directly compared with 2017 and 2020.
* Production from 2024 Season B onward is the NISR published total; earlier seasons are project
  estimates, so years that mix both are flagged.
* Rainfall is a satellite estimate averaged over each district.
* The shortlist has not been validated in the field, and its weights are a team choice.
* French and Kinyarwanda texts are drafts that have not yet been reviewed by native speakers
  (see [`DOCS/Translation_Review.md`](DOCS/Translation_Review.md)).

## Reproduce the results

NISR microdata are not in this repository (see `.gitignore`); request them from the
[NISR microdata catalogue](https://microdata.statistics.gov.rw/index.php/catalog) and place them in
`DATA/SAS/` and `DATA/Agriculture Household Survey/`. Only aggregated tables are committed
(`SCRIPTS/app/data/*.rds`, `SCRIPTS/web/public/data/*.json`).

1. **R pipeline** (R with `dplyr`, `tidyr`, `purrr`, `stringr`, `readr`, `haven`, `labelled`,
   `survey`, `ranger`, `sf`, `readxl`, `jsonlite`), from the project root:

   ```r
   source("SCRIPTS/09_Run_All.R")              # 05 select, 06 merge, 07 app tables, 08 models
   source("SCRIPTS/10_AHS_Preparation.R")      # household survey
   source("SCRIPTS/11_NISR_Published_Tables.R") # NISR 2026 workbooks in DATA/NISR_published/
   Sys.setenv(SI_AUTO_PUSH = "FALSE")          # export without committing or pushing
   source("SCRIPTS/12_Export_Web_Data.R")      # writes SCRIPTS/web/public/data/*.json
   ```

   **Important:** without `SI_AUTO_PUSH = "FALSE"`, `12_Export_Web_Data.R` ends by running
   `SCRIPTS/13_Push_To_GitHub.R`, which commits and pushes every change in the folder to `master`
   (and so redeploys the site). That script refuses to commit microdata-type files (`.dta`,
   `.sav`, `.sas7bdat`, `.zip`, `.RData`, `.rds` under `DATA/`, and anything under `DATA/SAS`,
   `DATA/processed` or the AHS folder) and secrets (`.Renviron`, `.env`, keys) even if
   `.gitignore` changes.

2. **Web app** (Node.js 20 or newer):

   ```bash
   cd SCRIPTS/web
   npm ci
   npm run dev      # http://localhost:5173
   npm run build    # production files in SCRIPTS/web/dist
   ```

3. **Shiny app** (the original R dashboard): `shiny::runApp("SCRIPTS/app")`.

## Deployment

The live site is built by Vercel directly from this public repository: project root
`SCRIPTS/web`, production branch `master`, settings in `SCRIPTS/web/vercel.json` (`npm ci`,
`npm run build`, output `dist`). Nothing is uploaded by hand. `.github/workflows/web-build.yml`
builds the app on each push and pull request as a check. Other deployment files (for example an
old GitHub Pages workflow) are not used.

## AI-use disclosure

The hackathon allows AI tools if their use is disclosed. This project used **Claude (Anthropic)**
as an assistant for:

* drafting code for data preparation, the website, the Shiny app and the models, which the team
  reviews and runs;
* drafting documentation, page text, the data audit, and the French and Kinyarwanda translations
  (not yet reviewed by native speakers);
* looking up NISR published figures, each of which is linked to its source table so it can be
  checked.

Every project estimate comes from code run on NISR data; no number was typed in without
computation or a cited source. Any AI-generated image is labelled as such. The team remains fully
responsible for the submission. The same disclosure is in the app (Methods > AI use).

## Data licences

* **NISR data:** the competition terms state that NISR data are available under CC BY 4.0 unless
  otherwise indicated. Microdata are used under the NISR microdata access terms and are not
  redistributed here.
* **CHIRPS:** see the terms on the [Climate Hazards Center site](https://www.chc.ucsb.edu/data/chirps).
* **GADM:** GADM data are free for academic and other non-commercial use, and their licence does
  not allow redistribution without permission. This repository currently includes GADM files
  (`DATA/GADM/`) and a derived boundary file (`SCRIPTS/web/public/data/districts.json`).
  *To be resolved by the team:* ask GADM for permission, or replace them with boundaries whose
  licence allows redistribution.

## Licence and intellectual property

Under the competition terms, entrants assign the intellectual property rights in their
submission to NISR. No open-source licence file is included, because one would conflict with that
assignment. The team must also submit the signed originality declaration required by the
competition (*to be completed by the team*).

## Judging criteria and where the app addresses them

| Criterion (20 points each) | Where to look |
|---|---|
| Problem understanding and relevance | Opening question and four-step path; Need page |
| Data use and methodology | Methodology above; source line under every chart; Overview "NISR published figures and our estimates"; Methods |
| Technical innovation | Survey-weighted estimates in R, offline-capable trilingual web app, adjustable screening score with sensitivity check |
| Usability and design | Plain-language takeaways, table alternative and CSV for every chart, keyboard and screen-reader support, phone layout |
| Tangible impact | Field-assessment shortlist with the feasibility inputs still to collect; claims limited to what the data support |

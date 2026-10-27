# SmartIrrigate Rwanda: Dashboard Architecture (DRAFT v0.1)

> **Status: DRAFT, not final.** Nothing gets built until you confirm.
> Add anything you want in **Section 11 "Your additions"** at the bottom, then say "confirm" (or list changes) in the project thread.

Prepared 13 Oct 2026 for the NISR 2026 Big Data Hackathon, **Track 1: Agricultural Productivity** (small-scale irrigation is a named example area).

---

## 0. Key facts from the competition page that shape this design

| Fact | Consequence for the design |
|---|---|
| Registration deadline **20 Oct 2026**, submission deadline **30 Oct 2026, 23:59** | 17 days left. Scope below is split into "must have" (MVP) and "nice to have". |
| Submission = **public GitHub repo + deployed app link + documentation** | App must deploy online (shinyapps.io or Posit Connect Cloud), so it must run on small pre-aggregated files, not the 280 MB `.RData`. |
| Solutions "must be informed by NISR data", open data allowed | SAS (NISR) is the backbone; CHIRPS, GADM and later soil data are supporting open data. |
| AI tools allowed **only if disclosed** | A "Data & Methods" page and the README must contain an AI-use disclosure. Non-disclosure = disqualification. |
| 5 criteria × 20 points | Every page below is tagged with the criteria it earns points for (Section 9). |

---

## 1. The story (what judges should remember in 30 seconds)

**One-sentence pitch:** *Rwanda's farmers who irrigate harvest much more, yet only a small share irrigate and adoption varies by district; SmartIrrigate shows where, for whom and with which technology the next irrigated hectare will pay off most, and turns 7 years of NISR survey data into a district priority list for MINAGRI, RAB and districts.*

The dashboard follows a 4-act narrative, one act per navigation group:

1. **The gap** — How many farmers and how much land are irrigated, and how has it moved 2019–2025? (Where are we vs NST2 / PSTA5?)
2. **The need** — Where is rainfall short or unreliable (CHIRPS 1981–2025), and is irrigation happening where it is needed?
3. **The payoff** — Irrigated plots vs rain-fed plots: yield, value of sales, and the "modern package" effect (irrigation + improved seed + fertiliser + mechanisation).
4. **The action** — Irrigation Opportunity Index per district, a what-if simulator ("raise adoption in district X by 10 points → +Y tonnes"), and who is left behind (women, older farmers, steep eroded land).

> ⚠️ Policy targets: the NST2 (2024–2029) and PSTA5 irrigated-area targets must be quoted from the official documents with a citation. I have not verified the exact figures, so they are placeholders in the KPI design below.

---

## 2. Technology and layout

**Stack (default, R):** Shiny + `bslib` (Bootstrap 5), `leaflet` (maps), `plotly` or `echarts4r` (interactive charts), `reactable` (tables), `srvyr`/`survey` (weighted estimates), `sf` (map), `bsicons` (KPI icons), optional `shiny.i18n` (English / Kinyarwanda).

**Page shell:** `bslib::page_navbar()` with one shared, collapsible **left sidebar** of global filters, a top navbar of pages, and a NISR-friendly theme (blue/green, Rwanda flag accents, readable fonts, light/dark toggle).

```
┌──────────────────────────────────────────────────────────────────────────┐
│ SmartIrrigate Rwanda   Overview | Where | Need | Payoff | How | Who | Plan | Methods   [EN|RW] [☾] │
├──────────────┬───────────────────────────────────────────────────────────┤
│ SIDEBAR      │  KPI cards row (value boxes)                             │
│ Global       │ ┌─────────┬─────────┬─────────┬─────────┐                │
│ filters      │ └─────────┴─────────┴─────────┴─────────┘                │
│              │  Main visual (map / chart)      │  Side visual / insight │
│ Page-        │                                 │  "What this means" box │
│ specific     │  Secondary visuals / table                               │
│ controls     │  Footnote: source, weighting, n (unweighted)              │
│ (accordion)  │                                                           │
│ [Download]   │                                                           │
└──────────────┴───────────────────────────────────────────────────────────┘
```

Design rules: every chart has a one-line **plain-language takeaway** above it, a **source + n** footnote below it, and a download button. Max 4 KPI cards per page. Consistent colour: irrigated = one teal, rain-fed = one sand/grey across all pages.

---

## 3. Sidebar and filters

### 3.1 Global filters (top of sidebar, apply to every page)

| Filter | Widget | Values | Source column |
|---|---|---|---|
| Agricultural year range | `sliderInput` (range) | 2019 – 2025 | `sas_year` |
| Season | checkbox group | A, B, C (default A + B) | `sas_season` |
| Province | `selectInput` | All, Kigali, North, South, East, West | `province` |
| District | `selectizeInput` (filtered by province) | 30 districts | `district_std` |
| Crop group | `selectInput` | All, cereals, tubers/roots, legumes, vegetables, fruits, industrial | `crop_category` / `cropgroup` (`irr_crop_prod`) |
| Farmer gender | radio | All, Female, Male | `gender` |

Clicking a district on any map also sets the District filter (cross-filtering). A "Reset filters" button sits at the bottom.

### 3.2 Page-specific controls (accordion under the global filters, appears only on that page)

| Page | Controls |
|---|---|
| Where (map) | Metric to map: % plots irrigated / % farmers irrigating / irrigated ha / change since 2019; unit: plot vs area weighted |
| Need (rainfall) | Season window; baseline period (1991–2020 default); indicator: total, anomaly %, SPI |
| Payoff | Crop (single); outcome: yield kg/ha or sales value RWF/ha; comparison: raw vs adjusted (matched) |
| How | Breakdown: technique / water source / tool; show cost per ha |
| Plan | Weight sliders for each index component; adoption increase (pp) for the what-if |

### 3.3 Always-visible notes in the sidebar
"Estimates are survey-weighted (NISR SAS). Season C covers mostly marshland/valley crops and has a smaller sample." Plus last update date.

---

## 4. Pages, visuals and the exact data behind each

Table names refer to the outputs of `SCRIPTS/05_Select_Irrigation_Data.R` (`irr_agri_prac`, `irr_crop_prod`, `irr_fert_pest`, `irr_crop_screen`, `irr_erosion`, `irr_agrofor`, `irr_rainfall`, `irr_districts`, later `irr_soil`). Harmonised columns: `district_std`, `weight_std`, `plot_area_ha_std`. Join key between modules: `segment_id + plot_number + sas_year + sas_season`.

### Page 1 — Overview ("The gap")  · MVP
| Visual | Type | Data / columns | Calculation |
|---|---|---|---|
| KPI 1: Plots irrigated (latest season) | value box + sparkline | `irr_agri_prac`: `plot_irrigated_this_season`, `weight_std` | weighted % of cultivated plots = Σw·[irrigated] / Σw |
| KPI 2: Irrigated area (ha) | value box | + `plot_area_ha_std` | Σ w·area·[irrigated] |
| KPI 3: Farmers irrigating any plot | value box | `irrigation_any_plot_this_season` (2020+) | weighted % of farmers |
| KPI 4: Yield premium of irrigated plots | value box | `irr_crop_prod` joined to agri_prac (see Page 4) | (yield_irr − yield_rainfed) / yield_rainfed, all crops or chosen crop |
| National trend | line chart, 21 seasons | KPI 1 by `sas_year`, `sas_season` | one line per season A/B/C, 95% CI ribbon |
| Mini-map | small choropleth | KPI 1 by `district_std` + `irr_districts` | click → goes to Where page |
| Progress vs target | bullet / gauge | KPI 2 vs NST2/PSTA5 target (**to verify**) | % of target reached |
| "3 things to know" box | text | generated from the numbers above | auto sentences (e.g. "Irrigation is highest in X, lowest in Y") |

### Page 2 — Where ("Irrigation map")  · MVP
| Visual | Type | Data / columns | Calculation |
|---|---|---|---|
| District choropleth | `leaflet` | `irr_districts` (GADM level 2) + district aggregates | metric chosen in sidebar; tooltip shows value, CI, unweighted n |
| District ranking | horizontal bar (30 bars) | same aggregate | sorted, highlighted selected district |
| Change map 2019→2025 | choropleth (diverging palette) | KPI 1 per district for first vs last 2 seasons | percentage-point change |
| District profile drawer | card on click | all pages' district values | irrigation %, main technique, main water source, rainfall anomaly, yield premium, index rank |

### Page 3 — Need ("Rainfall and climate risk")  · MVP
| Visual | Type | Data / columns | Calculation |
|---|---|---|---|
| Season rainfall anomaly map | choropleth | `irr_rainfall` (CHIRPS district-month), season mapping A = Sep–Feb, B = Mar–Jun, C = Jul–Aug (**please confirm calendar**) | (season total − 1991–2020 mean) / mean |
| Long-run rainfall + trend | line, 1981–2025 | `irr_rainfall` for selected district | season totals, LOESS or Sen's slope trend |
| Drought frequency | bar per district | `irr_rainfall` | % of seasons with SPI < −1 since 1981 |
| **Need vs action** scatter | scatter (30 points) | x = rainfall deficit/variability (CV); y = KPI 1 per district | quadrant lines at medians; top-left quadrant = "high need, low irrigation" districts, labelled |
| Irrigation vs rainfall over time | dual line | KPI 1 and season rainfall anomaly by season | shows whether farmers irrigate more in dry seasons |

### Page 4 — Payoff ("Does irrigation pay?")  · MVP (core evidence)
| Visual | Type | Data / columns | Calculation |
|---|---|---|---|
| Yield irrigated vs rain-fed by crop | dumbbell chart | `irr_crop_prod`: `crop_name`, `harvested_quantity` (+ `unit_of_measurement`), `harvested_crop_area`/`plot_area_ha_std`, `weight_std`; irrigation from `plot_irrigated_this_season` (crop_prod 2023+, joined from agri_prac 2019–2022) | weighted median & mean kg/ha per group; CI |
| Sales value per ha | dumbbell or bar | `quantity_sold`, `selling_price` | gross sales value RWF/ha (not net income; labelled clearly) |
| **Adjusted** irrigation effect | coefficient/forest plot | crop_prod + agri_prac + fert_pest + erosion | propensity-score matching or weighted regression of log(yield) on irrigation controlling crop, season, district, fertiliser, improved seed, erosion, plot size; shown next to the raw gap (**Tech Innovation + Methodology points**) |
| "Modern package" yield ladder | step/bar chart | irrigation, `improved_seed`/`type_of_seeds`, fertiliser use (`irr_fert_pest`), mechanisation (`plough`/`tractor` cols) | yield for 0, 1, 2, 3, 4 modern inputs combined |
| Production compared to normal | stacked bar | `how_do_you_compare` / `compare_the_production` | irrigated vs not, share reporting "better than normal" |

### Page 5 — How ("How farmers irrigate")  · MVP
| Visual | Type | Data / columns | Calculation |
|---|---|---|---|
| Technique mix over time | 100% stacked area | `irrigation_technique` (21 seasons) | weighted shares among irrigated plots |
| Water source mix | treemap or bar | `irrigation_water_source` + multi-answer cols `_s4q15_*`, `_s4q17_*`, `_s4q16_*` | count "any mention" per source |
| Tool / technology ladder | ordered bar | `irrigation_tool` (+ multi-answer cols) | ordered watering can → jerrycan → channels → motor pump → sprinkler/drip/pivot; % on "modern" rungs |
| Cost of irrigation | box plot by technique | `irrigation_cost_rwf`, `plot_area_ha_std` | RWF per ha, weighted median |
| District × technique heatmap | heatmap | technique by `district_std` | shares |

### Page 6 — Who ("Who is left behind")  · Nice to have (strong for Impact)
| Visual | Type | Data / columns | Calculation |
|---|---|---|---|
| Gender gap | bar with CI | `gender`, irrigation flag | % irrigating, female vs male, trend |
| Age bands | bar | `age_years` → bands (<35, 35–54, 55+) | % irrigating |
| Land & soil constraints | bar | `irr_erosion` / erosion cols (degree of erosion, anti-erosion works, land consolidation) | irrigation % by erosion degree / consolidated vs not |
| Plot size | bar | `plot_area_ha_std` quintiles | irrigation % by plot size |
| Climate-smart overlap | bar | `irr_agrofor`, agroforestry cols | agroforestry and irrigation together |

### Page 7 — Plan ("Where to invest next")  · MVP (this is what wins Impact points)
| Visual | Type | Data / columns | Calculation |
|---|---|---|---|
| **Irrigation Opportunity Index (IOI)** map | choropleth | district aggregates from pages 2–5 | IOI = weighted sum of min-max scaled components: rainfall need (deficit/CV, drought freq.), adoption gap (low KPI 1), yield payoff (district or crop premium), cultivated area at stake (`irr_crop_screen` area), feasibility (water source availability, low erosion, land consolidation), later soil (`irr_soil`). Weights adjustable with sliders; defaults documented |
| Ranked priority table | `reactable` | same | rank, components, sparkline; CSV download |
| What-if simulator | value boxes + bar | district irrigated area, yield premium per crop | "+X pp adoption in district D" → extra ha irrigated → extra tonnes and extra RWF (using adjusted premium, with range) |
| Adoption model (optional) | partial-dependence / variable importance | plot-level agri_prac + joins | logistic regression or random forest/XGBoost predicting `plot_irrigated_this_season`; show drivers and "plots that look like irrigators but are not" by district |

### Page 8 — Methods & Data  · MVP (required for Methodology + disclosure)
Sources and links (NISR SAS 2019–2025, CHIRPS, GADM, soil if added), processing pipeline diagram (`03` → `04` → `05` → `06_Build_Dashboard_Data.R` → app), weighting approach, definitions of every KPI, limitations (survey is plot-level, self-reported, season C small sample, question wording changes across years, gross not net value), **AI-use disclosure**, team, GitHub link, data download.

---

## 5. KPIs (the numbers judges should see first)

| # | KPI | Definition | Source | Page |
|---|---|---|---|---|
| 1 | Plots irrigated (%) | weighted share of cultivated plots irrigated this season | agri_prac | 1, 2 |
| 2 | Irrigated area (ha) | Σ weight × plot area × irrigated | agri_prac | 1, 7 |
| 3 | Farmers irrigating (%) | weighted share of farmers with any irrigated plot (2020+) | agri_prac | 1 |
| 4 | Yield premium (%) | (irrigated − rain-fed yield) / rain-fed, raw and adjusted | crop_prod + joins | 1, 4 |
| 5 | Modern irrigation share (%) | share of irrigated plots using motor pump / sprinkler / drip / pivot | agri_prac | 5 |
| 6 | Rainfall anomaly (%) | latest season vs 1991–2020 normal | CHIRPS | 3 |
| 7 | High-need, low-irrigation districts (count) | top-left quadrant of need-vs-action | CHIRPS + agri_prac | 3, 7 |
| 8 | Gender irrigation gap (pp) | male % − female % | agri_prac | 6 |
| 9 | Potential gain (tonnes / RWF) | from what-if at default +10 pp | derived | 7 |
| 10 | Progress to NST2 irrigation target (%) | KPI 2 / target (**target to verify**) | NST2 doc | 1 |

---

## 6. Data pipeline for the app (what still needs writing)

```
DATA/SAS (raw) ─▶ 03_Data_Preparation.R ─▶ DATA/processed/*.rds
               ─▶ 04_Load_Data.R ─▶ 05_Select_Irrigation_Data.R ─▶ DATA/processed/selection/irr_*.rds
               ─▶ 06_Build_Dashboard_Data.R  (NEW: survey-weighted aggregates, joins, index, model)
               ─▶ app/data/*.rds  (small, < 20 MB total) ─▶ app/app.R (Shiny, deployed)
```

Planned aggregate tables in `app/data/` (one row per…):

| File | Grain | Main columns |
|---|---|---|
| `nat_season.rds` | year × season | irr_plot_pct, ci_low, ci_high, irr_area_ha, irr_farmer_pct, n |
| `dist_season.rds` | district × year × season | same as above + province |
| `tech_mix.rds` | (district) × year × season × technique/source/tool | share, n |
| `yield_compare.rds` | crop × irrigated × year × season (× district) | yield_kg_ha (mean, median), sales_rwf_ha, n |
| `effect_model.rds` | crop | raw premium, adjusted premium, CI |
| `rain_season.rds` | district × year × season (1981–2025) | rain_mm, anomaly_pct, spi |
| `equity.rds` | group var × level × year × season | irr_pct, ci, n |
| `ioi.rds` | district | components, IOI score, rank |
| `districts_simplified.rds` | district | simplified `sf` geometry (`rmapshaper::ms_simplify`) for fast maps |

Statistical rules: `srvyr::as_survey_design(ids = segment_id, strata = stratum, weights = weight_std)`; suppress or grey out cells with unweighted n < 30; harmonise yield units via `unit_of_measurement` before computing kg/ha.

---

## 7. Infographics (built from the same aggregate tables)

1. **"Rwanda's irrigation in one page"** — KPI 1–3, national trend sparkline, map, technique icons.
2. **"Water pays"** — yield premium per crop (dumbbell), modern-package ladder.
3. **"Where to act"** — IOI map with top-5 districts and their reasons.
4. **"Who is left behind"** — gender and age gaps.

Made with `ggplot2` + `patchwork` + `ggtext` (or Canva using exported numbers), exported as PNG/PDF at A4 and social size; also linked on the Methods page.

---

## 8. Build order (fits the 30 Oct deadline)

| Days | Work |
|---|---|
| 13–15 Oct | Confirm this draft; run 03→05 on all 111 files; write `06_Build_Dashboard_Data.R` (Pages 1–3 aggregates) |
| 16–19 Oct | App shell (navbar, sidebar, theme) + Pages 1, 2, 3; deploy a first version early (find deployment problems early). **Register by 20 Oct** |
| 20–24 Oct | Pages 4, 5, 7 (payoff, how, IOI + what-if); adjusted effect model |
| 25–27 Oct | Page 6, Methods page, infographics, Kinyarwanda labels if time |
| 28–29 Oct | Testing on phone/laptop, README, documentation, AI disclosure, final deploy |
| 30 Oct | Submit before 23:59 (buffer: aim for 29 Oct) |

---

## 9. How each criterion is earned

| Criterion (20 pts each) | What in the dashboard earns it |
|---|---|
| Problem understanding & relevance | 4-act story, NST2/PSTA5/Vision 2050 targets on Overview, "need vs action" quadrant |
| Data use & methodology | 7 years × 3 seasons of NISR SAS harmonised, survey-weighted estimates with CIs, CHIRPS 45-year baseline, transparent Methods page and reproducible GitHub pipeline |
| Tech innovation | Satellite rainfall (CHIRPS) + survey fusion, matched/adjusted yield effect, adoption ML model, adjustable Opportunity Index, what-if simulator |
| Usability & design | One shared sidebar, cross-filtering map, takeaway sentence per chart, mobile-friendly bslib, downloads, EN/RW toggle |
| Tangible impact | Ranked district investment list with reasons and downloadable table, aimed at MINAGRI, RAB, districts and partners |

---

## 10. Open questions for you (answer when you confirm)

1. **Deployment:** shinyapps.io (free, 25 active hours/month) or Posit Connect Cloud? *I recommend Posit Connect Cloud* (deploys straight from the public GitHub repo, which is also a required deliverable).
2. **Kinyarwanda toggle:** include? *I recommend yes, labels only, if time allows* (strong for usability and impact).
3. **Season calendar:** is A = Sep–Feb, B = Mar–Jun, C = Jul–Aug correct for mapping CHIRPS to SAS seasons?
4. **ML model on Page 7:** include the adoption model, or keep only the index + simulator? *I recommend include, as a simple logistic regression first.*
5. **Pages 6 ("Who") and the soil layer:** MVP or nice-to-have? *I recommend nice-to-have.*

---

## 11. ✍️ Your additions

> Write anything you want added, removed or changed below. Examples: extra pages, specific charts, a different colour theme, your team name/logo, NST2 numbers you already have, crops to focus on, things judges asked for in coaching, Python parts you want to include.

### Pages or visuals to add

- 

### Things to remove or change

- 

### Data I want to bring in (extra datasets, targets, documents)

- 

### Design / branding (name, logo, colours, language)

- 

### Answers to Section 10 questions

1. 
2. 
3. 
4. 
5. 

### Anything else

- 

---
*When you're done, reply "confirm" in the thread (or tell me what to change) and I'll produce the final version and start the build plan.*

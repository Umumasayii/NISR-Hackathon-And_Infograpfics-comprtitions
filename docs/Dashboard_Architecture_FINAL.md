# SmartIrrigate Rwanda: Dashboard Architecture (FINAL v1.1)

> **v1.1 (2026-10-13):** Section 13 additions from Team NiyoIshimwe folded in, and the first working build (v0.1) is in `SCRIPTS/` and `SCRIPTS/app/`. Where v1.1 and earlier sections disagree, Sections 13 and 14 win.

> **Status: FINAL v1.0, built on your answers of 13 Oct 2026.** Section 13 "Your additions" is still open: anything you write there goes into v1.1 before we start building the app.
> Supersedes `Dashboard_Architecture_DRAFT.md` (kept for reference).

**Competition:** NISR 2026 Big Data Hackathon, Track 1 Agricultural Productivity (small-scale irrigation is a named example).
**Deadlines:** registration **20 Oct 2026**, submission **30 Oct 2026, 23:59**. **Deliverables:** public GitHub repo + deployed app + documentation. AI use must be disclosed.

**Your decisions (locked):**

| # | Decision |
|---|---|
| 1 | Deploy on **shinyapps.io** |
| 2 | Three languages: **English, Kinyarwanda, French** |
| 3 | Season calendar: **A = Sep–Feb** (long rains, main season), **B = Mar–Jun**, **C = Jul–Sep** (dry season, marshlands / irrigated) |
| 4 | **Include** the ML adoption model |
| 5 | "Who is left behind" page and soil layer are **nice-to-have** |
| 6 | Agriculture colours, smart icons, good fonts, many readable pages, smart interpretation, Plotly charts |
| 7 | Merge the data into common-feature master tables, so you see overall production and measures, then filter (**done separately: `SCRIPTS/06_Merge_Master_Data.R`**) |

---

## 1. What the data already says (first pass from the merged master tables)

These come from running `06_Merge_Master_Data.R` on your `irr_*` tables. They are survey-weighted but **not yet reviewed**, so treat them as working numbers that show the story the dashboard will tell.

| Finding | Number | Where it comes from |
|---|---|---|
| Irrigation is rare in the main seasons | **1.2–3.7%** of cultivated plots irrigated in Seasons A and B; highest is 2025A (3.7%) | `master_national_season$irrigated_plot_pct` |
| Season C is the irrigation season | **26–53%** of Season C plots are irrigated | same |
| Irrigated land in a main season | about **50,000 ha** in 2025A, up from about 35,000 ha in 2019A | `irrigated_area_ha` |
| Irrigation is mostly manual | only **6–15%** of irrigated plots use pumps, machines, sprinklers, drip or pivots | `modern_irrig_pct` |
| Irrigation pays for maize and rice | Maize, A+B seasons 2019–2025 (median): **≈2,300 kg/ha irrigated vs ≈1,400 rain-fed (+60%)**. Paddy rice: **+29%**. Beans: +13%. | `master_crop_season$yield_*` |
| Not every crop gains (raw comparison) | Irish potato −12%, cassava −5% | same; needs the adjusted model (Section 7) |
| Women irrigate less | 2025A: **2.8% of women's plots vs 4.1% of men's** | `irrig_female_pct`, `irrig_male_pct` |
| Fertiliser is used much more than machines | inorganic fertiliser on ~30% of Season A plots; mechanisation below 1% of plots | `inorganic_fert_pct`, `mechanised_pct` |

**The pitch that follows:** *Irrigation lifts maize yields by more than half, yet only 1 in 30 plots is irrigated in the main seasons, and almost all of that is done with cans and jerrycans. SmartIrrigate shows where the next irrigated hectare pays most, who is being left behind, and ranks districts for investment.*

---

## 2. Data pipeline (what feeds the app)

```
DATA/SAS (111 raw files) ─▶ 03_Data_Preparation.R ─▶ DATA/processed/SAS/*.rds
                         ─▶ 04_Load_Data.R ─▶ 05_Select_Irrigation_Data.R ─▶ DATA/processed/selection/irr_*.rds
                         ─▶ 06_Merge_Master_Data.R  (NEW, done)  ─▶ DATA/processed/master/master_*.rds/.csv
                         ─▶ 07_Build_App_Data.R     (next)       ─▶ app/data/*.rds  (small, fast)
                         ─▶ 08_Models.R              (next)      ─▶ app/data/model_*.rds
                         ─▶ app/ (Shiny + bslib)  ─▶ shinyapps.io
```

### 2.1 Master tables (from `06_Merge_Master_Data.R`, tested on your data)

| Table | Rows | One row per | Used by pages |
|---|---|---|---|
| `master_crop_plot` | 535,952 | crop × plot × season | Payoff, Model, Who |
| `master_plot` | 264,781 | plot × season | Overview, How, Who, Model |
| `master_national_season` | 21 | season | Overview |
| `master_district_season` | 658 | district × season (+ rainfall) | Map, Need, Plan |
| `master_crop_season` | 1,243 | crop × season | Payoff, Production |
| `master_crop_district_season` | 14,938 | crop × district × season | Production, Plan |
| `master_rain_district_season` | 4,020 | district × season, 1981–2025 | Need |

All tables share the same **common features**: `sas_year`, `sas_season`, `province`, `district_std`, `crop_name`, `crop_group`, `irrigated`, `gender`, so every filter in the sidebar works on every page. `filter_master()` and `summarise_measures()` in the script give the same "overall, then filtered" view in R.

### 2.2 Common measures available everywhere

| Group | Columns (plot / crop level) | Aggregate measures |
|---|---|---|
| Irrigation | `irrigated`, `irrig_any_farmer`, `irrig_technique`, `irrig_source`, `src_*`, `irrig_tool`, `irrig_tool_level`, `irrig_modern`, `irrig_cost_rwf` | `irrigated_plot_pct`, `irrigated_area_ha`, `irrigated_area_pct`, `farmers_irrig_pct`, `modern_irrig_pct`, `irrig_cost_rwf_ha` |
| Production | `harvest_kg`, `crop_area_ha`, `yield_kg_ha`, `yield_ok` | `production_t`, `crop_area_ha`, `yield_kg_ha`, `yield_irrigated_kg_ha`, `yield_rainfed_kg_ha`, `yield_premium_pct` |
| Market | `sold_kg_plot`, `price_rwf_kg`, `sales_value_rwf`, `sold_share` | `sold_t`, `sold_share_pct`, `price_rwf_kg`, `sales_value_mrwf` |
| Modern inputs | `improved_seed`, `organic_fert`, `inorganic_fert`, `pesticide`, `micronutrient`, `oxen`, `tractor`, `mechanised`, `modern_inputs_n` | `improved_seed_pct`, `inorganic_fert_pct`, `organic_fert_pct`, `pesticide_pct`, `mechanised_pct`, `tractor_pct` |
| Land | `plot_area_ha`, `erosion_degree`, `anti_erosion`, `land_consolidated`, `agroforestry` | `severe_erosion_pct`, `anti_erosion_pct`, `land_consolidated_pct`, `agroforestry_pct` |
| People | `gender`, `age_years`, `age_band`, `farmer_type` | `female_plot_pct`, `irrig_female_pct`, `irrig_male_pct` |
| Climate | — | `rain_mm`, `rain_normal_mm`, `rain_anomaly_pct`, `rain_std_anomaly`, `dry_season_flag` |

### 2.3 Data traps fixed in the merge (put these on the Methods page, judges reward this)

1. **Skip pattern:** from 2020, "was this plot irrigated?" is asked only if the farmer irrigated any plot, so ~90% of plots were NA. They are now "No". The same fix applies to fertiliser, pesticide, micronutrients, mechanisation and anti-erosion.
2. **Wrong labels:** in 2022A–C and 2025A–B the irrigation tool codes carried the water-source labels. They are relabelled by code position, and the counts then match neighbouring years.
3. **Multi-answer codes:** in 2021 and 2025A–B, source and tool were stored as digit strings ("13"). They are decoded.
4. **Weights:** 2019 crop production has no weights and 2021C has half. The weights now come from the same plot in agricultural practices.
5. **Crop area:** this has 7 different names. In 2021 the "crop area" was the whole plot area repeated for each crop, so crop screening is used instead. 2024 crop area comes from crop screening, and a crop's area is capped at its plot area.
6. **Joins:** plots are matched on the best key per season (segment + plot, or district + stratum + segment number + plot in 2022C, or segment + farmer in 2024C). All match rates are in `master_join_log.csv`, and the main joins (crop production to plot practices, and fertiliser) are ≥ 87% in every season. The weak ones are agroforestry and the plot-area fallback in some C seasons.
7. **Districts:** "Nyarugenege" is fixed to Nyarugenge, so all 30 districts join to CHIRPS and the map.

**Known limits** (shown in the app's footnotes): 2024B and 2024C crop area is incomplete, so their yields are greyed out. 2019 has no gender. Sold quantity is capped at the plot harvest. Season C samples are small.

---

## 3. Look and feel

### 3.1 Theme (bslib)

```r
theme <- bslib::bs_theme(
  version = 5, preset = "shiny",
  primary = "#2E7D32",  secondary = "#1565C0",  success = "#2E7D32",
  warning = "#B7791F",  danger = "#C0504D",     info = "#00897B",
  bg = "#FBFBF7", fg = "#1E2A1E",
  base_font    = bslib::font_google("Inter"),
  heading_font = bslib::font_google("Poppins", wght = c(500, 600, 700)),
  code_font    = bslib::font_google("JetBrains Mono"),
  "border-radius" = "0.75rem", "card-border-width" = "0")
```

* **Fonts:** Poppins for headings and Inter for body text. Both cover French and Kinyarwanda characters and stay readable on phones. Numbers in KPI cards use tabular figures (`font-variant-numeric: tabular-nums`).
* **Dark mode:** `bslib::input_dark_mode()` in the navbar, with dark colours stepped from the same hues (below).
* **Layout:** cards with soft shadows, a 1rem gap and full-screen buttons on every chart card (`card(full_screen = TRUE)`).

### 3.2 Agriculture colour system (validated for colour blindness, light and dark)

Validated with the data-viz palette checker: lightness band, chroma, colour-blind separation (worst adjacent ΔE 8.6), normal-vision separation and contrast all **PASS** in both modes.

| Slot | Meaning | Light | Dark |
|---|---|---|---|
| 1 | Leaf green: crops, irrigated, "good" | `#2E7D32` | `#43A047` |
| 2 | Water blue: water, rain, irrigation sources | `#1565C0` | `#3B8FD9` |
| 3 | Harvest gold: production, yield, market | `#B7791F` | `#C08A1E` |
| 4 | Sorghum purple: people / equity | `#6A4C93` | `#9C7FD1` |
| 5 | Terracotta: soil, erosion, risk | `#C0504D` | `#E06B5F` |
| 6 | Teal: inputs, technology | `#00897B` | `#1F9E8F` |

Rules:
* **Irrigated vs rain-fed is always green vs grey (`#9E9E8E`)** on every page.
* Maps use **one hue light → dark** (greens for irrigation, blues for rain, golds for production). Rainfall anomaly uses a **diverging** brown ↔ grey ↔ blue scale (dry ↔ normal ↔ wet).
* Colours follow the entity, not its rank. Maize keeps its colour whatever the filter, and series above 6 fold into "Other".
* Text is never coloured like the series. Every coloured mark also has a label or legend.

### 3.3 Smart icons (`bsicons` + `fontawesome`)

| Concept | Icon |
|---|---|
| Irrigation / water | `droplet-half`, `fa-faucet-drip` |
| Rainfall | `cloud-rain` |
| Crops / yield | `fa-seedling`, `fa-wheat-awn` |
| Production / market | `basket`, `cash-coin` |
| Machines | `fa-tractor` |
| Fertiliser | `fa-flask` |
| Map / district | `geo-alt` |
| People | `people`, `fa-person-dress` |
| Trend up / down | `arrow-up-right` / `arrow-down-right` (green / terracotta, always with a sign and label) |
| Model / AI | `cpu` |
| Warning / data note | `info-circle` |

### 3.4 Plotly chart standard (one helper, every chart)

`plotly_theme(p)` applies the same template to every chart. It sets thin lines (2px), markers of 8px or more, a light grid and no dual axes. Hover uses `hovertemplate` with units and the unweighted *n*, for example "Maize · 2025A<br>Yield: 2,512 kg/ha<br>n = 274 plots". It shows a reduced modebar (download PNG, zoom, reset) and `config(locale = "fr")` when French is chosen. Charts render with `toWebGL()` when there are more than 5,000 points.

### 3.5 Smart interpretation (on every chart)

Each chart card has a one-line **"What this means"** box above it and a **"Read more"** expander. The text is generated in R from the filtered numbers by rule-based templates in three languages, so it updates with every filter. Rules include:
* **Trend:** if the change between the first and last season exceeds the 95% CI, write "rose / fell by X points since 2019". Otherwise write "stayed stable".
* **Ranking:** name the top and bottom 3 districts, with their values.
* **Gap:** compare irrigated vs rain-fed yield, saying whether the gap is significant (from survey CIs) or "not clear for this filter".
* **Data guard:** if unweighted n < 30, write "Too few plots to say for this filter" and grey the chart.
* **Benchmark:** compare the selected district with the national value.

Example output: *"In Bugesera, 6.1% of plots were irrigated in 2025A, above the national 3.7%. Irrigated maize yielded 2,500 kg/ha compared with 2,000 kg/ha on rain-fed plots."*

### 3.6 Three languages

* `shiny.i18n` with one `i18n/translations.json` holding the `en`, `rw` and `fr` keys for every label, menu, KPI, footnote and interpretation template.
* A language switcher (EN | RW | FR) sits in the navbar. The choice persists across pages, and `update_lang()` re-renders titles and Plotly axis labels.
* Crop, district and category labels have their own translation table, `i18n/labels.csv`. District names stay as they are.
* **A native speaker must review the Kinyarwanda and French text before submission.** I'll draft them, then flag them for review in the repo.

---

## 4. Navigation and sidebar

### 4.1 Page shell

`bslib::page_navbar()` with a shared collapsible left **sidebar** (`sidebar(open = "desktop")`, closed on phones), navbar menus grouped by the story, and a footer with sources, last update and the GitHub link.

```
[🌱 SmartIrrigate Rwanda]  Home | Story ▾ | Analyse ▾ | Act ▾ | About ▾       [EN|RW|FR] [☾]
 Story:   1 Overview · 2 Irrigation Map · 3 Rain & Climate
 Analyse: 4 Production Explorer · 5 Does Irrigation Pay? · 6 How Farmers Irrigate · 7 Who Is Left Behind*
 Act:     8 Adoption Model (AI) · 9 District Priority Planner
 About:   10 Data & Methods · 11 Download Data
 (* nice-to-have)
```

### 4.2 Global filters (sidebar, apply to every page)

| Filter | Widget | Default | Column |
|---|---|---|---|
| Year range | `sliderInput` range | 2019–2025 | `sas_year` |
| Season | `checkboxGroupButtons` A / B / C | A + B (C is shown separately as the "dry-season" view) | `sas_season` |
| Province | `pickerInput` | All | `province` |
| District | `pickerInput` (filtered by province, live search) | All | `district_std` |
| Crop group | `pickerInput` | All | `crop_group` |
| Crop | `pickerInput` (filtered by group) | All | `crop_name` |
| Farmer gender | radio | All | `gender` |

* **Cross-filtering:** clicking a district on any map sets the District filter, and clicking a crop bar sets Crop.
* **Active-filter chips** sit at the top of each page, each with an ✕ to remove it, plus a "Reset all" button.
* **Bookmarking:** `enableBookmarking("url")` lets a user share a filtered view by link.

### 4.3 Page controls (accordion under the global filters, only on the relevant page)

| Page | Controls |
|---|---|
| Irrigation Map | Map metric (8 options from §5.2); unit: % plots / % area / hectares |
| Rain & Climate | Indicator: total mm, anomaly %, z-score; baseline 1991–2020 |
| Production Explorer | Measure: production t / area ha / yield kg/ha / sales RWF / price; group by: crop, district, season |
| Does Irrigation Pay? | Crop; outcome yield or sales/ha; raw vs adjusted |
| How Farmers Irrigate | Breakdown: technique / source / tool / ladder |
| Adoption Model | Farmer profile inputs for the simulator |
| Priority Planner | Weight sliders for the 5 index components; "+X points adoption" slider |

---

## 5. Pages, visuals and data

Notation: **T** = table in `app/data` (built by `07_Build_App_Data.R` from the master tables), **C** = columns.

### Page 0 — Home (landing)
* A hero banner with the one-sentence pitch, a background photo of a Rwandan terraced field or marshland (open-licence, with credit), and a "Start the story" button.
* 4 KPI cards (see Page 1). Below them, 3 cards for "The gap", "The payoff" and "The action" that link to the story pages.

### Page 1 — Overview ("The gap") · MVP
| Visual | Plotly type | T / C | Interpretation rule |
|---|---|---|---|
| KPI: plots irrigated (latest A) + sparkline | value box | `master_national_season`: `irrigated_plot_pct` | change vs 2019A |
| KPI: irrigated hectares | value box | `irrigated_area_ha` | vs NST2 target (**to verify and cite**) |
| KPI: maize yield premium | value box | `master_crop_season`: `yield_premium_pct` (Maize) | "irrigated maize yields X% more" |
| KPI: modern irrigation share | value box | `modern_irrig_pct` | "1 in N irrigators uses a pump or machine" |
| Irrigation over 21 seasons | line, one line per season A/B/C, CI ribbon | `irrigated_plot_pct` by `sas_year`, `sas_season` | trend rule |
| Production by crop group | stacked bar (≤6 groups + Other) | `master_crop_season`: `production_t`, `crop_group` | top group and its share |
| Mini map | choropleth | `master_district_season` + `districts_simplified` | top and bottom district |
| Modern input adoption |  horizontal bar | `irrigated_plot_pct`, `inorganic_fert_pct`, `improved_seed_pct`, `pesticide_pct`, `mechanised_pct`, `anti_erosion_pct` | lowest-adopted input |

### Page 2 — Irrigation Map ("Where") · MVP
| Visual | Type | T / C |
|---|---|---|
| District choropleth (leaflet, with Plotly side panels) | map | `master_district_season`: chosen metric among `irrigated_plot_pct`, `irrigated_area_ha`, `irrigated_area_pct`, `modern_irrig_pct`, `production_t`, `yield_kg_ha`, `inorganic_fert_pct`, `rain_anomaly_pct` |
| District ranking | sorted horizontal bar, selected district highlighted | same |
| Change 2019→2025 | diverging choropleth | difference of 2-season averages |
| District profile card (on click) | card + small multiples | all district columns; national benchmark line |

### Page 3 — Rain & Climate ("Need") · MVP
| Visual | Type | T / C |
|---|---|---|
| Season rainfall anomaly map | diverging choropleth | `master_rain_district_season`: `rain_anomaly_pct` |
| Rainfall 1981–2025 for selected district | line + trend line, dry seasons marked | `rain_mm`, `dry_season_flag` |
| Drought frequency per district | bar | share of seasons with `rain_std_anomaly < -1` |
| **Need vs action** | scatter, 30 districts, quadrant lines at medians, labels on the top-left quadrant | x = drought frequency or rain CV, y = `irrigated_plot_pct` |
| Irrigation in dry vs normal seasons | grouped bar | `irrigated_plot_pct` by `dry_season_flag` |

### Page 4 — Production Explorer ("overall products and measures, then filter") · MVP
This page is your merged-data view: every measure for every crop, region and season, driven by the filters.
| Visual | Type | T / C |
|---|---|---|
| Measure picker cards | value boxes | `production_t`, `crop_area_ha`, `yield_kg_ha`, `sold_share_pct`, `price_rwf_kg`, `sales_value_mrwf` |
| Treemap: production by crop group → crop | treemap | `master_crop_season` |
| Trend of the chosen measure | line | by season |
| Crop × district heatmap | heatmap | `master_crop_district_season` |
| Pivot table | `reactable` with grouping, sorting, CSV/Excel download | any measure × any grouping |

### Page 5 — Irrigation & Yield Evidence · MVP (core evidence; renamed in v1.1)
| Visual | Type | T / C |
|---|---|---|
| Yield irrigated vs rain-fed by crop | dumbbell (green vs grey dots) | `master_crop_season`: `yield_irrigated_kg_ha`, `yield_rainfed_kg_ha`, `n_irrigated_yield` (crops with n ≥ 30) |
| Raw vs adjusted premium | forest plot with CIs | `model_premium.rds` (Section 7.2) |
| Modern-package ladder | bar: yield by `modern_inputs_n` (0–4) | `master_crop_plot` |
| Sales value per ha | dumbbell | `sales_value_rwf / crop_area_ha` |
| "Better than last season?" | 100% stacked bar | `production_vs_last` by `irrigated` |

### Page 6 — How Farmers Irrigate · MVP
| Visual | Type | T / C |
|---|---|---|
| Technology ladder | ordered bar (1 Manual → 4 Machine/pivot) + trend | `irrig_tool_level` |
| Technique mix over time | 100% stacked area | `irrig_technique` |
| Water sources (any mention) | bar | `src_*` |
| Cost per ha by tool level | box plot | `irrig_cost_rwf / plot_area_ha` |
| District × technology heatmap | heatmap | `irrig_tool_level` by `district_std` |

### Page 7 — Who Is Left Behind · nice-to-have
Gender gap (bar + trend), age bands, plot size quintiles, erosion degree, land consolidation, from `master_plot`: `gender`, `age_band`, `plot_area_ha`, `erosion_degree`, `land_consolidated`.

### Page 8 — Adoption Model (AI) · MVP (Tech Innovation)
| Visual | Type | Source |
|---|---|---|
| Model card | text card | algorithm, AUC, n, years |
| What drives irrigation? | variable importance bar / SHAP summary | `model_adoption.rds` |
| Partial dependence | line | rainfall anomaly, plot size, district |
| "Farmer like me" simulator | inputs → probability gauge | predict on the fitted model |
| Hidden potential map | choropleth | per district, mean predicted probability − actual rate = untapped adoption |

### Page 9 — District Priority Planner ("Act") · MVP (Tangible Impact)
| Visual | Type | Source |
|---|---|---|
| Irrigation Opportunity Index (IOI) map | choropleth | `ioi.rds` |
| Weight sliders → live re-ranking | sliders + ranked `reactable` | 5 components: need (drought frequency), gap (low adoption), payoff (yield premium × area), scale (crop area), feasibility (water sources, low severe erosion, land consolidation) |
| What-if | value boxes + bar | "+X points adoption in district D → +ha, +tonnes, +RWF" using the adjusted premium with its range |
| Policy brief | button | downloads a one-page PDF/HTML brief for the selected district (`rmarkdown` / `quarto`) |

### Page 10 — Data & Methods · MVP
Pipeline diagram, sources (NISR SAS 2019–2025, CHIRPS, GADM), the data traps from §2.3, weighting, KPI definitions (`master_dictionary.csv`), model details, limits, **AI-use disclosure**, team and GitHub link.

### Page 11 — Download Data
Download filtered master aggregates (CSV/Excel), the data dictionary and the infographics.

---

## 6. KPIs (definitions)

| KPI | Definition | Column |
|---|---|---|
| Plots irrigated (%) | Σw·irrigated / Σw over cultivated plots | `irrigated_plot_pct` |
| Irrigated area (ha) | Σ w · plot area · irrigated | `irrigated_area_ha` |
| Farmers irrigating (%) | weighted share with any irrigated plot (2020+) | `farmers_irrig_pct` |
| Modern irrigation (%) | pump / tube well / machine / pivot or drip / sprinkler, among irrigated plots | `modern_irrig_pct` |
| Yield premium (%) | irrigated ÷ rain-fed yield − 1 (ratio of weighted sums; raw), plus the adjusted version | `yield_premium_pct` |
| Production (t) | Σ w · harvest kg / 1000 | `production_t` |
| Share sold (%) | Σ w · sold (capped at harvest) / production | `sold_share_pct` |
| Gender gap (points) | men's − women's % plots irrigated | `irrig_male_pct − irrig_female_pct` |
| Rain anomaly (%) | season total vs 1991–2020 normal | `rain_anomaly_pct` |
| Opportunity Index (0–100) | weighted, min-max-scaled components | `ioi` |

All percentages show a 95% CI computed with `srvyr` (strata = `stratum`, ids = `segment_id`, weights = `weight`) in `07_Build_App_Data.R`. Cells with n < 30 are suppressed.

---

## 7. Models (`08_Models.R`)

### 7.1 Irrigation adoption model (included, your decision 4)
* **Outcome:** `irrigated` (plot, Seasons A/B, 2020–2025).
* **Features:** district, season, year, rainfall anomaly, plot size, erosion degree, land consolidation, anti-erosion, gender, age, inorganic fertiliser, improved seed, mechanisation, farmer type.
* **Models:** a weighted logistic regression as the explainable baseline, plus gradient boosting (`tidymodels` + `xgboost`). Validation is by time: train on 2020–2023 and test on 2024–2025. Report AUC and calibration.
* **Explain:** variable importance and SHAP (`shapviz`) for the drivers and the simulator.
* **Output:** `model_adoption.rds` (a small butchered workflow) and `district_potential.rds`.

### 7.2 Adjusted yield premium (makes the payoff credible)
* For each major crop (maize, rice, beans, potato, vegetables), use propensity-score matching (`MatchIt`, nearest neighbour with a caliper) on district, season, plot size, fertiliser, seed, erosion and gender, then a weighted regression of log(yield).
* **Output:** `model_premium.rds` with the premium and its 95% CI per crop, shown next to the raw gap.

### 7.3 Optional (if time allows)
Rainfall outlook: a simple seasonal ARIMA per district on CHIRPS for the next season, labelled "experimental".

---

## 8. Deployment on shinyapps.io

* The app reads only `app/data/*.rds`, made of aggregates and model objects (target under 30 MB), so it starts fast on the small shinyapps.io instance. The 280 MB `.RData` and the raw SAS files are never deployed.
* `renv` locks package versions. Deploy with `rsconnect::deployApp("app", appName = "smartirrigate-rwanda")`.
* The free plan has limited active hours per month, so deploy early and avoid leaving it open during development. Use a local run for testing.
* The GitHub repo (public, required) holds `SCRIPTS/`, `app/`, `docs/`, the README with how to reproduce, and the AI disclosure. Raw SAS data stays out of the repo, so add it to `.gitignore` and describe how to obtain it.

### App folder
```
app/
  app.R            (page_navbar, theme, server wiring)
  R/  mod_overview.R  mod_map.R  mod_climate.R  mod_explorer.R  mod_payoff.R
      mod_how.R  mod_who.R  mod_model.R  mod_planner.R  mod_methods.R
      fct_plotly_theme.R  fct_interpret.R  fct_filters.R  fct_kpi.R
  data/            (from 07 and 08)
  i18n/translations.json  i18n/labels.csv
  www/  custom.css  logo.svg  hero.jpg
```
Each page is a Shiny **module**, so pages can be built and tested one at a time.

---

## 9. Infographics (same data, same colours, same icons)

1. **"Rwanda's irrigation in one page":** KPIs, the 21-season trend and the map.
2. **"Water pays":** the maize/rice dumbbell and the modern-package ladder.
3. **"Where to act":** the IOI map and the top 5 districts with their reasons.
4. **"Who is left behind":** gender and age gaps.

Each is built with `ggplot2` + `ggtext` + `patchwork` using the §3.2 palette, Poppins/Inter fonts and the §3.3 icons, and exported at A4, 1080×1080 for social media and 1920×1080 for slides. All three languages are produced from the same script.

---

## 10. Build plan (to 30 Oct)

| Dates | Work |
|---|---|
| 13–14 Oct | ✓ Architecture final. ✓ `06_Merge_Master_Data.R`. You: re-run 05 then 06 on your machine |
| 15–16 Oct | `07_Build_App_Data.R` (CIs, interpretations data, IOI); app shell (theme, navbar, sidebar, i18n skeleton) |
| 17–19 Oct | Pages 1, 2, 3, 4; **first deploy to shinyapps.io**; **register by 20 Oct** |
| 20–23 Oct | `08_Models.R`; Pages 5, 6, 8, 9 |
| 24–26 Oct | Methods & Download pages; translations; infographics; Page 7 if time |
| 27–28 Oct | Native-speaker review of RW/FR; phone testing; README, docs, AI disclosure |
| 29 Oct | Final deploy and submission (one day of buffer) |

---

## 11. How the dashboard earns each criterion

| Criterion (20 pts) | What earns it |
|---|---|
| Problem understanding & relevance | 4-act story; NST2 / PSTA5 / Vision 2050 link on Overview; need-vs-action quadrant |
| Data use & methodology | 7 years × 3 seasons of SAS harmonised; documented fixes of 7 data traps; survey-weighted CIs; CHIRPS 45-year baseline; reproducible scripts |
| Tech innovation | Satellite rainfall + survey fusion; ML adoption model with SHAP; matched yield effect; live Opportunity Index; what-if simulator |
| Usability & design | Validated agriculture palette; icons; 3 languages; plain-language interpretation on every chart; cross-filtering; mobile layout; dark mode |
| Tangible impact | Ranked district investment list, district policy brief download, gender gap made visible, aimed at MINAGRI, RAB, districts and partners |

---

## 12. Still to verify before submission

1. The NST2 and PSTA5 irrigated-area targets, quoted with a citation.
2. A native-speaker review of the Kinyarwanda and French text.
3. Season C yields and 2024B/C yields, because crop area is incomplete there.
4. The open-licence hero photo and its credit.

---

## 13. Team additions (accepted in v1.1)

| # | Addition | How the build applies it |
|---|---|---|
| 1 | Team name **NiyoIshimwe** and its brand palette | Navbar, footer, hero and Methods say "Powered by Team NiyoIshimwe". Brand colours drive the theme; chart colours are the same hues nudged to pass the colour-blind check (green #0F7044, amber #B07A1C, blue #1976B9, terracotta #B65F47). |
| 2 | Rename "Does Irrigation Pay?" to **Irrigation & Yield Evidence** | Done (page 5). |
| 3 | Observed and adjusted associations, no causal claims | Evidence page shows raw gap and adjusted % (survey-weighted log-yield model) side by side with a caveat banner. Wording says "associated with", never "causes". |
| 4 | Fold Home into Overview, Downloads into Methods | Done: 10 pages in 3 menus (Story, Analyse, Act) plus Methods. |
| 5 | Remove the RWF/tonnes what-if | Removed. Priority page has no return estimate. |
| 6 | Opportunity Index is **preliminary screening** | Page renamed "Priority screening", red banner, adjustable weights, and a rank-stability chart from 2,000 random weight sets. |
| 7 | No blanket "missing means No" | `06` audits every skip pattern per season and variable (`skip_pattern_audit.csv`); blanks become No only where the gate is confirmed. Irrigation confirmed in 15 of 21 seasons; inorganic fertiliser only in 2025A–C. |
| 8 | Crop and gender filters only where tables have those columns | Every page shows a "filters used" strip; crossed-out filters do not apply there. |
| 9 | District Profile side panel | Map page: click a district to see six indicators vs Rwanda with n and reliability, rainfall and screening rank. |
| 10 | Need vs Adoption quadrant | Need page: district scatter with median lines, CI bars and ecological-association caveat. |
| 11 | Ranking sensitivity | Priority page: p10–p90 rank range, probability of top 5, Stable / Moderately sensitive / Sensitive label. |
| 12 | "What this means" and "Source & limitations" under every chart, EN/RW/FR | Every chart card has both, generated from the data in the selected language. |
| 13 | Model validation dashboard | Model page: out-of-time AUC (logistic 0.810, random forest 0.785), Brier, calibration deciles, fairness by gender and province, odds ratios, importance, simulator. |
| 14 | Policy brief only after validation | Not built yet; to follow once results are reviewed. |
| 15 | Every KPI states date, unit, numerator/denominator, sample/quality, source | KPI subtitles carry season, n and a reliability badge; Methods has a KPI definitions tab. |
| 16 | No public microdata | The app ships only aggregates from `07`/`08` (about 0.9 MB). |
| 17 | Personas: farmers, planners, researchers/judges | Listed on Methods > About and used to order pages. |

## 14. Build v0.1 status and deviations

**Files (all in `SCRIPTS/`):** `00_Config.R` (paths, survey helpers), `05` and `06` (updated), `07_Build_App_Data.R`, `08_Models.R`, `09_Run_All.R`, and the app in `SCRIPTS/app/` (`app.R`, `R/` modules, `i18n/`, `www/`, `data/`).

**Run order:** `source("SCRIPTS/09_Run_All.R")` then `shiny::runApp("SCRIPTS/app")`.

**Deviations from sections 3–8 (can be swapped later):**
- Maps use Plotly choropleths with the district GeoJSON instead of leaflet, so every chart shares one toolkit. A blank base map in `www/world_110m.json` keeps maps working offline.
- Tables use DT instead of reactable; survey estimates use `survey` directly instead of `srvyr`.
- Translation uses a small JSON dictionary (`i18n/translations.json`, built by `build_translations.py`) and `?lang=en|rw|fr`, instead of shiny.i18n.
- Dark mode is not in v0.1.

**Known gaps for the next round:** native-speaker review of Kinyarwanda and French; crop names and reliability labels still in English; 2024B–C crop areas are thin; policy brief; infographics; photos with credits.


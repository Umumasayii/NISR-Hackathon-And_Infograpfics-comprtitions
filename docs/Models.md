# Models

Every number below comes from the build of 2026-10-23 (`SCRIPTS/web/public/data/app_data.json`),
produced by `SCRIPTS/08_Models.R` (models 1–3) and `SCRIPTS/07_Build_App_Data.R`, section 8 (model 4).
The website (Methods › Models) reads the same file, so the page updates with each rebuild.

All four models use the survey weights. They describe **patterns (associations), not causes**, and
none of them decides who gets support.

| # | Model | Question | Shown on | Main result |
|---|---|---|---|---|
| 1 | Survey-weighted logistic regression | Which plot and farmer features go with a plot being irrigated? | Adoption model | AUC 0.810 on 2024–2025, years it never saw |
| 2 | Random forest (`ranger`), benchmark | Would a flexible model rank plots much better? | Adoption model | AUC 0.780: no gain, so model 1 is used |
| 3 | Survey-weighted adjusted yield regression, one per crop | Do irrigated plots harvest more than similar rain-fed plots? | Irrigation & Yield Evidence | Clearly higher for 4 of 18 crops |
| 4 | Weighted screening index with weight sensitivity | Which districts should planners check first? | Priority screening | 14 of 30 districts keep a stable rank |

---

## 1. Irrigation adoption: survey-weighted logistic regression

**Why this model.** The outcome is yes/no (plot irrigated or not), so a logistic model fits. It is easy
to explain: each feature gets one odds ratio with a 95% interval, and the same equation drives the
what-if simulator on the Adoption model page. A light copy of the fitted equation (coefficients and
factor levels, no data) is exported for the simulator.

**Data.**
- NISR Seasonal Agricultural Survey (SAS) plots, Seasons A and B, 2020–2025.
- Kept: plots with an irrigation answer and an area above 0.
- Training: 2020–2023, **134,355 plots**. Test: 2024–2025, **68,928 plots**.
- Survey weights rescaled to a mean of 1 (the fit is not dominated by their scale).
- Rain from CHIRPS, joined by district, year and season.

**Variables.**

| Role | Variable | Coding |
|---|---|---|
| Outcome | `irrigated` | 1 = plot irrigated this season |
| Feature | `district` | 30 districts (fixed effects) |
| Feature | `season` | A or B |
| Feature | `log_plot_area` | log(plot area in ha), area capped at 20 ha |
| Feature | `rain_anomaly_z` | (season rain − 1991–2020 normal) ÷ SD; missing set to 0 |
| Feature | `erosion` | Low / Moderate / Severe / Unknown |
| Feature | `consolidated` | Land use consolidation site: Yes / No / Unknown |
| Feature | `inorganic_fert` | Chemical fertiliser: Yes / No / Unknown |
| Feature | `organic_fert` | Organic fertiliser: Yes / No / Unknown |
| Feature | `gender` | Plot manager: Female / Male / Unknown |
| Feature | `age_band` | Under 35 / 35–54 / 55+ / Unknown |
| Feature | `large_farm` | Large-scale / Small-scale / Unknown (missing is not counted as small) |

**Fitting.**
- Point estimates: `glm(binomial)` with the rescaled weights.
- Intervals: `survey::svyglm(quasibinomial)` on the same formula, strata and the physical survey
  segment as cluster (segments are revisited across seasons), t quantiles on the design df
  (**3,060 df, 3,310 segments**). The naive `glm` standard errors are kept beside them for comparison;
  they were too narrow.

**Validation (out-of-time).** Fitted on 2020–2023, scored on 2024–2025.

| Measure (2024–2025 test) | Logistic | Random forest | No-skill guess |
|---|---|---|---|
| AUC (weighted Mann-Whitney, ties = ½) | **0.810** | 0.780 | 0.500 |
| Average precision | 0.110 | 0.100 | 0.025 (share irrigated) |
| Brier score (lower is better) | 0.0229 | 0.0231 | 0.0240 (training share as constant) |
| Irrigated among the top 10% predicted | 11.1% | 10.3% | 2.5% |
| Irrigated plots caught in the top 10% | 45.1% | 42.1% | 10% |
| Lift over a random pick | ×4.5 | ×4.2 | ×1.0 |
| Predicted / observed share irrigated | 2.2% / 2.5% | 2.7% / 2.5% | |

**Calibration** (logistic, tenths of predicted risk, predicted vs observed % irrigated): the five lowest
tenths predict 0.03–0.55% against 0.20–1.22% observed; the top tenth predicts 14.7% against 13.6%
observed. Shown as a chart on the Adoption model page.

**Fairness checks** (same measures by group, test years):

| Group | AUC | Predicted − observed (pts) |
|---|---|---|
| Female | 0.819 | −0.42 |
| Male | 0.803 | −0.22 |
| East | 0.775 | +0.21 |
| Kigali | 0.893 | +0.24 |
| North | 0.829 | −0.43 |
| South | 0.801 | −0.44 |
| West | 0.794 | −0.53 |

These are group metrics, not a proof of fairness.

**Main odds ratios** (design-based 95% interval): chemical fertiliser 8.1 (6.6–9.9), land consolidation
2.5 (1.6–4.0), organic fertiliser 2.2 (1.7–2.7), male manager 1.45 (1.20–1.75), plot area 0.60 per
log-unit (0.54–0.66), season rain anomaly 1.0 (0.9–1.1), small-scale vs large-scale farm 0.02
(0.01–0.03).

**Diagnostics.** Converged in 17 iterations; no coefficient has SE above 10 on the design scale. The
only warning is the expected "non-integer #successes" from using weights in `glm`. 20,685 fitted values
sit within 0.001 of 0 or 1, and rare "Unknown" groups give extreme odds ratios (manager gender
Unknown 824, age Unknown near 0): read those as data gaps, not effects.

**Limits.**
- Contemporaneous classification: fertiliser use, erosion and the season's rain are only known during
  or after the season, so it is **not a pre-season forecast**.
- 73% of test segments were also in training (segments are revisited), so the test is not fully
  independent.
- Associations only: chemical fertiliser and irrigation go together; one does not cause the other.

## 2. Benchmark: random forest

**Why this model.** It picks up interactions and non-linear patterns the logistic model cannot. If it
scored much higher, the simple model would be missing something. It did not (AUC 0.780 vs 0.810;
Brier 0.0231 vs 0.0229), so the app keeps the simpler, explainable model.

**Data and settings.** Same plots, features, weights and split as model 1. `ranger` probability
forest, 300 trees, minimum node size 50, case weights, permutation importance, seed 2026.

**Variable importance** (permutation, scaled to the top = 100): plot area 100, large farm 54,
chemical fertiliser 51, consolidation 38, district 30, rain anomaly 26, gender 17, organic fertiliser 13,
age band 12, season 9, erosion 1.

**District prediction gap.** For each district, the forest's predicted share of irrigated plots minus
the observed share in 2024–2025. It is a lead for field checks, not what a programme would achieve.

**Limits.** Importance shows what the forest relies on, not why. Same contemporaneous-data limit as model 1.

## 3. Harvests: survey-weighted adjusted yield regression

**Why this model.** Irrigated plots differ in inputs, size and place. A survey-weighted regression of
log yield compares like with like and gives a % difference (exp(b) − 1) with a design-based interval.

**Data.**
- SAS crop-plot rows, Seasons A and B, 2019–2025.
- Eligible: harvest above 0, crop area known, yield inside its crop-season 1st–99th percentile.
- Seasons with under 80% crop-area coverage left out: **2024B (46%) and 2024C (7%)**.
- One model per crop with at least 150 irrigated plots: **18 crops**.

**Variables.** Outcome log(kg per ha). Regressors: irrigated (0/1), chemical fertiliser, organic
fertiliser, improved seed (unknown kept as its own group), log crop area, district, year-season.

**Fitting.** `survey::svyglm` with strata and the physical segment as cluster (seasons pooled). Each crop
is a domain (`subset`) of the full design, so every segment stays in the variance. 95% intervals use t
quantiles on the design df.

**Checks.**
- Complete-case refit (only plots with all three inputs known). In this build every eligible plot had
  all three answers, so it gives the same numbers.
- Raw comparison: weighted harvest ÷ weighted area, irrigated vs rain-fed (a different estimand, shown
  beside the adjusted one).
- On the Evidence page: the raw gap under four plot-selection rules (main rule, keep zero harvests,
  no trimming, trim 5–95%).

**Results** (adjusted % difference, irrigated vs similar rain-fed plots):

| Crop | Adjusted | 95% interval | Raw | Plots (irrigated) |
|---|---|---|---|---|
| Sweet pepper | +34.9% | +3.7 to +75.6 | +14.7% | 343 (171) |
| Tomato | +14.8% | +1.7 to +29.6 | +15.8% | 2,021 (828) |
| Irish potato | +14.6% | +4.4 to +25.8 | −13.8% | 20,764 (366) |
| Maize | +14.1% | +7.4 to +21.3 | +57.3% | 72,222 (1,559) |

The other 14 crops show no clear difference (interval crosses 0): amaranth, banana for beer, bush bean,
cabbage, cassava, climbing bean, cooking banana, dessert banana, eggplant, paddy rice, pepper, soybean,
sweet potato, taro.

**Limits.** Observational: water access, soil, skills and markets are not measured, so these are
adjusted associations, not the effect of irrigation. Raw and adjusted numbers can point in different
directions (Irish potato, paddy rice) because inputs, place and season differ.

## 4. District shortlist: weighted screening index

**Why this model.** A transparent, adjustable score is easier to question than a black box. Planners
can change the weights on the Priority page and watch the order move.

**Data.** 30 districts. CHIRPS rainfall 1991–2025; SAS 2023–2025 for irrigation, cultivated area,
the men–women irrigation gap and fertiliser use.

**Criteria** (each rescaled 0–1 by min–max across districts; score = weighted mean × 100):

| Criterion | What it is | Period | Default weight |
|---|---|---|---|
| Rain-shortfall history | Mean of: season rain variability (CV), dry main seasons (anomaly < −1 SD), low normal rain | 1991–2020 baseline; dry seasons 2016–2025 | 30% |
| Adoption gap | 1 − share of plots irrigated | Seasons A+B 2023–2025 | 30% |
| Cultivated area | Mean cultivated ha per main season | 2023–2025 | 20% |
| Gender gap | Men − women plot irrigation (only where both groups have n ≥ 30; negatives set to 0) | 2023–2025 | 10% |
| Current input use | Plots using chemical fertiliser | 2023–2025 | 0% (until fertiliser figures match NISR) |

**Validation: weight sensitivity.** There is no ground truth, so the rank is tested for stability:
1,000 weight sets drawn from Dirichlet(20 × default weights); a criterion weighted 0 stays 0; seed 2026.
Each district gets a rank range (10th–90th percentile) and the share of draws that put it in the top 5.
The same method runs in the browser (`SCRIPTS/web/src/lib/ranking.ts`, with tests).

- Stable (range ≤ 4 places): 14 districts. Moderately sensitive (≤ 10): 11. Sensitive to weights: 5.
- Top 5 by default: Kirehe, Ngoma, Nyagatare, Kayonza, Bugesera, each in the top 5 in 83–100% of draws.

**Limits.** A shortlist for field checks, not an investment ranking. Water availability, scheme status,
irrigable area, distance to infrastructure, water user associations, permits, unit costs and market
access are not in the data; the Assess page records them per district.

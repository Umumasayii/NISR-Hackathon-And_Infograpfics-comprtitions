# Methods and reconciliation with NISR (2019–2025)

Rebuilt 2026-10-23 from the 111 SAS microdata files with `SCRIPTS/09_Run_All.R`. Every number below
was recomputed from the microdata by `SCRIPTS/15_Reconcile_With_NISR.R`; the full cell-by-cell list is
`docs/Reconciliation_Register_2019_2025.csv`. NISR published values stay the primary figures where
the definition matches ours. Our estimates were never adjusted to match NISR.

## 1. Estimation

- **Design.** Strata = district × land-use stratum within each season; PSU = segment; weight =
  `plot_weight`. Ratios (shares, yields) use linearised variance and t intervals on the design
  degrees of freedom. Lonely PSUs: centred at the overall mean (`survey.lonely.psu = "adjust"`).
- **Pooled seasons.** About 97% of segments are revisited between Seasons A and B and about 98%
  between years, so seasons are not independent samples. Pooled estimates now sum linearised scores
  per physical segment across seasons (strata = district × stratum). Verified: national irrigated
  share 2023–2025 A+B = 2.417%, SE 0.1215 points, identical to `survey::svymean` with segment
  clusters. Treating seasons as independent gave SE 0.1130 (7.5% too small).
  Test: `SCRIPTS/tests/test_pooled_variance.R` (PASS).
- **Combining areas in the browser.** When a part has no SE, the combined SE and interval are
  missing (never zero) and the result is marked Not reliable.
- **Yields.** Weighted harvest ÷ weighted eligible crop area. Main rule: positive harvest and yield
  inside the crop × season 1st–99th percentiles; 2024B/C excluded. The Evidence page shows the same
  ratio when zero harvests are kept, without trimming, and with 5–95% trimming.

## 2. Reconciliation findings

| Indicator | NISR vs ours | Cause (verified in the microdata) | What the site does |
|---|---|---|---|
| Chemical fertiliser, % of plots, 2025A/B | 56.50 vs 34.44; 52.83 vs 28.98 | From 2025A the questionnaire first asks "did you use it on **any** of your plots?" and asks the plot question only if yes. NISR's % is the share among plots with a plot answer (plots of users). Recomputed that way, ours equals NISR (gap 0.00). In 2024A the plot question was asked on every plot and both agree (34.01) | NISR value shown under its own label ("plots of farmers who used it"); not compared |
| Pesticide, % of plots, from 2022C | e.g. 2025A 50.32 vs 19.62; 2025B 43.56 vs 15.52 | Same gate, from 2022C. Recomputed on answered plots: gap 0.00 in 2024A, 2025A, 2025B and within 0.7 points in 2024B/C | Own label, not compared |
| Organic fertiliser, % of plots, from 2022C | e.g. 2025B 71.10 vs 60.65 | Same gate, from 2022C. Recomputed: gap 0.00 in 2024A, 2025A, 2025B and within 0.4 points in 2024B/C | Own label, not compared |
| Input use, % of land, gated seasons | Ours up to 37 points lower | Built from the same gated plot question | Own label, not compared |
| Farmers who irrigated, 2025C | 58.88 vs 54.48 | NISR's farmer % is the **unweighted** share of sampled farmers: we reproduce 58.88 exactly. Ours is survey-weighted (farmer weight = mean of plot weights). 2025A: 13.43 vs 13.51; 2025B: 11.52 vs 10.92 | NISR figure shown first; ours as cross-check |
| Farmer-level input use, 2022C–2025C | Was 20–26 points below NISR in 2024–2025 | **Defect, fixed.** Our farmer flag was built from the plot rows; from the gate onwards it must come from the "any of your plots" question (2025A: 2,940 farmers said yes but recorded it on none of their listed plots). Now the unweighted share matches NISR within 0.2 points in every season 2023A–2025C | Fixed in `06_Merge_Master_Data.R` |
| Farmer-level input use, 2020A–2022B | Ours 15–23 points **above** NISR (e.g. 2021A chemical 61.3 vs 40.9) | **Not resolved.** No "any plot" question in those years. NISR's farmer % is 6–9 points above its own plot %, ours is far higher; the NISR farmer base may differ. Needs NISR's tabulation syntax | Shown as published; flagged |
| Cultivated land | Ours 3–12% below from 2020; 21% above in 2019 | Not resolved | Shown as published |
| Cassava harvested area | Ours up to 5× NISR in Season A | Not resolved (likely perennial/area-share handling) | Shown as published |
| 2024B crop areas | 44% of harvested crop rows match a screened crop (99.9% elsewhere) | File structure; cause not determinable from the data | 2024B/C excluded from yields |

## 3. Priority screening

Score = Σ wᵢ·cᵢ with weights normalised to 100% over criteria with positive weight; each criterion
is min-max scaled across the 30 districts. A weight of zero contributes nothing, including in the
sensitivity check: 1,000 weight sets from Dirichlet(20 × effective weights) over positive criteria
only (seed 2026; the same rule in R and in the browser; unit-tested). If every weight is zero no
district is ranked and downloads are disabled. Rank ranges show preference sensitivity, not
sampling error.

## 4. Adoption model (Advanced only)

Logistic regression and random forest, trained 2020–2023, checked on 2024–2025 (68,928 plots).
Tie-corrected weighted AUC 0.810 (forest 0.780); Brier 0.0229 vs 0.0240 for predicting the base rate;
average precision 0.110 vs base rate 0.025; top-10% precision 11.1%, recall 45.1%, lift 4.5.
Odds-ratio intervals now use the survey design with physical segments (3,310 segments, 3,060 df)
instead of naive logistic SEs. Converged in 17 iterations; no coefficient SE above 10.
73% of test-period segments were also in training, so the check is out-of-time but not on new
places. Predictors (fertiliser use, erosion, the season's rain) are only known during the season:
it is a **contemporaneous classification, not a pre-season forecast**, and not causal.

# Data dictionary

The website reads three files built by `SCRIPTS/12_Export_Web_Data.R` into `SCRIPTS/web/public/data/`.
All values are aggregates; no record-level data are exported. Tables are stored column-wise as
`{"__df": {column: [values]}}`.

## Units of analysis (never mixed)

| Unit | Meaning | Weight |
|---|---|---|
| Plot | A parcel cultivated in the season | SAS `plot_weight` |
| Crop × plot | One crop on one plot (yields, production) | SAS `plot_weight` |
| Farmer | Agricultural operator in the season, counted once | Mean of the farmer's plot weights (SAS has no farmer weight) |
| Hectare | Area totals: weighted sums of measured plot or crop areas | SAS `plot_weight` |
| Household | AHS only | AHS household weight |

Seasons: A = September–February (main), B = March–June, C = July–September (dry, small sample).

## Common estimate columns

| Column | Meaning |
|---|---|
| `level`, `area` | `national` / `province` / `district` and its name |
| `sas_year`, `sas_season` | Survey year and season |
| `indicator` | See below |
| `estimate` | Weighted ratio (share 0–1 for % indicators, kg/ha for yields) |
| `se` | Linearised standard error from the survey design (strata = district × land-use stratum, PSU = segment). Pooled seasons cluster on the physical segment because segments are revisited. Missing, never zero, when it cannot be computed |
| `ci_low`, `ci_high` | 95% interval, t on the design degrees of freedom |
| `n` | Sampled units with an answer |
| `n_psu`, `df` | Segments and design degrees of freedom behind the estimate |
| `wsum` | Sum of weights (estimated population) |
| `cv` | Coefficient of variation, se / estimate |
| `reliability` | `Unreliable` if n < 30 or fewer than 5 segments; `Good` if CV ≤ 20%, n ≥ 50 and ≥ 12 segments; `Use with caution` if CV ≤ 35%; `Unreliable` otherwise. Shown as Reliable / Use with care / Not reliable |

## Indicators (`est`)

| Indicator | Unit | Definition |
|---|---|---|
| `irrigated` | plots | Plot irrigated in the season, % of cultivated plots |
| `irrig_modern` | plots | Plot irrigated with a motorised pump, sprinkler, drip or pivot, % of plots |
| `irrig_any_farmer` | farmers | Farmer irrigated at least one plot, % of farmers (weighted; NISR publishes the unweighted share) |
| `inorganic_fert`, `organic_fert`, `pesticide` | plots | Input used on the plot, % of **all** cultivated plots. Where the farmer said they used none on any plot, the skipped plot answer is set to "no" (checked in `meta.skip_audit`) |
| `land_consolidated`, `anti_erosion`, `agroforestry`, `mechanised` | plots | Practice on the plot, % of plots |

## Other tables

| Table | Content |
|---|---|
| `totals` | Cultivated, irrigated and crop area (ha), production (t), sales, per area and season |
| `crop`, `crop_dist` | Crop area, production, yields (irrigated / rain-fed), sales, improved seed, by crop |
| `yield.pooled`, `yield.by_year`, `yield.ladder` | Weighted harvest ÷ weighted eligible area (kg/ha). Eligible: positive harvest, inside the crop × season 1st–99th percentiles, usable seasons (2024B/C excluded) |
| `yield.sensitivity` | Same ratio under four eligibility rules: `main`, `with_zero_harvests`, `no_trimming`, `trim_5_95`, with `n_excluded` and `n_zero_harvest` |
| `rain.rain`, `rain.district` | CHIRPS seasonal rain, 1991–2020 normal, standardised anomaly, dry-season flag (< −1 SD), and the rain-shortfall history index (0–100, relative) |
| `screen.table` | Priority screening: criteria `c_need` (rain-shortfall history), `c_gap` (adoption gap), `c_scale` (cultivated area), `c_equity` (gender gap), `c_readiness` (input-use proxy, default weight 0), each min-max scaled 0–1 across the 30 districts; score, rank and rank range under weight sensitivity |
| `model` | Adoption classifier (Advanced): performance (tie-corrected AUC, Brier and baseline, average precision, top-10% precision/recall), calibration, group metrics, survey-design odds ratios, `diagnostics` |
| `model_yield` | Adjusted irrigated vs rain-fed yield association by crop (log model), and the raw ratio-of-totals difference |
| `meta` | Build time, sources, season quality, skip-pattern audit |
| `ahs` | AHS 2017/2020/2024 household indicators (2024 is a series break) |

## `official.json`

One row per NISR published figure (2019–2025): `value` (NISR), `project_value` (ours, same
definition only), `d` (decision: `cross_check`, `no_project`, `own_label`, `blank`), and the source
file, sheet and `cell`. `definitions` gives each indicator's population and whether it matches ours
(`comparable`). Input-use "% of plots" in skip-gated seasons is `own_label` (different population).

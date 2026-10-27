# Data check, dashboard v0.2 (2026-10-13)

The check reran 06 → 07 → 08 on the selection files rebuilt 2026-10-13 (`DATA/processed/selection`).

## Fixed in this version

| Issue | Where | Fix |
|---|---|---|
| Sale prices carried "don't know" codes (99, 999, 9999, 99999, 999999) and zeros, which inflated sales value | `06_Merge_Master_Data.R` | Codes and zeros set to missing. Prices more than 10× the crop-season median are also set to missing. |
| Sales value was lost wherever the price was missing | `06_Merge_Master_Data.R` | Price imputed from the district median for that crop and season, else the national median. The new column `price_imputed` flags these rows. |
| Province missing on many 2021B and 2021C rows | `06_Merge_Master_Data.R` (corrected in v0.8) | v0.2 wrongly said this row was dropped from the app; no such filter existed, and 2021B district totals were counted twice. Since v0.8 the province comes from a fixed district list, every measure is built at the district × season level, and the build stops if district totals do not add up to national totals. See `Audit_Response_v0.8.md`. |

After the fix, maize prices sit around 200–420 RWF/kg. A+B sales value runs from 233 bn RWF (2019A) to 831 bn RWF (2025B).

## Flags to keep in mind (not changed, shown as caveats)

- **2022C:** cultivated area is only 3.7 kha, and 19% of plot areas are missing. Treat 2022C area and production as unreliable.
- **Thin crop-area totals:** 2024B and 2024C crop areas exist for only 46% and 7% of harvested crop plots. Since v0.8 both seasons are left out of every yield result (see `season_quality.csv`); 2020C also looks low.
- **Mechanisation (tractor, other machines):** about 0–1% of plots. The rate is rare, and probably real.
- **Share of harvest sold:** rises in 2024–25. This may reflect a change in the questionnaire, not behaviour.
- **Sales value:** partly uses imputed prices (see `price_imputed`).
- **Skip patterns:** blanks are set to "No" only in seasons where the skip was verified (log printed by 06).
- **Model results:** unchanged. Out-of-time AUC is 0.810 for logistic regression and 0.785 for random forest. Adjusted yield associations are positive and significant for maize, Irish potato, tomato, sweet pepper and taro.

## What to rerun on your machine

Run `06_Merge_Master_Data.R`, `07_Build_App_Data.R` and `08_Models.R` in that order, or `09_Run_All.R` with `run_select = FALSE`. The `SCRIPTS/app/data/*.rds` files shipped with v0.2 were already rebuilt this way, so the app works without the rerun.

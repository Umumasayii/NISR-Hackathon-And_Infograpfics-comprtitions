// Shapes of the tables exported by SCRIPTS/12_Export_Web_Data.R (aggregates only).
export type Season = 'A' | 'B' | 'C';
export type Reliability = 'Good' | 'Use with caution' | 'Unreliable' | 'Published';
export type Level = 'national' | 'province' | 'district' | 'combined';

export interface Est {
  level: Level; area: string; sas_year: number; sas_season: Season; indicator: string;
  estimate: number; se: number | null; ci_low: number | null; ci_high: number | null;
  n: number; wsum: number; cv: number | null; reliability: Reliability; source: 'survey';
  n_psu?: number | null; df?: number | null;   // segments and design degrees of freedom (builds from 2026-10-23)
}
export interface Totals {
  level: Level; area: string; province: string | null; sas_year: number; sas_season: Season;
  cultivated_area_ha: number | null; irrigated_area_ha: number | null; irrigated_area_pct: number | null;
  production_t: number | null; crop_area_ha: number | null; sold_t: number | null;
  sales_value_mrwf: number | null; n_plots: number | null; n_farmers: number | null;
  modern_irrig_area_ha: number | null; totals_source: string;
}
export interface Crop {
  district_std?: string; crop_group: string; crop_name: string; sas_year: number; sas_season: Season;
  n_crop_plots: number; yield_kg_ha: number | null; yield_irrigated_kg_ha: number | null;
  yield_rainfed_kg_ha: number | null; n_irrigated_yield: number | null; production_t: number | null;
  crop_area_ha: number | null; sold_t: number | null; sold_share_pct: number | null;
  price_rwf_kg: number | null; sales_value_mrwf: number | null; improved_seed_pct: number | null;
  // sums behind the yields (builds from 2026-10-20): harvest kg and area ha of the eligible plots
  yield_harvest_kg?: number | null; yield_area_ha?: number | null; yield_harvest_irr_kg?: number | null;
  yield_area_irr_ha?: number | null; yield_harvest_rf_kg?: number | null; yield_area_rf_ha?: number | null;
  n_yield?: number | null; n_rainfed_yield?: number | null;
}
export interface YieldRow {
  crop_group?: string; crop_name: string; season_type?: string; sas_year?: number; irrigation?: 'Irrigated' | 'Rain-fed';
  modern_inputs_n?: number; n: number; estimate: number; ci_low: number; ci_high: number; reliability: Reliability;
}
export interface MixRow {
  sas_year: number; sas_season: Season; category: string; w: number; n: number; share: number;
  n_group: number; dimension: string; district_std: string | null; period: string | null;
}
export interface RainRow {
  district_std: string; sas_year: number; sas_season: Season; rain_mm: number; rain_normal_mm: number;
  rain_anomaly_pct: number; rain_std_anomaly: number;
}
export interface NeedRow {
  district_std: string; rain_normal_ab_mm: number; rain_cv_pct: number; dry_seasons_2016_2025: number;
  rain_cv_a_pct?: number; rain_cv_b_pct?: number;
  need_score: number; adoption_pct: number | null; adoption_low: number | null; adoption_high: number | null;
  adoption_n: number | null; adoption_reliability: Reliability | null; quadrant: string;
}
export interface EquityRow {
  group: string; n: number; estimate: number; ci_low: number; ci_high: number; reliability: Reliability;
  dimension: string; period: string | null; sas_year: number | null; district_std?: string; gender?: string;
}
export interface ScreenRow {
  district_std: string; province: string; need_score: number; adoption_pct: number | null;
  adoption_reliability: Reliability | null; quadrant: string; cultivated_area_ha: number;
  c_need: number; c_gap: number; c_scale: number; c_equity: number; c_readiness: number;
  score: number; rank: number; rank_median: number; rank_p10: number; rank_p90: number;
  prob_top5_pct: number; stability: string; reasons: string;
  inorganic_fert_pct?: number | null; gender_gap_pts?: number | null; gender_gap_ok?: boolean | null;
}
/** A published NISR figure, read cell by cell from the SAS annual tables (official.json, SCRIPTS/11 + 14).
 *  d: how it relates to our estimate: '' none, 'cross_check' same definition (our value kept beside it),
 *  'own_label' different definition (never compared), 'no_project' nothing of ours to compare, 'blank' cell empty */
export interface PubRow {
  indicator: string; sas_year: number; sas_season: Season; level: 'national' | 'district'; area: string; crop_name: string | null;
  is_group: boolean; value: number | null; src_id: number; cell: string; project_value: number | null;
  d: 'cross_check' | 'own_label' | 'no_project' | 'blank' | null;
}
export interface PubSource { src_id: number; survey: string; source_title: string; source_file: string; sheet: string; nisr_table: string; table_title: string; measure_label: string | null }
export interface PubDef { indicator: string; unit: string; population: string; definition: string; comparable: boolean; project_indicator: string | null; project_table: string | null }
export interface OfficialFile { rows: PubRow[]; sources: PubSource[]; definitions: PubDef[]; built: string }
export interface AhsRow {
  level: Level; area: string; year: number; indicator: string; population: string; estimate: number;
  se: number | null; ci_low: number | null; ci_high: number | null; n: number; wsum: number;
  cv: number | null; reliability: Reliability; series_break: boolean;
}
export interface AhsEquity { year: number; group: string; estimate: number; se: number; n: number; reliability: Reliability; dimension: string; }
export interface AhsMix { year: number; dimension: string; category: string; share: number; n: number; }

export interface AppData {
  built: string;
  lookup: { province: string; district: string }[];
  est: Est[]; totals: Totals[]; crop: Crop[]; crop_dist: Crop[];
  yield: { pooled: YieldRow[]; by_year: YieldRow[]; ladder: YieldRow[]; crops: string[];
    sensitivity?: { mask: string; crop_name: string; irrigation: string; estimate: number | null; se: number | null; ci_low: number | null; ci_high: number | null;
      n: number; n_psu?: number | null; df?: number | null; n_excluded: number | null; n_zero_harvest: number | null; reliability: Reliability }[] };
  tech: { mix: MixRow[]; sources_any: { sas_year: number; sas_season: Season; source: string; share: number; n: number }[];
          cost: { irrig_tool_level: string; p25: number; median: number; p75: number; n: number }[];
          other_share: { sas_year: number; other_pct: number; dimension: string }[] };
  rain: { rain: RainRow[]; district: NeedRow[] };
  equity: { equity: EquityRow[]; gender_district: (EquityRow & { district_std: string; gender: string })[] };
  screen: { table: ScreenRow[]; default_weights: Record<string, number>; feasibility_missing: string[];
            meta?: { weights: Record<string, number>; sensitivity: string; periods: Record<string, string> } };
  model: {
    performance: { auc: number; brier: number; observed_pct: number; predicted_pct: number; n: number; model: string; validation?: string;
      avg_precision?: number; avg_precision_baseline?: number; brier_baseline_train?: number; brier_baseline_test?: number;
      top10_precision_pct?: number; top10_recall_pct?: number; top10_lift?: number; auc_method?: string }[];
    calibration: { bin: number; predicted_pct: number; observed_pct: number; n: number }[];
    fairness: { group: string; auc: number; n: number; dimension: string; calibration_gap_pts: number }[];
    coefficients: { term: string; odds_ratio: number; or_low: number; or_high: number }[];
    importance: { feature: string; importance: number }[];
    potential: { district_std: string; observed_pct: number; predicted_pct: number; n: number; gap_pts: number }[];
    coef: Record<string, number>; levels: Record<string, (string | number)[]>; n_train: number; n_test: number;
    diagnostics?: { converged: boolean; iterations: number; warnings: string[] | string; fitted_near_0_or_1: number; terms_with_se_over_10: string[];
      design_df: number; n_segments_train: number; test_segments_in_train_pct: number; decision_date: string };
  };
  model_yield: {
    table: { crop_name: string; raw_pct: number; adjusted_pct: number; adjusted_low: number; adjusted_high: number; n: number; n_irrigated: number }[];
    controls: string; estimands?: Record<string, string>; eligibility?: string; excluded_seasons?: { season: string; area_coverage_pct: number }[];
  };
  meta: {
    built: string; team: string; n_plots: number; n_crop_plots: number; n_farmers: number;
    sources: { source: string; use: string }[];
    season_quality: { sas_year: number; sas_season: Season; area_coverage_pct: number; yield_usable: boolean }[];
    scope?: string;
    layers?: { table: string; layer: string; source?: string }[];
    /** set when the browser data were corrected without a full rebuild */
    interim?: { note: string; pending: string[] };
    skip_audit: Record<string, unknown>[]; join_log: Record<string, unknown>[];
  };
  ahs: { indicators: AhsRow[]; equity: AhsEquity[]; irrigation_mix: AhsMix[]; built: string } | null;
}

export type I18n = Record<string, Record<string, string>>;
export type GeoJSON = { type: string; features: { properties: { district: string; province: string } }[] };

# ============================================================================
# 09_Run_All.R  -  rebuild everything the dashboard needs, in order
# SmartIrrigate Rwanda - Team NiyoIshimwe - NISR 2026 Big Data Hackathon
#
# Run from the Hackathon project root:  source("SCRIPTS/09_Run_All.R")
#   05  select irrigation columns     -> DATA/processed/selection/
#   06  merge harmonised master tables -> DATA/processed/master/
#   07  survey-weighted app tables     -> SCRIPTS/app/data/
#   08  adoption + yield models        -> SCRIPTS/app/data/
# Then start the app:  shiny::runApp("SCRIPTS/app")
#
# Set run_select = FALSE to skip step 05 when DATA/processed/selection is
# already up to date (05 needs 04_Load_Data.R, which reads all 111 SAS files).
# ============================================================================

run_select <- TRUE
steps <- c(if (run_select) "05_Select_Irrigation_Data.R",
           "06_Merge_Master_Data.R", "07_Build_App_Data.R", "08_Models.R")

for (s in steps) {
  message("\n==== ", s, " ====")
  t0 <- Sys.time()
  # each script runs in its own environment, so rm(list = ls()) inside a
  # script does not wipe this loop
  source(file.path("SCRIPTS", s), local = new.env(), encoding = "UTF-8")
  message("==== ", s, " done in ", round(difftime(Sys.time(), t0, units = "mins"), 1), " min")
}
message("\nAll done. Start the dashboard with: shiny::runApp(\"SCRIPTS/app\")")

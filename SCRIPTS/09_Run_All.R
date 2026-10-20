# ============================================================================
# 09_Run_All.R  -  rebuild everything the dashboard needs, in order
# SmartIrrigate Rwanda - Team NiyoIshimwe - NISR 2026 Big Data Hackathon
#
# Run from the Hackathon project root:  source("SCRIPTS/09_Run_All.R")
#   05  select irrigation columns     -> DATA/processed/selection/
#   06  merge harmonised master tables -> DATA/processed/master/
#   10  AHS 2017/2020/2024 indicators  -> DATA/processed/ahs/ (needs the AHS .dta files)
#   14  published NISR reference cells -> DATA/processed/official/ (needs the official
#       workbooks in DATA/NISR_published/; skipped with a message when they are missing)
#   07  survey-weighted app tables     -> SCRIPTS/app/data/
#   08  adoption + yield models        -> SCRIPTS/app/data/
#   12  web export (JSON)              -> SCRIPTS/web/public/data/  (no push)
# Then start the app:  shiny::runApp("SCRIPTS/app")
# or the website:      cd SCRIPTS/web; npm ci; npm run dev
# Nothing is committed or pushed by this script. Inputs: see README "Inputs".
#
# Set run_select = FALSE to skip step 05 when DATA/processed/selection is
# already up to date (05 needs 04_Load_Data.R, which reads all 111 SAS files).
# ============================================================================

run_select <- TRUE
run_ahs    <- dir.exists(file.path("DATA", "Agriculture Household Survey"))
Sys.setenv(SI_AUTO_PUSH = "FALSE")      # 12 never pushes from here
steps <- c(if (run_select) "05_Select_Irrigation_Data.R",
           "06_Merge_Master_Data.R", if (run_ahs) "10_AHS_Preparation.R", "14_Official_Reference.R",
           "07_Build_App_Data.R", "08_Models.R", "12_Export_Web_Data.R")

for (s in steps) {
  message("\n==== ", s, " ====")
  t0 <- Sys.time()
  # each script runs in its own environment, so rm(list = ls()) inside a
  # script does not wipe this loop
  source(file.path("SCRIPTS", s), local = new.env(), encoding = "UTF-8")
  message("==== ", s, " done in ", round(difftime(Sys.time(), t0, units = "mins"), 1), " min")
}
message("\nAll done. Start the dashboard with: shiny::runApp(\"SCRIPTS/app\")")
writeLines(capture.output(sessionInfo()), file.path("DATA", "processed", "logs", "sessionInfo.txt"))

# ============================================================================
# 13_Push_To_GitHub.R  -  send every project change to GitHub (and so to Vercel)
# SmartIrrigate Rwanda - Team NiyoIshimwe - NISR 2026 Big Data Hackathon
#
# Commits everything that changed in the Hackathon folder, brings in changes
# already on GitHub (for example from Claude), and pushes to master. Vercel
# rebuilds the website on every push to master.
#
# .gitignore decides what never leaves your computer: NISR microdata (DATA/SAS,
# AHS, DATA/processed), R session files and secrets. Files over 95 MB are
# skipped because GitHub refuses them.
#
# Runs on its own:  source("SCRIPTS/13_Push_To_GitHub.R"); push_project()
# and at the end of 12_Export_Web_Data.R. Set Sys.setenv(SI_AUTO_PUSH = "FALSE")
# to export without pushing.
# Needs the gert package and the GitHub sign-in you already use with gert.
# ============================================================================

push_project <- function(msg = NULL, root = Sys.getenv("HACKATHON_ROOT", "."), max_mb = 95) {
  if (!requireNamespace("gert", quietly = TRUE)) {
    message("Not pushed: install the gert package first (install.packages(\"gert\"))")
    return(invisible(FALSE))
  }
  repo <- tryCatch(gert::git_find(root), error = function(e) NULL)
  if (is.null(repo)) {
    message("Not pushed: ", normalizePath(root), " is not inside a git folder")
    return(invisible(FALSE))
  }
  branch <- gert::git_branch(repo = repo)
  if (!identical(branch, "master")) {
    message("Not pushed: you are on branch '", branch, "'; the website follows master")
    return(invisible(FALSE))
  }

  # stage what changed (git_status already leaves out everything in .gitignore)
  st <- gert::git_status(repo = repo)
  if (nrow(st)) {
    gone <- st$file[st$status == "deleted"]
    keep <- setdiff(unique(st$file), gone)
    size <- file.size(file.path(repo, keep))
    big  <- keep[!is.na(size) & size > max_mb * 1e6]
    if (length(big)) message("Skipped (over ", max_mb, " MB, GitHub refuses them): ", paste(big, collapse = ", "))
    # second line of defence after .gitignore: unit-level survey files and secrets are never
    # committed, even if someone edits .gitignore (aggregates in SCRIPTS/app/data are fine)
    private <- keep[grepl("\\.(dta|sav|sas7bdat|zip|RData|Rhistory)$|(^|/)\\.Renviron$|(^|/)\\.env$|\\.(pem|key)$", keep, ignore.case = TRUE) |
                    grepl("^DATA/(SAS|processed|Agriculture Household Survey)/", keep) |
                    (grepl("^DATA/", keep) & grepl("\\.rds$", keep, ignore.case = TRUE))]
    if (length(private)) message("Never committed (microdata or secrets): ", paste(private, collapse = ", "))
    add <- setdiff(keep, c(big, private))
    if (length(add))  gert::git_add(add, repo = repo)
    if (length(gone)) gert::git_rm(gone, repo = repo)
  }
  staged <- gert::git_status(staged = TRUE, repo = repo)
  if (nrow(staged)) {
    if (is.null(msg)) msg <- paste("Update project files", format(Sys.time(), "%Y-%m-%d %H:%M"))
    gert::git_commit(msg, repo = repo)
    message("Committed ", nrow(staged), " file(s): ", msg)
  }

  # bring in changes already on GitHub, then push
  ok <- tryCatch({ gert::git_pull(repo = repo); TRUE }, error = function(e) {
    message("Not pushed: could not merge the changes on GitHub (", conditionMessage(e), ").\n",
            "Open the folder in RStudio's Git tab or GitHub Desktop, fix the conflict, then run push_project() again.")
    FALSE
  })
  if (!ok) return(invisible(FALSE))
  ahead <- gert::git_ahead_behind(repo = repo)$ahead
  if (!isTRUE(ahead > 0)) {
    message("GitHub is already up to date")
    return(invisible(TRUE))
  }
  gert::git_push(repo = repo)
  message("Pushed ", ahead, " commit(s) to GitHub master; Vercel will update the website in a minute or two")
  invisible(TRUE)
}

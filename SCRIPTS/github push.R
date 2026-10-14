# 1. Set your Git identity
gert::git_config_global_set("user.name", "umumasayii")
gert::git_config_global_set("user.email", "brancharich@gmail.com")

# 2. Stage all files in the SCRIPTS folder (including subdirectories)
script_files <- list.files("SCRIPTS", full.names = TRUE, recursive = TRUE)
gert::git_add(script_files)

# 3. Commit all staged files
gert::git_commit("Add and update all scripts in SCRIPTS folder")

# 4. Push changes to GitHub
gert::git_push(remote = "origin", set_upstream = TRUE)
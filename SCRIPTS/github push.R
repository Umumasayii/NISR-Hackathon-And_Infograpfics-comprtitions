# 1. Set your Git identity
gert::git_config_global_set("user.name", "umumasayii")
gert::git_config_global_set("user.email", "brancharich@gmail.com")

gert::git_add("SCRIPTS/06_Merge_Master_Data.R")
gert::git_commit("Add 06_Merge_Master_Data.R")
gert::git_push(remote = "origin", set_upstream = TRUE)
system("git push -u origin master") 
# Note: If your default branch is 'main', use: system("git push -u origin main")


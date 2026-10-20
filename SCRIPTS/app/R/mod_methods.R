# ---- Page 10: Methods, data quality, AI disclosure and downloads -------------
downloads <- list(
  est_plot = function() D$est, totals = function() D$totals, crop_season = function() D$crop,
  priority_screening = function() D$screen$table, need_adoption = function() D$rain$district,
  yield_adjusted = function() D$model_yield$table, model_validation = function() D$model$performance)

# ONE general data source for the whole app: the team writes it in DATA_SOURCE.md
# (read once at start-up; restart the app after editing it)
DATA_SOURCE_HTML <- if (file.exists("DATA_SOURCE.md"))
  HTML(markdown::mark(text = paste(readLines("DATA_SOURCE.md", encoding = "UTF-8", warn = FALSE), collapse = "\n")))

mod_methods_ui <- function(id, tr) {
  ns <- NS(id)
  tagList(
    navset_card_tab(
      nav_panel(tr("t_about"), icon = fontawesome::fa("seedling"),
        layout_columns(col_widths = c(7, 5),
          div(h4(tr("about_title")), p(tr("about_text")),
              h5(tr("personas")),
              tags$ul(tags$li(strong(tr("persona_farmer")), " ", tr("persona_farmer_txt")),
                      tags$li(strong(tr("persona_planner")), " ", tr("persona_planner_txt")),
                      tags$li(strong(tr("persona_research")), " ", tr("persona_research_txt"))),
              h5(tr("team")), p(tr("footer_by"))),
          div(h5(tr("sources")), uiOutput(ns("sources")),
              h5(tr("reliability")), uiOutput(ns("rel_legend"))))),
      nav_panel(tr("t_pipeline"), icon = fontawesome::fa("diagram-project"),
        tags$ol(class = "pipeline",
          lapply(1:7, \(i) tags$li(strong(tr(paste0("pipe_", i, "_t"))), " ", tr(paste0("pipe_", i)))))),
      nav_panel(tr("t_traps"), icon = fontawesome::fa("triangle-exclamation"),
        tags$ul(class = "traps", lapply(1:9, \(i) tags$li(tr(paste0("trap_", i))))),
        h5(class = "mt-4", tr("cov_title")), p(class = "muted", tr("cov_help")), uiOutput(ns("coverage")),
        h5(tr("skip_audit")), p(class = "muted", tr("skip_audit_help")), DT::DTOutput(ns("skip")),
        h5(class = "mt-4", tr("join_log")), p(class = "muted", tr("join_log_help")), DT::DTOutput(ns("joins"))),
      nav_panel(tr("t_kpi"), icon = fontawesome::fa("ruler"),
        p(tr("kpi_rule")), uiOutput(ns("kpi_defs")),
        h5(class = "mt-4", tr("pub_title")), p(class = "muted", tr("pub_note")), uiOutput(ns("pub")),
        h5(class = "mt-4", tr("pub_align_title")), p(class = "muted", tr("pub_align_note")), uiOutput(ns("pub_align")),
        h5(class = "mt-4", tr("bench_title")), p(class = "muted", tr("bench_note")), uiOutput(ns("bench"))),
      nav_panel(tr("t_ai"), icon = fontawesome::fa("robot"),
        p(tr("ai_text")), tags$ul(lapply(1:4, \(i) tags$li(tr(paste0("ai_", i)))))),
      nav_panel(tr("t_downloads"), icon = fontawesome::fa("download"),
        p(tr("downloads_text")),
        div(class = "dl-grid", lapply(names(downloads), \(x)
          downloadButton(ns(paste0("dl_", x)), tr(paste0("dl_", x)), class = "btn-outline-primary"))))))
}

mod_methods_server <- function(id, f, tr) {
  moduleServer(id, function(input, output, session) {
    # plain HTML tables: renderTable() drops accented letters (é, è) in some locales
    html_table <- function(d) tags$table(class = "table table-sm table-striped profile-table",
      tags$thead(tags$tr(lapply(names(d), tags$th))),
      tags$tbody(lapply(seq_len(nrow(d)), \(i) tags$tr(lapply(d[i, , drop = TRUE], \(v) tags$td(as.character(v)))))))
    output$sources <- renderUI(
      if (!is.null(DATA_SOURCE_HTML)) div(class = "data-source", DATA_SOURCE_HTML) else
        html_table(D$meta$sources |> setNames(c(tr("source"), tr("used_for")))))
    output$rel_legend <- renderUI(tagList(
      p(rel_badge("Good", tr), " ", tr("rel_good")), p(rel_badge("Use with caution", tr), " ", tr("rel_caution")),
      p(rel_badge("Unreliable", tr), " ", tr("rel_unreliable")),
      p(rel_badge("Published", tr), " ", tr("rel_published"))))
    output$skip <- DT::renderDT(DT::datatable(
      D$meta$skip_audit |> select(variable, ys, skip_confirmed, blanks_set_to_no, rows, gate_present_pct, gate_no,
                                  answered_when_gate_no),
      rownames = FALSE, class = "compact stripe", options = list(pageLength = 8, scrollX = TRUE, dom = "ftip")))
    output$joins <- DT::renderDT(DT::datatable(D$meta$join_log, rownames = FALSE, class = "compact stripe",
                                               options = list(pageLength = 8, scrollX = TRUE, dom = "ftip")))
    output$kpi_defs <- renderUI({
      k <- c("irrigated", "irrig_any_farmer", "irrig_modern", "irrigated_area_ha", "yield", "adjusted", "sales", "need", "priority")
      html_table(data.frame(KPI = sapply(paste0("kd_", k, "_n"), tr), Definition = sapply(paste0("kd_", k), tr)) |>
        setNames(c("KPI", tr("definition"))))
    })
    output$coverage <- renderUI({
      q <- D$meta$season_quality; if (is.null(q)) return(NULL)
      html_table(q |> transmute(s = paste0(sas_year, sas_season), p = paste0(round(area_coverage_pct), "%"),
                                x = if_else(yield_usable, "\u2713", tr("yield_excluded", paste0(sas_year, sas_season)))) |>
                   setNames(c(tr("season"), "%", "")))
    })
    # NISR published figures used in the app (they replace our estimate where both exist)
    output$pub <- renderUI({
      h <- D$meta$published$headline; if (is.null(h)) return(NULL)
      nm <- c(irrig_any_farmer = "ind_irrig_any_farmer", inorganic_fert = "ind_inorganic_fert", organic_fert = "ind_organic_fert",
              pesticide = "ind_pesticide", cultivated_area_ha = "pub_cultivated", modern_irrig_area_ha = "pub_modern_area")
      h <- h |> filter(indicator %in% names(nm)) |>
        mutate(v = if_else(unit == "%", fmt_pct(value), paste(fmt_num(value), "ha")), s = paste0(sas_year, sas_season)) |>
        select(indicator, s, v, nisr_table)
      m <- D$est |> filter(level == "national", indicator == "irrig_modern", source == "nisr") |>
        transmute(indicator, s = paste0(sas_year, sas_season), v = fmt_pct(estimate), nisr_table)
      d <- bind_rows(h, m) |> tidyr::pivot_wider(id_cols = indicator, names_from = s, values_from = v) |>
        mutate(indicator = sapply(c(nm, irrig_modern = "ind_irrig_modern")[indicator], tr))
      html_table(d |> rename(!!tr("indicator") := indicator))
    })
    output$pub_align <- renderUI({
      a <- D$meta$published$totals_alignment; if (is.null(a) || !nrow(a)) return(NULL)
      c <- D$meta$published$production_alignment |> filter(abs(survey_vs_published_pct) >= 10) |> arrange(season, crop_name)
      tagList(
        html_table(a |> transmute(s = season, x = paste(fmt_num(survey_t / 1000), "kt"), y = paste(fmt_num(published_t / 1000), "kt"),
                                  z = paste0(survey_vs_published_pct, "%")) |>
                     setNames(c(tr("season"), tr("pub_survey"), tr("pub_published"), tr("pub_diff")))),
        if (nrow(c)) p(class = "muted", tr("pub_align_crops", paste0(c$crop_name, " ", c$season, " (", c$survey_vs_published_pct, "%)", collapse = ", "))))
    })
    output$bench <- renderUI({
      b <- D$meta$benchmarks; if (is.null(b)) return(NULL)
      tags$table(class = "table table-sm profile-table",
        tags$tbody(lapply(seq_len(nrow(b)), \(i) tags$tr(
          tags$td(tr(paste0("bench_", b$key[i]))),
          tags$td(strong(if (b$unit[i] == "ha") paste(fmt_num(b$value[i]), "ha") else fmt_pct(b$value[i]))),
          tags$td(b$period[i]),
          tags$td(tags$a(href = b$url[i], target = "_blank", b$source[i]))))))
    })
    for (x in names(downloads)) local({
      nm <- x
      output[[paste0("dl_", nm)]] <- downloadHandler(
        filename = function() paste0("smartirrigate_", nm, ".csv"),
        content = function(file) utils::write.csv(downloads[[nm]](), file, row.names = FALSE))
    })
  })
}

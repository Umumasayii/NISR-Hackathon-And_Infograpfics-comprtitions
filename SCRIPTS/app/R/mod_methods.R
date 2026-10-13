# ---- Page 10: Methods, data quality, AI disclosure and downloads -------------
downloads <- list(
  est_plot = function() D$est, totals = function() D$totals, crop_season = function() D$crop,
  priority_screening = function() D$screen$table, need_adoption = function() D$rain$district,
  yield_adjusted = function() D$model_yield$table, model_validation = function() D$model$performance)

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
          div(h5(tr("sources")), tableOutput(ns("sources")),
              h5(tr("reliability")), uiOutput(ns("rel_legend"))))),
      nav_panel(tr("t_pipeline"), icon = fontawesome::fa("diagram-project"),
        tags$ol(class = "pipeline",
          lapply(1:7, \(i) tags$li(strong(tr(paste0("pipe_", i, "_t"))), " ", tr(paste0("pipe_", i)))))),
      nav_panel(tr("t_traps"), icon = fontawesome::fa("triangle-exclamation"),
        tags$ul(class = "traps", lapply(1:7, \(i) tags$li(tr(paste0("trap_", i))))),
        h5(tr("skip_audit")), p(class = "muted", tr("skip_audit_help")), DT::DTOutput(ns("skip")),
        h5(class = "mt-4", tr("join_log")), p(class = "muted", tr("join_log_help")), DT::DTOutput(ns("joins"))),
      nav_panel(tr("t_kpi"), icon = fontawesome::fa("ruler"),
        p(tr("kpi_rule")), tableOutput(ns("kpi_defs"))),
      nav_panel(tr("t_ai"), icon = fontawesome::fa("robot"),
        p(tr("ai_text")), tags$ul(lapply(1:4, \(i) tags$li(tr(paste0("ai_", i)))))),
      nav_panel(tr("t_downloads"), icon = fontawesome::fa("download"),
        p(tr("downloads_text")),
        div(class = "dl-grid", lapply(names(downloads), \(x)
          downloadButton(ns(paste0("dl_", x)), tr(paste0("dl_", x)), class = "btn-outline-primary"))))))
}

mod_methods_server <- function(id, f, tr) {
  moduleServer(id, function(input, output, session) {
    output$sources <- renderTable(D$meta$sources |> setNames(c(tr("source"), tr("used_for"))), striped = TRUE, width = "100%")
    output$rel_legend <- renderUI(tagList(
      p(rel_badge("Good", tr), " ", tr("rel_good")), p(rel_badge("Use with caution", tr), " ", tr("rel_caution")),
      p(rel_badge("Unreliable", tr), " ", tr("rel_unreliable"))))
    output$skip <- DT::renderDT(DT::datatable(
      D$meta$skip_audit |> select(variable, ys, skip_confirmed, blanks_set_to_no, rows, gate_present_pct, gate_no,
                                  answered_when_gate_no),
      rownames = FALSE, class = "compact stripe", options = list(pageLength = 8, scrollX = TRUE, dom = "ftip")))
    output$joins <- DT::renderDT(DT::datatable(D$meta$join_log, rownames = FALSE, class = "compact stripe",
                                               options = list(pageLength = 8, scrollX = TRUE, dom = "ftip")))
    output$kpi_defs <- renderTable({
      k <- c("irrigated", "irrig_modern", "irrigated_area_ha", "yield", "adjusted", "need", "priority")
      data.frame(KPI = sapply(paste0("kd_", k, "_n"), tr), Definition = sapply(paste0("kd_", k), tr)) |>
        setNames(c("KPI", tr("definition")))
    }, striped = TRUE, width = "100%")
    for (x in names(downloads)) local({
      nm <- x
      output[[paste0("dl_", nm)]] <- downloadHandler(
        filename = function() paste0("smartirrigate_", nm, ".csv"),
        content = function(file) utils::write.csv(downloads[[nm]](), file, row.names = FALSE))
    })
  })
}

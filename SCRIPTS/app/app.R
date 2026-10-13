# ============================================================================
# SmartIrrigate Rwanda  -  Powered by Team NiyoIshimwe
# NISR 2026 Big Data Hackathon, Track 1 (Agricultural Productivity)
#
# Run locally (from the Hackathon folder):  shiny::runApp("SCRIPTS/app")
# Deploy:  rsconnect::deployApp("SCRIPTS/app", appName = "smartirrigate-rwanda")
# Data:    SCRIPTS/app/data is built by SCRIPTS/07_Build_App_Data.R and 08_Models.R
# Language: add ?lang=en, ?lang=rw or ?lang=fr to the URL (buttons in the navbar)
# Files in R/ are loaded automatically by Shiny.
# ============================================================================

suppressPackageStartupMessages({
  library(shiny); library(bslib); library(plotly); library(dplyr); library(tidyr)
})

theme <- bs_theme(
  version = 5, bg = brand$canvas, fg = brand$ink,
  primary = brand$green, secondary = brand$blue, success = brand$green,
  warning = brand$amber, danger = brand$terracotta, info = brand$blue,
  # fonts are bundled in www/fonts (no download at start-up)
  base_font = "'Plus Jakarta Sans', 'Segoe UI', system-ui, sans-serif",
  heading_font = "'Sora', 'Segoe UI', system-ui, sans-serif",
  "font-size-base" = "0.97rem", "border-radius" = "0.75rem", "card-border-color" = "#E4EAE5",
  "card-cap-bg" = "#FFFFFF", "navbar-bg" = "#FFFFFF", "headings-font-weight" = "700")

ui <- function(request) {
  lang <- get_lang(request$QUERY_STRING)
  tr <- make_tr(lang)
  lang_links <- div(class = "lang-switch", lapply(names(langs), \(l)
    a(href = paste0("?lang=", l), class = if (l == lang) "active" else NULL, toupper(l), title = langs[[l]])))

  sidebar_ui <- sidebar(
    width = 290, open = "desktop",
    div(class = "sidebar-title", fontawesome::fa("sliders"), " ", tr("filters")),
    sliderInput("years", tr("years"), min = min(YEARS), max = max(YEARS), value = range(YEARS), sep = "", step = 1),
    checkboxGroupInput("seasons", tr("seasons"), inline = TRUE,
                       choices = setNames(c("A", "B", "C"), c(tr("season_a"), tr("season_b"), tr("season_c"))),
                       selected = c("A", "B")),
    selectInput("province", tr("province"), choices = c(setNames("", tr("all_rwanda")), sort(unique(D$lookup$province)))),
    selectInput("district", tr("district"), choices = c(setNames("", tr("all")), D$lookup$district)),
    selectInput("crop_group", tr("crop_group"), choices = c(setNames("", tr("all")), CROP_GRPS)),
    selectInput("crop", tr("crop"), choices = c(setNames("", tr("all")), sort(unique(D$crop$crop_name)))),
    radioButtons("gender", tr("gender"), inline = TRUE,
                 choices = setNames(c("", "Female", "Male"), c(tr("all"), tr("female"), tr("male")))),
    actionButton("reset", tr("reset"), icon = icon("rotate-left"), class = "btn-outline-secondary btn-sm"),
    hr(),
    div(class = "filter-note", fontawesome::fa("circle-info"), " ", tr("filter_note")))

  page_navbar(
    title = div(class = "brand", img(src = "logo.svg", height = "34px"),
                span(class = "brand-name", "SmartIrrigate Rwanda")),
    id = "nav", theme = theme, sidebar = sidebar_ui, fillable = FALSE,
    header = tags$head(tags$link(rel = "stylesheet", href = "fonts/fonts.css"),
                       tags$link(rel = "stylesheet", href = "custom.css"),
                       tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
                       tags$title("SmartIrrigate Rwanda"),
                       tags$script(sprintf("document.documentElement.lang = '%s';", lang)),
                       tags$script(src = "app.js")),
    nav_menu(tr("menu_story"), icon = fontawesome::fa("book-open"),
      nav_panel(tr("p_overview"), value = "overview", icon = fontawesome::fa("house"), mod_overview_ui("overview", tr)),
      nav_panel(tr("p_map"), value = "map", icon = fontawesome::fa("map-location-dot"), mod_map_ui("map", tr)),
      nav_panel(tr("p_district"), value = "district", icon = fontawesome::fa("id-card"), mod_district_ui("district", tr)),
      nav_panel(tr("p_need"), value = "need", icon = fontawesome::fa("cloud-sun-rain"), mod_need_ui("need", tr))),
    nav_menu(tr("menu_analyse"), icon = fontawesome::fa("chart-column"),
      nav_panel(tr("p_explorer"), value = "explorer", icon = fontawesome::fa("table-cells"), mod_explorer_ui("explorer", tr)),
      nav_panel(tr("p_evidence"), value = "evidence", icon = fontawesome::fa("seedling"), mod_evidence_ui("evidence", tr)),
      nav_panel(tr("p_how"), value = "how", icon = fontawesome::fa("faucet-drip"), mod_how_ui("how", tr)),
      nav_panel(tr("p_who"), value = "who", icon = fontawesome::fa("people-group"), mod_who_ui("who", tr))),
    nav_menu(tr("menu_act"), icon = fontawesome::fa("compass"),
      nav_panel(tr("p_model"), value = "model", icon = fontawesome::fa("brain"), mod_model_ui("model", tr)),
      nav_panel(tr("p_priority"), value = "priority", icon = fontawesome::fa("ranking-star"), mod_priority_ui("priority", tr))),
    nav_panel(tr("p_methods"), value = "methods", icon = fontawesome::fa("circle-info"), mod_methods_ui("methods", tr)),
    nav_spacer(),
    nav_item(lang_links),
    footer = div(class = "app-footer",
                 span(tr("footer_by")), span(" \u00B7 "),
                 span(tr("footer_sources")), span(" \u00B7 "),
                 span(paste(tr("built"), D$meta$built))))
}

server <- function(input, output, session) {
  lang <- isolate(get_lang(session$clientData$url_search))
  tr <- make_tr(lang)

  # province -> district, crop group -> crop
  observeEvent(input$province, {
    ds <- if (nzchar(input$province)) D$lookup$district[D$lookup$province == input$province] else D$lookup$district
    updateSelectInput(session, "district", choices = c(setNames("", tr("all")), ds),
                      selected = if (input$district %in% ds) input$district else "")
  }, ignoreInit = TRUE)
  observeEvent(input$crop_group, {
    cs <- D$crop |> filter(!nzchar(input$crop_group) | crop_group == input$crop_group) |> pull(crop_name) |> unique() |> sort()
    updateSelectInput(session, "crop", choices = c(setNames("", tr("all")), cs))
  }, ignoreInit = TRUE)
  observeEvent(input$reset, {
    updateSliderInput(session, "years", value = range(YEARS))
    updateCheckboxGroupInput(session, "seasons", selected = c("A", "B"))
    for (s in c("province", "district", "crop_group", "crop")) updateSelectInput(session, s, selected = "")
    updateRadioButtons(session, "gender", selected = "")
  })

  # One reactive with every filter; pages use only the filters their tables support
  f <- reactive({
    seasons <- input$seasons %||% c("A", "B")
    area_level <- if (nzchar(input$district)) "district" else if (nzchar(input$province)) "province" else "national"
    list(years = input$years[1]:input$years[2], seasons = seasons,
         province = input$province, district = input$district,
         crop_group = input$crop_group, crop = input$crop, gender = input$gender,
         area_level = area_level,
         area = switch(area_level, district = input$district, province = input$province, national = "Rwanda"))
  })
  # a click on any map selects that district
  set_district <- function(d) {
    if (is.null(d) || !d %in% D$lookup$district) return()
    updateSelectInput(session, "province", selected = D$lookup$province[D$lookup$district == d])
    updateSelectInput(session, "district", selected = d)
  }

  mod_overview_server("overview", f, tr, goto = function(v) nav_select("nav", v, session = session))
  mod_map_server("map", f, tr, set_district)
  mod_district_server("district", f, tr, set_district)
  mod_need_server("need", f, tr, set_district)
  mod_explorer_server("explorer", f, tr)
  mod_evidence_server("evidence", f, tr)
  mod_how_server("how", f, tr)
  mod_who_server("who", f, tr)
  mod_model_server("model", f, tr)
  mod_priority_server("priority", f, tr, set_district)
  mod_methods_server("methods", f, tr)
}

shinyApp(ui, server, enableBookmarking = "url")

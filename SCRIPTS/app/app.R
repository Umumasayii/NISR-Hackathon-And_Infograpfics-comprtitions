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
  # the system interface font, like a normal website (Segoe UI on Windows)
  base_font = FONT_BODY, heading_font = FONT_BODY,
  "font-size-base" = "0.9375rem", "border-radius" = "0.5rem", "card-border-color" = "#E3E6E4",
  "card-cap-bg" = "#FFFFFF", "navbar-bg" = "#FFFFFF", "headings-font-weight" = "600")

ui <- function(request) {
  lang <- get_lang(request$QUERY_STRING)
  tr <- make_tr(lang)
  lang_links <- div(class = "lang-switch", lapply(names(langs), \(l)
    a(href = paste0("?lang=", l), class = if (l == lang) "active" else NULL, toupper(l), title = langs[[l]])))

  all_d <- D$lookup$district; all_p <- sort(unique(D$lookup$province))
  sidebar_ui <- sidebar(
    width = 300, open = "desktop",
    div(class = "sidebar-head",
        div(class = "sh-icon", fontawesome::fa("sliders")),
        div(div(class = "sidebar-title", tr("filters")), div(class = "sh-sub", tr("filters_sub")))),
    div(class = "filter-group",
        div(class = "fg-title", tr("fg_when")),
        multi_pick("years", tr("years"), setNames(YEARS, YEARS), YEARS, "calendar-days", tr = tr),
        multi_pick("seasons", tr("seasons"), setNames(c("A", "B", "C"), c(tr("season_a"), tr("season_b"), tr("season_c"))),
                   c("A", "B"), "cloud-sun-rain", tr = tr)),
    div(class = "filter-group",
        div(class = "fg-title", tr("fg_where")),
        multi_pick("province", tr("province"), all_p, all_p, "map", tr = tr, all_means = tr("all_rwanda")),
        multi_pick("district", tr("district"), all_d, all_d, "location-dot", search = TRUE, tr = tr)),
    div(class = "filter-group",
        div(class = "fg-title", tr("fg_what")),
        multi_pick("crop_group", tr("crop_group"), CROP_GRPS, CROP_GRPS, "layer-group", tr = tr),
        multi_pick("crop", tr("crop"), sort(unique(D$crop$crop_name)), sort(unique(D$crop$crop_name)), "seedling",
                   search = TRUE, tr = tr)),
    div(class = "filter-actions",
        actionButton("reset", tr("reset"), icon = icon("rotate-left"), class = "btn-reset")),
    div(class = "filter-note", fontawesome::fa("circle-info"), " ", tr("filter_note")))

  page_navbar(
    title = div(class = "brand", img(src = "logo.svg", height = "34px"),
                span(class = "brand-name", "SmartIrrigate Rwanda")),
    id = "nav", theme = theme, sidebar = sidebar_ui, fillable = FALSE,
    header = tags$head(tags$link(rel = "stylesheet", href = "custom.css"),
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
      nav_panel(tr("p_who"), value = "who", icon = fontawesome::fa("people-group"), mod_who_ui("who", tr)),
      nav_panel(tr("p_households"), value = "households", icon = fontawesome::fa("people-roof"), mod_households_ui("households", tr))),
    nav_menu(tr("menu_act"), icon = fontawesome::fa("compass"),
      nav_panel(tr("p_model"), value = "model", icon = fontawesome::fa("brain"), mod_model_ui("model", tr)),
      nav_panel(tr("p_priority"), value = "priority", icon = fontawesome::fa("ranking-star"), mod_priority_ui("priority", tr))),
    nav_panel(tr("p_methods"), value = "methods", icon = fontawesome::fa("circle-info"), mod_methods_ui("methods", tr)),
    nav_spacer(),
    nav_item(lang_links),
    footer = div(class = "app-footer",
                 span(tr("footer_by")), span(" \u00B7 "),
                 a(href = "#", onclick = "document.querySelector('a[data-value=methods]').click(); return false;", tr("footer_see_sources")), span(" \u00B7 "),
                 span(paste(tr("built"), D$meta$built))))
}

server <- function(input, output, session) {
  lang <- isolate(get_lang(session$clientData$url_search))
  tr <- make_tr(lang)

  all_d <- D$lookup$district; all_p <- sort(unique(D$lookup$province))
  all_c <- sort(unique(D$crop$crop_name))
  # empty selection = everything
  sel <- function(x, all) if (length(x)) intersect(x, all) else all

  # province -> district list, crop group -> crop list (keep what is still valid)
  dist_scope <- reactiveVal(all_d)
  observeEvent(input$province, {
    ds <- D$lookup$district[D$lookup$province %in% sel(input$province, all_p)]
    cur <- input$district
    was_all <- !length(cur) || all(dist_scope() %in% cur)   # districts were not narrowed
    keep <- if (was_all) ds else intersect(cur, ds)
    dist_scope(ds)
    updateCheckboxGroupInput(session, "district", choices = ds, selected = if (length(keep)) keep else ds)
  }, ignoreInit = TRUE, ignoreNULL = FALSE)
  observeEvent(input$crop_group, {
    cs <- D$crop |> filter(crop_group %in% sel(input$crop_group, CROP_GRPS)) |> pull(crop_name) |> unique() |> sort()
    updateCheckboxGroupInput(session, "crop", choices = cs, selected = cs)
  }, ignoreInit = TRUE, ignoreNULL = FALSE)
  observeEvent(input$reset, {
    updateCheckboxGroupInput(session, "years", selected = YEARS)
    updateCheckboxGroupInput(session, "seasons", selected = c("A", "B"))
    updateCheckboxGroupInput(session, "province", selected = all_p)
    dist_scope(all_d)
    updateCheckboxGroupInput(session, "district", choices = all_d, selected = all_d)
    updateCheckboxGroupInput(session, "crop_group", selected = CROP_GRPS)
    updateCheckboxGroupInput(session, "crop", choices = all_c, selected = all_c)
  })

  # One reactive with every filter (see R/fct_data.R for the fields)
  f <- reactive({
    years <- sort(as.integer(sel(input$years, as.character(YEARS))))
    seasons <- if (length(input$seasons)) input$seasons else c("A", "B")
    provs <- sel(input$province, all_p)
    scope <- D$lookup$district[D$lookup$province %in% provs]
    dists <- sel(input$district, scope)
    level <- if (length(dists) < length(scope)) "district" else if (length(provs) < length(all_p)) "province" else "national"
    areas <- switch(level, district = dists, province = provs, national = "Rwanda")
    grps <- sel(input$crop_group, CROP_GRPS)
    crops <- input$crop
    crop_scope <- D$crop |> filter(crop_group %in% grps) |> pull(crop_name) |> unique()
    list(years = years, seasons = seasons, area_level = level, areas = areas, districts = dists,
         provinces = sort(unique(D$lookup$province[D$lookup$district %in% dists])),
         area = if (level == "national") "Rwanda" else short_set(areas),
         district = if (level == "district" && length(dists) == 1) dists else "",
         crop_groups = if (length(grps) < length(CROP_GRPS)) grps else character(),
         crops = if (length(crops) && length(crops) < length(crop_scope)) crops else character())
  })
  # a click on any map selects that district only
  set_district <- function(d) {
    if (is.null(d) || !d %in% all_d) return()
    dist_scope(all_d)
    updateCheckboxGroupInput(session, "province", selected = all_p)
    updateCheckboxGroupInput(session, "district", choices = all_d, selected = d)
  }

  mod_overview_server("overview", f, tr, goto = function(v) nav_select("nav", v, session = session))
  mod_map_server("map", f, tr, set_district)
  mod_district_server("district", f, tr, set_district)
  mod_need_server("need", f, tr, set_district)
  mod_explorer_server("explorer", f, tr)
  mod_evidence_server("evidence", f, tr)
  mod_how_server("how", f, tr)
  mod_who_server("who", f, tr)
  mod_households_server("households", f, tr, set_district)
  mod_model_server("model", f, tr)
  mod_priority_server("priority", f, tr, set_district)
  mod_methods_server("methods", f, tr)
}

shinyApp(ui, server, enableBookmarking = "url")

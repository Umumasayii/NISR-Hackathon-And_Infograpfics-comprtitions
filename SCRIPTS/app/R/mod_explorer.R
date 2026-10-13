# ---- Page 4: Data Explorer - overall products and measures, then filtered ------
explorer_measures <- c("production_t", "crop_area_ha", "yield_kg_ha", "yield_irrigated_kg_ha", "yield_rainfed_kg_ha",
                       "sold_t", "sold_share_pct", "price_rwf_kg", "sales_value_mrwf", "improved_seed_pct")

mod_explorer_ui <- function(id, tr) {
  ns <- NS(id)
  tagList(
    filters_used(tr, c("years", "seasons", "area", "crop")),
    div(class = "callout soft", fontawesome::fa("filter"), " ", tr("explorer_intro")),
    uiOutput(ns("kpis")),
    chart_card(tr("c_treemap"), plotlyOutput(ns("tree"), height = "430px"), ns("tree_means"), tr("src_sas_totals"), icon = "sitemap"),
    layout_columns(
      col_widths = c(6, 6),
      chart_card(tr("c_top_crops"),
                 tagList(selectInput(ns("measure"), NULL, width = "100%",
                                     choices = setNames(explorer_measures, sapply(paste0("ms_", explorer_measures), tr))),
                         plotlyOutput(ns("bycrop"), height = "430px")),
                 ns("bycrop_means"), tr("src_sas_totals")),
      chart_card(tr("c_measure_trend"), plotlyOutput(ns("trend"), height = "470px"), ns("trend_means"), tr("src_sas_totals"))),
    card(class = "chart-card", full_screen = TRUE,
         card_header(div(class = "d-flex justify-content-between align-items-center",
                         span(tr("c_table")),
                         downloadButton(ns("dl"), tr("download_csv"), class = "btn-sm btn-outline-primary"))),
         card_body(DT::DTOutput(ns("table"))),
         card_footer(div(class = "source", tr("src_table")))))
}

mod_explorer_server <- function(id, f, tr) {
  moduleServer(id, function(input, output, session) {
    # Overall (all crops) first, then the crop filter on top
    cr <- reactive(crops_for(f()))

    # weighted mean that drops missing values and missing/zero weights
    wm <- function(x, w) { ok <- !is.na(x) & !is.na(w) & w > 0; if (any(ok)) sum(x[ok] * w[ok]) / sum(w[ok]) else NA_real_ }
    # Aggregate a crop table over the selected seasons: sums for t/ha, ratios recomputed
    agg <- function(d, by) d |> group_by(across(all_of(by))) |>
      summarise(production_t = sum(production_t, na.rm = TRUE), crop_area_ha = sum(crop_area_ha, na.rm = TRUE),
                yield_kg_ha = wm(yield_kg_ha, crop_area_ha),
                yield_irrigated_kg_ha = wm(yield_irrigated_kg_ha, n_irrigated_yield),
                yield_rainfed_kg_ha = wm(yield_rainfed_kg_ha, crop_area_ha),
                sold_t = sum(sold_t, na.rm = TRUE),
                price_rwf_kg = wm(price_rwf_kg, sold_t),
                sales_value_mrwf = sum(sales_value_mrwf, na.rm = TRUE),
                improved_seed_pct = wm(improved_seed_pct, crop_area_ha),
                n_crop_plots = sum(n_crop_plots), n_irrigated_yield = sum(n_irrigated_yield, na.rm = TRUE),
                .groups = "drop") |>
      mutate(sold_share_pct = 100 * sold_t / production_t,
             across(where(is.numeric), \(x) ifelse(is.nan(x), NA, x)))

    output$kpis <- renderUI({
      d <- cr(); if (!nrow(d)) return(div(class = "muted", tr("no_data")))
      ny <- n_distinct(paste(d$sas_year)); a <- agg(d, character())
      label <- if (nzchar(f()$crop)) f()$crop else if (nzchar(f()$crop_group)) f()$crop_group else tr("all_crops")
      ys <- d |> group_by(sas_year) |> summarise(t = sum(production_t, na.rm = TRUE), ha = sum(crop_area_ha, na.rm = TRUE),
                                                 sold = sum(sold_t, na.rm = TRUE), .groups = "drop") |> arrange(sas_year)
      tile_row(
        stat_tile(tr("ms_production_t"), paste(fmt_num(a$production_t / ny / 1000), "kt"), "wheat-awn", "#B07A1C", NULL, TRUE, ys$t,
                  tr("k_per_year", label, f()$area), num = round(a$production_t / ny / 1000), suffix = " kt"),
        stat_tile(tr("ms_crop_area_ha"), paste(fmt_num(a$crop_area_ha / ny / 1000, 1), "k ha"), "seedling", brand$green, NULL, TRUE, ys$ha,
                  tr("k_per_year", label, f()$area), num = round(a$crop_area_ha / ny / 1000, 1), suffix = "k ha", decimals = 1),
        stat_tile(tr("ms_sold_share_pct"), fmt_pct(a$sold_share_pct), "store", brand$blue, NULL, TRUE, 100 * ys$sold / ys$t,
                  tr("k_sold_sub", fmt_num(a$sold_t / ny / 1000), fmt_num(a$sales_value_mrwf / ny / 1000, 1)),
                  num = a$sold_share_pct, suffix = "%", decimals = 1),
        if (nzchar(f()$crop)) stat_tile(tr("ms_yield_kg_ha"), paste(fmt_num(a$yield_kg_ha), "kg/ha"), "scale-balanced", "#6A4C93",
                                        NULL, TRUE, NULL, tr("k_yield_sub", fmt_num(a$n_crop_plots)), num = round(a$yield_kg_ha), suffix = " kg/ha")
        else stat_tile(tr("k_n_crops"), n_distinct(d$crop_name), "list-check", "#6A4C93", NULL, TRUE, NULL, tr("k_n_crops_sub"),
                       num = n_distinct(d$crop_name)))
    })

    # treemap: crop groups -> crops, sized by the chosen measure (click a group to zoom)
    output$tree <- renderPlotly({
      m <- input$measure; req(m)
      tm <- if (m %in% c("production_t", "crop_area_ha", "sold_t", "sales_value_mrwf")) m else "production_t"
      d <- by_crop() |> filter(!is.na(.data[[tm]]), .data[[tm]] > 0)
      validate(need(nrow(d) > 0, tr("no_data")))
      g <- d |> group_by(crop_group) |> summarise(v = sum(.data[[tm]]), .groups = "drop")
      grp <- sort(unique(D$crop$crop_group))
      gcol <- setNames(rep(c(series_cols, brand$grey, "#7FA88F", "#C2A06A", "#7DA7CC"), length.out = length(grp)), grp)
      ids <- c(g$crop_group, paste(d$crop_group, d$crop_name, sep = "/"))
      plot_ly(type = "treemap", ids = ids, labels = c(g$crop_group, d$crop_name), parents = c(rep("", nrow(g)), d$crop_group),
              values = c(g$v, d[[tm]]), branchvalues = "total",
              marker = list(colors = c(unname(gcol[g$crop_group]), unname(gcol[d$crop_group])), line = list(color = "#fff", width = 2)),
              textinfo = "label+percent root", hovertemplate = paste0("<b>%{label}</b><br>", tr(paste0("ms_", tm)),
                                                                     ": %{value:,.0f}<br>%{percentRoot:.1%} <extra></extra>"),
              pathbar = list(visible = TRUE)) |>
        layout(margin = list(l = 0, r = 0, t = 30, b = 0), font = list(family = FONT_BODY), paper_bgcolor = "rgba(0,0,0,0)") |>
        config(displaylogo = FALSE)
    })
    output$tree_means <- renderUI(span(tr("m_tree")))

    by_crop <- reactive(agg(cr(), c("crop_group", "crop_name")))
    output$bycrop <- renderPlotly({
      m <- input$measure; req(m)
      d <- by_crop() |> filter(!is.na(.data[[m]]), n_crop_plots >= 30) |> slice_max(.data[[m]], n = 15) |>
        arrange(.data[[m]])
      validate(need(nrow(d) > 0, tr("no_data")))
      grp <- sort(unique(by_crop()$crop_group))
      cols <- setNames(rep(c(series_cols, brand$grey, "#7FA88F", "#C2A06A", "#7DA7CC"), length.out = length(grp)), grp)
      plot_ly(d, y = ~factor(crop_name, levels = crop_name), x = d[[m]], type = "bar", orientation = "h",
              color = ~crop_group, colors = cols,
              text = ~paste0("<b>", crop_name, "</b> (", crop_group, ")<br>", tr(paste0("ms_", m)), ": ",
                             fmt_num(d[[m]], if (m %in% c("sold_share_pct", "improved_seed_pct")) 1 else 0),
                             "<br>n = ", fmt_num(n_crop_plots)),
              hoverinfo = "text", textposition = "none") |>
        plotly_std(x = tr(paste0("ms_", m))) |> layout(yaxis = list(title = ""), legend = list(y = -0.25))
    })
    output$bycrop_means <- renderUI({
      m <- input$measure; d <- by_crop() |> filter(!is.na(.data[[m]]), n_crop_plots >= 30) |> arrange(desc(.data[[m]]))
      if (!nrow(d)) return(NULL)
      tot_share <- if (m %in% c("production_t", "crop_area_ha", "sold_t", "sales_value_mrwf"))
        fmt_pct(100 * d[[m]][1] / sum(d[[m]]), 0) else NULL
      p(tr("m_bycrop", d$crop_name[1], tr(paste0("ms_", m))),
        if (!is.null(tot_share)) tr("m_bycrop_share", tot_share), " ", tr("m_bycrop_note"))
    })

    trend_d <- reactive(agg(cr(), c("sas_year", "sas_season")))
    output$trend <- renderPlotly({
      m <- input$measure; req(m); d <- trend_d() |> filter(!is.na(.data[[m]]))
      validate(need(nrow(d) > 0, tr("no_data")))
      p <- plot_ly()
      for (s in intersect(c("A", "B", "C"), unique(d$sas_season))) {
        x <- d |> filter(sas_season == s)
        p <- p |> add_trace(x = x$sas_year, y = x[[m]], type = "scatter", mode = "lines+markers",
                            name = tr(paste0("season_", tolower(s))), line = list(color = season_cols[[s]], width = 2),
                            marker = list(color = season_cols[[s]], size = 8),
                            text = paste0(x$sas_year, s, ": ", fmt_num(x[[m]], 1)), hoverinfo = "text")
      }
      plotly_std(p, y = tr(paste0("ms_", m)), dtick = 1)
    })
    output$trend_means <- renderUI({
      m <- input$measure; d <- trend_d() |> filter(!is.na(.data[[m]]), sas_season %in% c("A", "B")) |> arrange(sas_year)
      if (n_distinct(d$sas_year) < 2) return(NULL)
      a <- d |> filter(sas_year == min(sas_year)); b <- d |> filter(sas_year == max(sas_year))
      ch <- 100 * (mean(b[[m]]) / mean(a[[m]]) - 1)
      p(tr("m_measure_trend", tr(paste0("ms_", m)), min(d$sas_year), max(d$sas_year),
           paste0(ifelse(ch > 0, "+", ""), fmt_num(ch, 0), "%")), " ", tr("m_measure_caveat"))
    })

    tbl <- reactive({
      cr() |> select(sas_year, sas_season, crop_group, crop_name, n_crop_plots, all_of(explorer_measures)) |>
        arrange(desc(sas_year), sas_season, desc(production_t)) |>
        mutate(across(where(is.double), \(x) round(x, 1)))
    })
    output$table <- DT::renderDT({
      d <- tbl()
      names(d) <- c(tr("year"), tr("season"), tr("crop_group"), tr("crop"), "n", sapply(paste0("ms_", explorer_measures), tr))
      DT::datatable(d, rownames = FALSE, class = "compact stripe hover",
                    options = list(pageLength = 12, scrollX = TRUE, dom = "ftip",
                                   language = list(search = tr("search"))))
    })
    output$dl <- downloadHandler(
      filename = function() paste0("smartirrigate_crops_", gsub(" ", "_", f()$area), "_", Sys.Date(), ".csv"),
      content = function(file) utils::write.csv(tbl(), file, row.names = FALSE))
  })
}

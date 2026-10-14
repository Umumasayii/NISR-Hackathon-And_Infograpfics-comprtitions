# ---- Page 5: Irrigation & Yield Evidence (observed and adjusted associations) ---
# Section 13: no causal claims. "Raw" = observed difference; "adjusted" = after
# controlling for inputs, crop area, district and season (survey-weighted log model).
mod_evidence_ui <- function(id, tr) {
  ns <- NS(id)
  tagList(
    filters_used(tr, c("years", "seasons", "area", "crop")),
    div(class = "callout", fontawesome::fa("scale-balanced"), " ", tr("evidence_caveat")),
    chart_card(tr("c_forest"), plotlyOutput(ns("forest"), height = "400px"), ns("forest_means"), tr("src_model_yield"),
               icon = "seedling"),
    layout_columns(
      col_widths = c(3, 4, 5),
      card(class = "chart-card", card_header(span(class = "ch-icon", fontawesome::fa("wheat-awn")), span(tr("choose_crop"))),
           card_body(selectInput(ns("crop"), NULL, choices = D$yield$crops, selected = "Maize", width = "100%"),
                     uiOutput(ns("crop_box")))),
      chart_card(tr("c_dumbbell"), plotlyOutput(ns("dumb"), height = "260px"), ns("dumb_means"), tr("src_yield"),
                 icon = "scale-unbalanced"),
      chart_card(tr("c_ladder"), plotlyOutput(ns("ladder"), height = "260px"), ns("ladder_means"), tr("src_ladder"),
                 icon = "stairs")),
    layout_columns(
      col_widths = c(6, 6),
      chart_card(tr("c_yield_year"), plotlyOutput(ns("byyear"), height = "300px"), ns("byyear_means"), tr("src_yield"),
                 icon = "chart-line"),
      chart_card(tr("c_yield_area"), plotlyOutput(ns("yarea"), height = "300px"), ns("yarea_means"), tr("src_yield_area"),
                 icon = "location-dot")))
}

mod_evidence_server <- function(id, f, tr) {
  moduleServer(id, function(input, output, session) {
    # follow the sidebar crop when it has enough irrigated plots
    observeEvent(f()$crops, {
      ok <- intersect(f()$crops, D$yield$crops)
      if (length(ok) && !isolate(input$crop) %in% ok) updateSelectInput(session, "crop", selected = ok[1])
    })
    # crops kept by the sidebar crop and crop-group filters
    crop_scope <- reactive({
      cs <- D$crop |> distinct(crop_group, crop_name)
      if (length(f()$crop_groups)) cs <- filter(cs, crop_group %in% f()$crop_groups)
      if (length(f()$crops)) cs <- filter(cs, crop_name %in% f()$crops)
      cs$crop_name
    })

    output$forest <- renderPlotly({
      d <- D$model_yield$table |> filter(crop_name %in% crop_scope()) |> arrange(adjusted_pct) |>
        mutate(crop_name = factor(crop_name, levels = crop_name))
      validate(need(nrow(d) > 0, tr("no_adjusted")))
      dir_col <- ifelse(d$adjusted_low > 0, col_irrigated, ifelse(d$adjusted_high < 0, brand$terracotta, brand$grey))
      p <- plot_ly(d)
      for (cl in unique(dir_col)) p <- p |>
        add_segments(data = d[dir_col == cl, ], x = ~adjusted_low, xend = ~adjusted_high, y = ~crop_name, yend = ~crop_name,
                     line = list(color = cl, width = 2.5), hoverinfo = "skip", showlegend = FALSE)
      p |>
        add_markers(data = d, x = ~raw_pct, y = ~crop_name, name = tr("raw_diff"),
                    marker = list(symbol = "circle-open", size = 10, color = brand$grey, line = list(width = 2)),
                    text = ~paste0(crop_name, "<br>", tr("raw_diff"), ": ", fmt_num(raw_pct, 0), "%"), hoverinfo = "text") |>
        add_markers(data = d, x = ~adjusted_pct, y = ~crop_name, name = tr("adj_diff"),
                    marker = list(size = 11, color = dir_col),
                    text = ~paste0("<b>", crop_name, "</b><br>", tr("adj_diff"), ": ", fmt_num(adjusted_pct, 0), "% (",
                                   fmt_num(adjusted_low, 0), " to ", fmt_num(adjusted_high, 0), ")<br>n = ", fmt_num(n),
                                   " \u00B7 ", tr("n_irrigated"), " ", fmt_num(n_irrigated)), hoverinfo = "text") |>
        plotly_std(x = tr("x_yield_diff")) |>
        layout(yaxis = list(title = ""),
               shapes = list(list(type = "line", x0 = 0, x1 = 0, y0 = 0, y1 = 1, yref = "paper",
                                  line = list(color = brand$ink, width = 1))))
    })
    output$forest_means <- renderUI({
      d <- D$model_yield$table
      pos <- d |> filter(adjusted_low > 0) |> arrange(desc(adjusted_pct))
      neg <- d |> filter(adjusted_high < 0)
      p(tr("m_forest", nrow(pos), nrow(d),
           if (nrow(pos)) paste0(pos$crop_name, " (+", fmt_num(pos$adjusted_pct, 0), "%)", collapse = ", ") else "\u2013",
           nrow(d) - nrow(pos) - nrow(neg)), " ", tr("m_forest_controls", D$model_yield$controls))
    })

    pooled <- reactive(D$yield$pooled |> filter(crop_name == input$crop))
    output$crop_box <- renderUI({
      m <- D$model_yield$table |> filter(crop_name == input$crop)
      g <- pooled()$crop_group[1]
      tagList(p(class = "muted", g),
              if (nrow(m)) div(class = "big-number", paste0(ifelse(m$adjusted_pct > 0, "+", ""), fmt_num(m$adjusted_pct, 0), "%"),
                               p(class = "kpi-sub", tr("k_adj_sub", fmt_num(m$adjusted_low, 0), fmt_num(m$adjusted_high, 0))))
              else p(class = "muted", tr("no_adjusted")))
    })
    output$dumb <- renderPlotly({
      d <- pooled(); validate(need(nrow(d) > 0, tr("no_data")))
      d <- d |> mutate(st = ifelse(grepl("C", season_type), tr("season_c"), tr("seasons_ab")))
      if (!"C" %in% f()$seasons) d <- filter(d, !grepl("C", season_type))
      if (!any(c("A", "B") %in% f()$seasons)) d <- filter(d, grepl("C", season_type))
      validate(need(nrow(d) > 0, tr("no_data")))
      w <- d |> select(st, irrigation, estimate) |> tidyr::pivot_wider(names_from = irrigation, values_from = estimate)
      p <- plot_ly()
      if (all(c("Irrigated", "Rain-fed") %in% names(w)))
        p <- p |> add_segments(data = w, x = ~`Rain-fed`, xend = ~Irrigated, y = ~st, yend = ~st,
                               line = list(color = "#D5DDD8", width = 6), hoverinfo = "skip", showlegend = FALSE)
      for (g in c("Rain-fed", "Irrigated")) { x <- d |> filter(irrigation == g); if (!nrow(x)) next
        p <- p |> add_markers(data = x, x = ~estimate, y = ~st, name = tr(if (g == "Irrigated") "irrigated" else "rainfed"),
                              marker = list(size = 16, color = if (g == "Irrigated") col_irrigated else col_rainfed,
                                            line = list(color = "#fff", width = 2)),
                              text = ~paste0(g, " \u00B7 ", st, "<br><b>", fmt_num(estimate), " kg/ha</b> (95% CI ", fmt_num(ci_low), "\u2013",
                                             fmt_num(ci_high), ")<br>n = ", fmt_num(n), " \u00B7 ", reliability), hoverinfo = "text") }
      plotly_std(p, x = tr("y_yield")) |> layout(yaxis = list(title = ""), legend = list(y = -0.3))
    })
    output$dumb_means <- renderUI({
      d <- pooled() |> filter(grepl("main", season_type))
      if (nrow(d) < 2) return(NULL)
      i <- d |> filter(irrigation == "Irrigated"); r <- d |> filter(irrigation == "Rain-fed")
      overlap <- !(i$ci_low > r$ci_high || i$ci_high < r$ci_low)
      p(tr(if (overlap) "m_dumb_overlap" else "m_dumb_diff", input$crop, fmt_num(i$estimate), fmt_num(r$estimate)),
        " ", rel_badge(i$reliability, tr))
    })

    output$byyear <- renderPlotly({
      d <- D$yield$by_year |> filter(crop_name == input$crop, sas_year %in% f()$years); validate(need(nrow(d) > 0, tr("no_data")))
      p <- plot_ly()
      for (g in c("Rain-fed", "Irrigated")) {
        x <- d |> filter(irrigation == g); cl <- if (g == "Irrigated") col_irrigated else col_rainfed
        p <- p |> add_trace(data = x, x = ~sas_year, y = ~estimate, type = "scatter", mode = "lines+markers", name = tr(if (g == "Irrigated") "irrigated" else "rainfed"),
                            line = list(color = cl, width = 3, shape = "spline", smoothing = 0.5),
                            marker = list(color = cl, size = 8, line = list(color = "#fff", width = 2)),
                            text = ~paste0(g, " ", sas_year, ": ", fmt_num(estimate), " kg/ha<br>n = ", fmt_num(n),
                                           " \u00B7 ", reliability), hoverinfo = "text")
      }
      plotly_std(p, y = tr("y_yield"), dtick = 1) |> layout(hovermode = "x unified")
    })
    output$byyear_means <- renderUI({
      d <- D$yield$by_year |> filter(crop_name == input$crop) |>
        select(sas_year, irrigation, estimate) |> tidyr::pivot_wider(names_from = irrigation, values_from = estimate) |>
        filter(!is.na(Irrigated), !is.na(`Rain-fed`))
      if (!nrow(d)) return(NULL)
      p(tr("m_byyear", sum(d$Irrigated > d$`Rain-fed`), nrow(d), input$crop))
    })

    output$ladder <- renderPlotly({
      d <- D$yield$ladder |> filter(crop_name == input$crop); validate(need(nrow(d) > 0, tr("no_data")))
      plot_ly(d, x = ~factor(modern_inputs_n), y = ~estimate, type = "bar",
              marker = list(color = ifelse(d$reliability == "Unreliable", "#C9D8CF", col_irrigated)),
              text = ~paste0(modern_inputs_n, " ", tr("inputs"), ": ", fmt_num(estimate), " kg/ha<br>n = ", fmt_num(n),
                             " \u00B7 ", reliability), hoverinfo = "text", textposition = "none") |>
        plotly_std(x = tr("x_modern_inputs"), y = tr("y_yield"), legend = FALSE) |> layout(bargap = 0.35)
    })
    output$ladder_means <- renderUI({
      d <- D$yield$ladder |> filter(crop_name == input$crop, reliability != "Unreliable") |> arrange(modern_inputs_n)
      if (nrow(d) < 2) return(NULL)
      p(tr("m_ladder", input$crop, fmt_num(d$estimate[1]), fmt_num(tail(d$estimate, 1)), tail(d$modern_inputs_n, 1)))
    })

    # ---- irrigated vs rain-fed yield in the selected area and years (raw, no adjustment)
    yarea_d <- reactive({
      wm <- function(x, w) { ok <- !is.na(x) & !is.na(w) & w > 0; if (any(ok)) sum(x[ok] * w[ok]) / sum(w[ok]) else NA_real_ }
      crops_for(modifyList(f(), list(crops = input$crop, crop_groups = character()))) |>
        group_by(sas_year) |>
        summarise(irr = wm(yield_irrigated_kg_ha, n_irrigated_yield), rain = wm(yield_rainfed_kg_ha, crop_area_ha),
                  n_irr = sum(n_irrigated_yield, na.rm = TRUE), .groups = "drop") |> arrange(sas_year)
    })
    output$yarea <- renderPlotly({
      d <- yarea_d(); validate(need(nrow(d) > 0, tr("no_data")))
      d <- d |> mutate(irr = ifelse(n_irr >= 10, irr, NA))
      plot_ly(d, x = ~sas_year) |>
        add_bars(y = ~rain, name = tr("rainfed"), marker = list(color = col_rainfed),
                 text = ~paste0(sas_year, " \u00B7 ", tr("rainfed"), ": ", fmt_num(rain), " kg/ha"), hoverinfo = "text", textposition = "none") |>
        add_bars(data = filter(d, !is.na(irr)), y = ~irr, name = tr("irrigated"), marker = list(color = col_irrigated),
                 text = ~paste0(sas_year, " \u00B7 ", tr("irrigated"), ": ", fmt_num(irr), " kg/ha (n = ", fmt_num(n_irr), ")"),
                 hoverinfo = "text", textposition = "none") |>
        plotly_std(y = tr("y_yield"), dtick = 1) |> layout(barmode = "group", bargap = 0.3)
    })
    output$yarea_means <- renderUI({
      d <- yarea_d() |> filter(n_irr >= 10, !is.na(irr), !is.na(rain))
      if (!nrow(d)) return(span(tr("m_yarea_few", input$crop, f()$area)))
      span(tr("m_yarea", input$crop, f()$area, sum(d$irr > d$rain), nrow(d)))
    })
  })
}

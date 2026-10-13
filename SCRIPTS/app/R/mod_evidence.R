# ---- Page 5: Irrigation & Yield Evidence (observed and adjusted associations) ---
# Section 13: no causal claims. "Raw" = observed difference; "adjusted" = after
# controlling for inputs, crop area, district and season (survey-weighted log model).
mod_evidence_ui <- function(id, tr) {
  ns <- NS(id)
  tagList(
    filters_used(tr, c("seasons", "crop")),
    div(class = "callout", fontawesome::fa("scale-balanced"), " ", tr("evidence_caveat")),
    chart_card(tr("c_forest"), plotlyOutput(ns("forest"), height = "520px"), ns("forest_means"), tr("src_model_yield")),
    layout_columns(
      col_widths = c(4, 8),
      card(class = "chart-card", card_header(tr("choose_crop")),
           card_body(selectInput(ns("crop"), NULL, choices = D$yield$crops, selected = "Maize", width = "100%"),
                     uiOutput(ns("crop_box")))),
      chart_card(tr("c_dumbbell"), plotlyOutput(ns("dumb"), height = "300px"), ns("dumb_means"), tr("src_yield"))),
    layout_columns(
      col_widths = c(7, 5),
      chart_card(tr("c_yield_year"), plotlyOutput(ns("byyear"), height = "340px"), ns("byyear_means"), tr("src_yield")),
      chart_card(tr("c_ladder"), plotlyOutput(ns("ladder"), height = "340px"), ns("ladder_means"), tr("src_ladder"))))
}

mod_evidence_server <- function(id, f, tr) {
  moduleServer(id, function(input, output, session) {
    # follow the sidebar crop when it has enough irrigated plots
    observeEvent(f()$crop, if (f()$crop %in% D$yield$crops) updateSelectInput(session, "crop", selected = f()$crop))

    output$forest <- renderPlotly({
      d <- D$model_yield$table |> arrange(adjusted_pct) |> mutate(crop_name = factor(crop_name, levels = crop_name))
      dir_col <- ifelse(d$adjusted_low > 0, col_irrigated, ifelse(d$adjusted_high < 0, brand$terracotta, brand$grey))
      p <- plot_ly(d)
      for (cl in unique(dir_col)) p <- p |>
        add_segments(data = d[dir_col == cl, ], x = ~adjusted_low, xend = ~adjusted_high, y = ~crop_name, yend = ~crop_name,
                     line = list(color = cl, width = 3), hoverinfo = "skip", showlegend = FALSE)
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
      d <- d |> mutate(st = ifelse(grepl("C", season_type), tr("season_c"), tr("seasons_ab")),
                       col = ifelse(irrigation == "Irrigated", col_irrigated, col_rainfed))
      plot_ly(d, x = ~estimate, y = ~st, type = "scatter", mode = "markers", color = ~irrigation,
              colors = c(Irrigated = col_irrigated, `Rain-fed` = col_rainfed), marker = list(size = 14),
              error_x = list(type = "data", symmetric = FALSE, array = ~ci_high - estimate, arrayminus = ~estimate - ci_low),
              text = ~paste0(irrigation, " \u00B7 ", st, "<br>", fmt_num(estimate), " kg/ha (", fmt_num(ci_low), "\u2013",
                             fmt_num(ci_high), ")<br>n = ", fmt_num(n), " \u00B7 ", reliability), hoverinfo = "text") |>
        plotly_std(x = tr("y_yield")) |> layout(yaxis = list(title = ""))
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
      d <- D$yield$by_year |> filter(crop_name == input$crop); validate(need(nrow(d) > 0, tr("no_data")))
      p <- plot_ly()
      for (g in c("Rain-fed", "Irrigated")) {
        x <- d |> filter(irrigation == g); cl <- if (g == "Irrigated") col_irrigated else col_rainfed
        p <- p |> add_trace(data = x, x = ~sas_year, y = ~estimate, type = "scatter", mode = "lines+markers", name = g,
                            line = list(color = cl, width = 2), marker = list(color = cl, size = 8),
                            error_y = list(type = "data", symmetric = FALSE, array = ~ci_high - estimate,
                                           arrayminus = ~estimate - ci_low, color = cl, thickness = 1),
                            text = ~paste0(g, " ", sas_year, ": ", fmt_num(estimate), " kg/ha<br>n = ", fmt_num(n),
                                           " \u00B7 ", reliability), hoverinfo = "text")
      }
      plotly_std(p, y = tr("y_yield"), dtick = 1)
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
              error_y = list(type = "data", symmetric = FALSE, array = ~ci_high - estimate,
                             arrayminus = ~estimate - ci_low, color = brand$grey),
              text = ~paste0(modern_inputs_n, " ", tr("inputs"), ": ", fmt_num(estimate), " kg/ha<br>n = ", fmt_num(n),
                             " \u00B7 ", reliability), hoverinfo = "text", textposition = "none") |>
        plotly_std(x = tr("x_modern_inputs"), y = tr("y_yield"), legend = FALSE)
    })
    output$ladder_means <- renderUI({
      d <- D$yield$ladder |> filter(crop_name == input$crop, reliability != "Unreliable") |> arrange(modern_inputs_n)
      if (nrow(d) < 2) return(NULL)
      p(tr("m_ladder", input$crop, fmt_num(d$estimate[1]), fmt_num(tail(d$estimate, 1)), tail(d$modern_inputs_n, 1)))
    })
  })
}

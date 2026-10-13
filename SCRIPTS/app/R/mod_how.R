# ---- Page 6: How farmers irrigate (technology ladder, technique, water source, cost)
tech_dims <- c("irrig_tool_level", "irrig_technique", "irrig_source")

mod_how_ui <- function(id, tr) {
  ns <- NS(id)
  tagList(
    filters_used(tr, c("years", "seasons", "area")),
    div(class = "callout soft", fontawesome::fa("circle-info"), " ", tr("how_intro")),
    div(class = "how-dim", radioButtons(ns("dim"), NULL, inline = TRUE, choices = setNames(tech_dims, sapply(paste0("dim_", tech_dims), tr)))),
    layout_columns(
      col_widths = c(7, 5),
      chart_card(tr("c_mix_trend"), plotlyOutput(ns("mix"), height = "380px"), ns("mix_means"), tr("src_tech")),
      chart_card(tr("c_cost"), plotlyOutput(ns("cost"), height = "380px"), ns("cost_means"), tr("src_cost"))),
    chart_card(tr("c_sources_any"), plotlyOutput(ns("src"), height = "340px"), ns("src_means"), tr("src_tech"), icon = "water"),
    chart_card(tr("c_mix_district"), plotlyOutput(ns("dist"), height = "560px"), ns("dist_means"), tr("src_tech_district")))
}

mod_how_server <- function(id, f, tr) {
  moduleServer(id, function(input, output, session) {
    cat_cols <- function(cats) setNames(rep(c(series_cols, brand$grey, "#7FA88F", "#C2A06A"), length.out = length(cats)), cats)

    mix_d <- reactive({
      D$tech$mix |> filter(is.na(period), dimension == input$dim, sas_year %in% f()$years, sas_season %in% f()$seasons) |>
        mutate(ys = paste0(sas_year, sas_season))
    })
    output$mix <- renderPlotly({
      d <- mix_d(); validate(need(nrow(d) > 0, tr("no_data")))
      cats <- sort(unique(d$category))
      plot_ly(d, x = ~ys, y = ~share, color = ~factor(category, levels = cats), colors = cat_cols(cats), type = "bar",
              text = ~paste0(ys, " \u00B7 ", category, ": ", fmt_pct(share), "<br>", tr("irrigated_plots_n"), " ", fmt_num(n_group)),
              hoverinfo = "text", textposition = "none", marker = list(line = list(color = brand$canvas, width = 1))) |>
        plotly_std(y = tr("y_share_irrigated")) |>
        layout(barmode = "stack", xaxis = list(title = "", tickangle = -45, type = "category"), legend = list(y = -0.35))
    })
    output$mix_means <- renderUI({
      d <- mix_d() |> group_by(category) |> summarise(s = weighted.mean(share, n_group), .groups = "drop") |> arrange(desc(s))
      if (!nrow(d)) return(NULL)
      small <- mix_d() |> filter(n_group < 100) |> nrow()
      p(tr("m_mix", d$category[1], fmt_pct(d$s[1], 0)), if (small) tr("m_mix_small"))
    })

    output$cost <- renderPlotly({
      d <- D$tech$cost |> filter(irrig_tool_level != "Other")
      plot_ly(d, y = ~factor(irrig_tool_level, levels = rev(irrig_tool_level))) |>
        add_segments(x = ~p25 / 1000, xend = ~p75 / 1000, yend = ~factor(irrig_tool_level, levels = rev(irrig_tool_level)),
                     line = list(color = "#9DB8A9", width = 10), hoverinfo = "skip", showlegend = FALSE) |>
        add_markers(x = ~median / 1000, marker = list(color = col_irrigated, size = 13, symbol = "line-ns", line = list(width = 3, color = col_irrigated)),
                    text = ~paste0(irrig_tool_level, "<br>", tr("median"), ": ", fmt_num(median / 1000), "k RWF/ha<br>",
                                   tr("iqr"), ": ", fmt_num(p25 / 1000), "k\u2013", fmt_num(p75 / 1000), "k<br>n = ", fmt_num(n)),
                    hoverinfo = "text", showlegend = FALSE) |>
        plotly_std(x = tr("x_cost")) |> layout(yaxis = list(title = ""))
    })
    output$cost_means <- renderUI({
      d <- D$tech$cost |> filter(irrig_tool_level != "Other") |> arrange(median)
      p(tr("m_cost", d$irrig_tool_level[1], fmt_num(d$median[1] / 1000), fmt_num(max(d$median) / 1000)))
    })

    # every water source used on irrigated plots (multiple answers allowed)
    src_d <- reactive(D$tech$sources_any |> filter(sas_year %in% f()$years, sas_season %in% f()$seasons) |>
      group_by(source, sas_year) |> summarise(share = weighted.mean(share, n), n = sum(n), .groups = "drop"))
    output$src <- renderPlotly({
      d <- src_d(); validate(need(nrow(d) > 0, tr("no_data")))
      cats <- d |> group_by(source) |> summarise(s = mean(share)) |> arrange(desc(s)) |> pull(source)
      p <- plot_ly()
      cl <- setNames(rep(c(series_cols, brand$grey), length.out = length(cats)), cats)
      for (c in cats) { x <- d |> filter(source == c) |> arrange(sas_year)
        p <- p |> add_trace(data = x, x = ~sas_year, y = ~share, type = "scatter", mode = "lines+markers", name = c,
                            line = list(color = cl[[c]], width = 2.5), marker = list(color = cl[[c]], size = 8),
                            text = ~paste0(c, " ", sas_year, ": ", fmt_pct(share), " \u00B7 n = ", fmt_num(n)), hoverinfo = "text") }
      plotly_std(p, y = tr("y_share_irrigated"), dtick = 1)
    })
    output$src_means <- renderUI({
      d <- src_d() |> group_by(source) |> summarise(s = mean(share)) |> arrange(desc(s)); if (!nrow(d)) return(NULL)
      span(tr("m_sources", d$source[1], fmt_pct(d$s[1], 0), d$source[2], fmt_pct(d$s[2], 0)))
    })

    dist_d <- reactive({
      d <- D$tech$mix |> filter(period == "2023-2025", dimension == input$dim) |>
        left_join(D$lookup, by = c("district_std" = "district"))
      if (nzchar(f()$province)) d <- filter(d, province == f()$province)
      d
    })
    output$dist <- renderPlotly({
      d <- dist_d(); validate(need(nrow(d) > 0, tr("no_data")))
      cats <- sort(unique(d$category)); top <- cats[1]
      ord <- d |> filter(category == top) |> arrange(share) |> pull(district_std)
      ord <- c(setdiff(unique(d$district_std), ord), ord)
      plot_ly(d, y = ~factor(district_std, levels = ord), x = ~share, color = ~factor(category, levels = cats),
              colors = cat_cols(cats), type = "bar", orientation = "h",
              text = ~paste0(district_std, " \u00B7 ", category, ": ", fmt_pct(share), "<br>", tr("irrigated_plots_n"), " ",
                             fmt_num(n_group)), hoverinfo = "text", textposition = "none") |>
        plotly_std(x = tr("y_share_irrigated")) |>
        layout(barmode = "stack", yaxis = list(title = "", tickfont = list(size = 11)), legend = list(y = -0.12))
    })
    output$dist_means <- renderUI({
      d <- dist_d(); if (!nrow(d)) return(NULL)
      thin <- d |> distinct(district_std, n_group) |> filter(n_group < 30)
      p(tr("m_mix_district"), if (nrow(thin)) tr("m_thin", nrow(thin)))
    })
  })
}

# ---- Page 3: Need vs Adoption (rainfall risk and irrigation uptake) ----------
mod_need_ui <- function(id, tr) {
  ns <- NS(id)
  tagList(
    filters_used(tr, c("years", "seasons", "area")),
    div(class = "callout", fontawesome::fa("triangle-exclamation"), " ", tr("need_caveat")),
    layout_columns(
      col_widths = c(7, 5),
      chart_card(tr("c_quadrant"), plotlyOutput(ns("quad"), height = "380px"), ns("quad_means"), tr("src_need"), icon = "crosshairs"),
      chart_card(tr("c_anomaly_map"),
                 tagList(div(class = "card-tools", selectInput(ns("ys"), NULL, choices = NULL, width = "100%")),
                         plotlyOutput(ns("amap"), height = "328px")),
                 ns("amap_means"), tr("src_chirps"), icon = "temperature-half")),
    layout_columns(
      col_widths = c(7, 5),
      chart_card(tr("c_bubble"), plotlyOutput(ns("bubble"), height = "400px"), ns("bubble_means"), tr("src_need"), icon = "circle-play"),
      chart_card(tr("c_rain_trend"), plotlyOutput(ns("rtrend"), height = "400px"), ns("rtrend_means"), tr("src_chirps"), icon = "cloud-rain")))
}

mod_need_server <- function(id, f, tr, set_district) {
  moduleServer(id, function(input, output, session) {
    nd <- D$rain$district |> left_join(D$lookup, by = c("district_std" = "district"))

    # ---- quadrant
    output$quad <- renderPlotly({
      d <- nd |> mutate(sel = f()$area_level != "national" & district_std %in% f()$districts)
      qkey <- function(q) paste0("q_", gsub("[^a-z]", "", tolower(q)))
      qlev <- c("High need, low adoption", "High need, higher adoption", "Lower need, low adoption", "Lower need, higher adoption")
      qcols <- setNames(c(brand$terracotta, "#0F7044", "#B07A1C", "#1976B9"), tr(qkey(qlev)))
      d <- d |> mutate(quad_lab = factor(tr(qkey(quadrant)), levels = names(qcols)))
      mx <- median(d$need_score); my <- median(d$adoption_pct, na.rm = TRUE)
      plot_ly(d, x = ~need_score, y = ~adoption_pct, type = "scatter", mode = "markers+text", source = "need_click",
              customdata = ~district_std, color = ~quad_lab, colors = qcols,
              text = ~ifelse(quadrant == "High need, low adoption" | sel, district_std, ""), textposition = "top center", textfont = list(size = 10, color = brand$ink),
              marker = list(size = ~ifelse(sel, 16, 11), line = list(color = ~ifelse(sel, brand$ink, "#FFFFFF"), width = 1.5)),
              hovertext = ~paste0("<b>", district_std, "</b> (", province, ")<br>", tr("need_score"), ": ",
                                  fmt_num(need_score, 0), "/100<br>", tr("ind_irrigated"), ": ", fmt_pct(adoption_pct),
                                  " (", fmt_pct(adoption_low), "\u2013", fmt_pct(adoption_high), ")<br>",
                                  tr("normal_rain"), ": ", fmt_num(rain_normal_ab_mm), " mm \u00B7 CV ", fmt_num(rain_cv_pct, 0),
                                  "%<br>", tr(paste0("q_", gsub("[^a-z]", "", tolower(quadrant))))),
              hoverinfo = "text") |>
        plotly_std(x = tr("need_score"), y = tr("y_pct_plots_2325")) |> layout(yaxis = list(rangemode = "nonnegative")) |>
        layout(shapes = list(
          list(type = "line", x0 = mx, x1 = mx, y0 = 0, y1 = 1, yref = "paper", line = list(dash = "dot", color = brand$grey)),
          list(type = "line", y0 = my, y1 = my, x0 = 0, x1 = 1, xref = "paper", line = list(dash = "dot", color = brand$grey))),
          annotations = list(list(x = 1, y = 0, xref = "paper", yref = "paper", xanchor = "right", yanchor = "bottom",
                                  text = tr("q_hnla_label"), showarrow = FALSE,
                                  font = list(color = brand$terracotta, size = 12)))) |>
        event_register("plotly_click")
    })
    observeEvent(plotly_clicked(session, "need_click"), set_district(plotly_clicked(session, "need_click")))
    observeEvent(plotly_clicked(session, "bubble_click"), set_district(plotly_clicked(session, "bubble_click")))
    output$quad_means <- renderUI({
      h <- nd |> filter(quadrant == "High need, low adoption") |> arrange(desc(need_score))
      span(tr("m_quadrant", nrow(h), paste(h$district_std, collapse = ", ")))
    })

    # ---- animated bubbles: each district's irrigation (A+B) per year vs its need score
    output$bubble <- renderPlotly({
      d <- D$est |> filter(level == "district", indicator == "irrigated", sas_season %in% c("A", "B"), sas_year %in% f()$years,
                             area %in% f()$districts) |>
        group_by(district_std = area, sas_year) |> summarise(adoption = weighted.mean(estimate, wsum), n = sum(n), .groups = "drop") |>
        left_join(nd |> select(district_std, need_score, province), by = "district_std") |>
        left_join(D$totals |> filter(level == "district", sas_season %in% c("A", "B")) |>
                    group_by(district_std = area, sas_year) |> summarise(ha = sum(cultivated_area_ha, na.rm = TRUE), .groups = "drop"),
                  by = c("district_std", "sas_year")) |>
        filter(!is.na(need_score)) |> arrange(sas_year)
      validate(need(nrow(d) > 0, tr("no_data")))
      pc <- c(East = "#0F7044", Kigali = "#6A4C93", North = "#1976B9", South = "#B07A1C", West = "#B65F47")
      plot_ly(d, x = ~need_score, y = ~adoption, frame = ~sas_year, ids = ~district_std, color = ~province, colors = pc,
              size = ~ha, sizes = c(8, 45), type = "scatter", mode = "markers", source = "bubble_click", customdata = ~district_std,
              marker = list(opacity = 0.85, sizemode = "diameter"),
              text = ~paste0("<b>", district_std, "</b> (", province, ") \u00B7 ", sas_year, "<br>", tr("ind_irrigated"), ": ",
                             fmt_pct(adoption), "<br>", tr("need_score"), ": ", fmt_num(need_score, 0), "<br>",
                             tr("w_c_scale"), ": ", fmt_num(ha), " ha \u00B7 n = ", fmt_num(n)), hoverinfo = "text") |>
        plotly_std(x = tr("need_score"), y = tr("y_pct_plots_ab")) |>
        layout(yaxis = list(range = c(0, max(d$adoption, na.rm = TRUE) * 1.1)), xaxis = list(range = c(0, 100))) |>
        animation_opts(frame = 1200, transition = 700, redraw = FALSE) |>
        animation_slider(currentvalue = list(prefix = paste0(tr("year"), ": "), font = list(color = brand$green, size = 15))) |>
        animation_button(label = tr("play")) |> event_register("plotly_click") |>
        plotly_build() |> suppressWarnings()   # size-mapped markers warn about line.width; harmless
    })
    output$bubble_means <- renderUI(span(tr("m_bubble")))

    # ---- anomaly map
    observe({
      ys <- D$rain$rain |> filter(sas_year %in% f()$years, sas_season %in% f()$seasons) |>
        distinct(sas_year, sas_season) |> arrange(desc(sas_year), desc(sas_season)) |>
        mutate(k = paste0(sas_year, sas_season)) |> pull(k)
      updateSelectInput(session, "ys", choices = ys, selected = if (isolate(input$ys) %in% ys) isolate(input$ys) else ys[1])
    })
    amap_d <- reactive({
      req(input$ys)
      D$rain$rain |> filter(paste0(sas_year, sas_season) == input$ys) |>
        transmute(district = district_std, value = rain_anomaly_pct, rain_mm, rain_normal_mm,
                  hover = paste0("<b>", district, "</b><br>", fmt_num(rain_mm), " mm (", tr("normal"), " ",
                                 fmt_num(rain_normal_mm), " mm)<br>", tr("anomaly"), ": ",
                                 ifelse(value > 0, "+", ""), fmt_num(value, 0), "%"))
    })
    output$amap <- renderPlotly({
      d <- amap_d(); validate(need(nrow(d) > 0, tr("no_data")))
      lim <- max(abs(d$value), 30, na.rm = TRUE)
      choropleth(d, D$geo, "value", tr("anomaly_pct"), colorscale = div_rain, source = "anom_click",
                 zmin = -lim, zmax = lim, selected = if (f()$area_level != "national") f()$districts)
    })
    observeEvent(plotly_clicked(session, "anom_click"), set_district(plotly_clicked(session, "anom_click")))
    output$amap_means <- renderUI({
      d <- amap_d(); if (!nrow(d)) return(NULL)
      dry <- d |> filter(value < -15) |> arrange(value)
      p(if (nrow(dry)) tr("m_anom_dry", input$ys, nrow(dry), paste(head(dry$district, 5), collapse = ", "))
        else tr("m_anom_ok", input$ys, fmt_num(mean(d$value), 0)))
    })

    # ---- rainfall trend for the selected area
    rtrend_d <- reactive({
      r <- D$rain$rain |> left_join(D$lookup, by = c("district_std" = "district")) |>
        filter(sas_season %in% f()$seasons, sas_year >= 2000)
      r <- filter(r, district_std %in% f()$districts)
      r |> group_by(sas_year, sas_season) |>
        summarise(rain_mm = mean(rain_mm), normal = mean(rain_normal_mm), .groups = "drop")
    })
    output$rtrend <- renderPlotly({
      d <- rtrend_d(); validate(need(nrow(d) > 0, tr("no_data")))
      p <- plot_ly()
      for (s in intersect(c("A", "B", "C"), unique(d$sas_season))) {
        x <- d |> filter(sas_season == s)
        p <- p |>
          add_bars(data = x, x = ~sas_year, y = ~rain_mm, name = tr(paste0("season_", tolower(s))),
                   marker = list(color = ifelse(x$sas_year %in% f()$years, season_cols[[s]], paste0(season_cols[[s]], "55"))),
                   text = ~paste0(sas_year, s, ": ", fmt_num(rain_mm), " mm<br>", tr("normal"), " ", fmt_num(normal), " mm"),
                   hoverinfo = "text", textposition = "none") |>
          add_lines(data = x, x = ~sas_year, y = ~normal, line = list(color = season_cols[[s]], dash = "dash", width = 1.5, shape = "spline"),
                    name = paste(tr("normal"), s), hoverinfo = "skip", showlegend = FALSE)
      }
      plotly_std(p, y = tr("y_rain_mm")) |> layout(barmode = "group", bargap = 0.25)
    })
    output$rtrend_means <- renderUI({
      d <- rtrend_d() |> filter(sas_year %in% f()$years)
      if (!nrow(d)) return(NULL)
      below <- d |> filter(rain_mm < 0.85 * normal)
      p(tr("m_rain_trend", f()$area, nrow(below), nrow(d),
           if (nrow(below)) paste(paste0(below$sas_year, below$sas_season), collapse = ", ") else "\u2013"))
    })
  })
}

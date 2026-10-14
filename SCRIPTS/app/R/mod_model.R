# ---- Page 8: Adoption model - validation dashboard + simulator --------------
# Section 13: show validation (out-of-time, calibration, fairness) before any use.
mod_model_ui <- function(id, tr) {
  ns <- NS(id)
  L <- D$model$levels
  tagList(
    filters_used(tr, c("area")),
    div(class = "callout", fontawesome::fa("flask"), " ", tr("model_caveat", fmt_num(D$model$n_train), fmt_num(D$model$n_test))),
    uiOutput(ns("perf")),
    layout_columns(
      col_widths = c(6, 6),
      chart_card(tr("c_calibration"), plotlyOutput(ns("calib"), height = "300px"), ns("calib_means"), tr("src_model"), icon = "bullseye"),
      chart_card(tr("c_fairness"), plotlyOutput(ns("fair"), height = "300px"), ns("fair_means"), tr("src_model"), icon = "scale-balanced")),
    layout_columns(
      col_widths = c(5, 7),
      chart_card(tr("c_importance"), plotlyOutput(ns("imp"), height = "340px"), ns("imp_means"), tr("src_model"), icon = "list-ol"),
      chart_card(tr("c_odds"), plotlyOutput(ns("odds"), height = "340px"), ns("odds_means"), tr("src_model"), icon = "arrows-left-right")),
    layout_columns(
      col_widths = c(5, 7),
      card(class = "chart-card sim-card",
           card_header(span(class = "ch-icon", fontawesome::fa("sliders")), span(tr("c_simulator"))),
           card_body(
             layout_columns(col_widths = c(6, 6), fill = FALSE,
               selectInput(ns("s_district"), tr("district"), L$district, "Kirehe"),
               selectInput(ns("s_season"), tr("season"), setNames(L$season, c(tr("season_a"), tr("season_b")))),
               numericInput(ns("s_area"), tr("plot_area_ha"), 0.1, min = 0.005, max = 20, step = 0.05),
               sliderInput(ns("s_rain"), tr("rain_z"), -1.5, 2.5, 0, step = 0.25),
               selectInput(ns("s_erosion"), tr("dim_erosion"), L$erosion, "Moderate"),
               selectInput(ns("s_consolidated"), tr("dim_consolidated"), L$consolidated, "No"),
               selectInput(ns("s_inorganic"), tr("ind_inorganic_fert"), L$inorganic_fert, "No"),
               selectInput(ns("s_organic"), tr("ind_organic_fert"), L$organic_fert, "Yes"),
               selectInput(ns("s_gender"), tr("gender"), L$gender, "Female"),
               selectInput(ns("s_age"), tr("dim_age_band"), L$age_band, "35-54"),
               selectInput(ns("s_large"), tr("farm_type"), L$large_farm, "Small-scale")),
             uiOutput(ns("sim_out")))),
      chart_card(tr("c_potential"), plotlyOutput(ns("pot"), height = "470px"), ns("pot_means"), tr("src_model"), icon = "map")))
}

# Predict from the light glm copy (terms + xlevels + coefficients, no data)
predict_light <- function(m, newdata) {
  X <- model.matrix(m$terms, model.frame(m$terms, newdata, xlev = m$xlevels), contrasts.arg = m$contrasts)
  b <- m$coefficients; b[is.na(b)] <- 0
  plogis(drop(X[, names(b), drop = FALSE] %*% b))
}

mod_model_server <- function(id, f, tr) {
  moduleServer(id, function(input, output, session) {
    M <- D$model
    observeEvent(f()$districts, if (f()$area_level != "national" && f()$districts[1] %in% M$levels$district)
      updateSelectInput(session, "s_district", selected = f()$districts[1]))

    output$perf <- renderUI({
      g <- M$performance |> filter(grepl("Logistic", model)); r <- M$performance |> filter(grepl("forest", model))
      tile_row(
        stat_tile(tr("k_auc"), formatC(g$auc, format = "f", digits = 3), "bullseye", brand$green, NULL, TRUE, NULL,
                  tr("k_auc_sub", formatC(r$auc, format = "f", digits = 3)), num = g$auc, decimals = 3),
        stat_tile(tr("k_brier"), formatC(g$brier, format = "f", digits = 4), "chart-line", brand$blue, NULL, TRUE, NULL,
                  tr("k_brier_sub"), num = g$brier, decimals = 4),
        stat_tile(tr("k_obs_pred"), paste0(fmt_pct(g$observed_pct), " / ", fmt_pct(g$predicted_pct)), "scale-balanced", "#6A4C93",
                  NULL, TRUE, NULL, tr("k_obs_pred_sub")),
        stat_tile(tr("k_validation"), "2024\u20132025", "calendar-check", "#B07A1C", NULL, TRUE, NULL, tr("k_validation_sub")))
    })

    output$calib <- renderPlotly({
      d <- M$calibration; mx <- max(c(d$predicted_pct, d$observed_pct)) * 1.05
      plot_ly(d, x = ~predicted_pct, y = ~observed_pct, type = "scatter", mode = "lines+markers",
              line = list(color = col_irrigated), marker = list(size = ~sqrt(n) / 6 + 6, color = col_irrigated),
              text = ~paste0(tr("decile"), " ", bin, "<br>", tr("predicted"), ": ", fmt_pct(predicted_pct, 2), "<br>",
                             tr("observed"), ": ", fmt_pct(observed_pct, 2), "<br>n = ", fmt_num(n)), hoverinfo = "text",
              name = tr("model")) |>
        add_lines(x = c(0, mx), y = c(0, mx), line = list(dash = "dot", color = brand$grey), name = tr("perfect"),
                  hoverinfo = "skip", inherit = FALSE) |>
        plotly_std(x = tr("x_predicted"), y = tr("y_observed")) |> layout(legend = list(x = 0.02, y = 0.98, orientation = "v"))
    })
    output$calib_means <- renderUI({
      d <- M$calibration; top <- d |> slice_max(bin, n = 1)
      p(tr("m_calib", fmt_pct(top$predicted_pct), fmt_pct(top$observed_pct)))
    })

    output$fair <- renderPlotly({
      d <- M$fairness |> mutate(lbl = paste0(group, " (", dimension, ")"))
      plot_ly(d, x = ~lbl, y = ~auc, type = "bar", marker = list(color = ifelse(d$dimension == "Gender", "#B07A1C", "#1976B9")),
              text = ~paste0(lbl, "<br>AUC ", formatC(auc, format = "f", digits = 3), "<br>", tr("calib_gap"), ": ",
                             ifelse(calibration_gap_pts > 0, "+", ""), fmt_num(calibration_gap_pts, 2), " pts<br>n = ", fmt_num(n)),
              hoverinfo = "text", textposition = "none") |>
        plotly_std(y = "AUC", legend = FALSE) |> layout(yaxis = list(range = c(0.5, 1)), xaxis = list(title = ""), bargap = 0.35)
    })
    output$fair_means <- renderUI({
      d <- M$fairness
      p(tr("m_fair", formatC(min(d$auc), format = "f", digits = 2), formatC(max(d$auc), format = "f", digits = 2),
           d$group[which.max(abs(d$calibration_gap_pts))], fmt_num(max(abs(d$calibration_gap_pts)), 1)))
    })

    output$imp <- renderPlotly({
      d <- M$importance |> arrange(importance)
      plot_ly(d, y = ~factor(feature, levels = feature), x = ~importance, type = "bar", orientation = "h",
              marker = list(color = col_irrigated), text = ~paste0(feature, ": ", fmt_num(importance, 0)),
              hoverinfo = "text", textposition = "none") |>
        plotly_std(x = tr("x_importance"), legend = FALSE) |> layout(yaxis = list(title = ""), bargap = 0.35)
    })
    output$imp_means <- renderUI(p(tr("m_imp", M$importance$feature[1], M$importance$feature[2])))

    output$odds <- renderPlotly({
      d <- M$coefficients |> filter(term != "(Intercept)", !grepl("^district", term), is.finite(or_high)) |>
        arrange(odds_ratio)
      plot_ly(d, y = ~factor(term, levels = term)) |>
        add_segments(x = ~or_low, xend = ~or_high, yend = ~factor(term, levels = term),
                     line = list(color = "#C5D6CC", width = 2.5), hoverinfo = "skip", showlegend = FALSE) |>
        add_markers(x = ~odds_ratio, marker = list(size = 10, color = ifelse(d$or_low > 1, col_irrigated,
                                                                         ifelse(d$or_high < 1, brand$terracotta, brand$grey))),
                    text = ~paste0(term, "<br>OR ", fmt_num(odds_ratio, 2), " (", fmt_num(or_low, 2), "\u2013", fmt_num(or_high, 2), ")"),
                    hoverinfo = "text", showlegend = FALSE) |>
        plotly_std(x = tr("x_odds")) |>
        layout(xaxis = list(type = "log"), yaxis = list(title = "", tickfont = list(size = 11)),
               shapes = list(list(type = "line", x0 = 1, x1 = 1, y0 = 0, y1 = 1, yref = "paper", line = list(color = brand$ink))))
    })
    output$odds_means <- renderUI(p(tr("m_odds")))

    sim <- reactive({
      nd <- data.frame(district = input$s_district, season = input$s_season,
                       log_plot_area = log(min(max(input$s_area %||% 0.1, 0.005), 20)), rain_anomaly_z = input$s_rain,
                       erosion = input$s_erosion, consolidated = input$s_consolidated, inorganic_fert = input$s_inorganic,
                       organic_fert = input$s_organic, gender = input$s_gender, age_band = input$s_age,
                       large_farm = input$s_large)
      base <- predict_light(M$glm, nd)
      alt <- nd; alt$consolidated <- "Yes"; alt$inorganic_fert <- "Yes"
      list(p = base, p_alt = predict_light(M$glm, alt))
    })
    output$sim_out <- renderUI({
      s <- sim()
      div(class = "sim-result",
          div(class = "big-number", fmt_pct(100 * s$p)), p(class = "kpi-sub", tr("sim_prob")),
          p(tr("sim_alt", fmt_pct(100 * s$p_alt))), p(class = "source", tr("sim_caveat")))
    })

    output$pot <- renderPlotly({
      d <- M$potential |> transmute(district = district_std, value = gap_pts,
                                    hover = paste0("<b>", district, "</b><br>", tr("observed"), ": ", fmt_pct(observed_pct),
                                                   "<br>", tr("predicted"), ": ", fmt_pct(predicted_pct), "<br>", tr("gap"), ": ",
                                                   ifelse(value > 0, "+", ""), fmt_num(value, 1), " pts"))
      lim <- max(abs(d$value))
      choropleth(d, D$geo, "value", tr("gap_pts"), colorscale = list(c(0, "#1976B9"), c(0.5, "#F2F2EE"), c(1, "#B07A1C")),
                 source = "pot_map", zmin = -lim, zmax = lim, selected = if (f()$area_level != "national") f()$districts)
    })
    output$pot_means <- renderUI({
      d <- M$potential |> arrange(desc(gap_pts))
      p(tr("m_potential", paste(head(d$district_std, 4), collapse = ", ")))
    })
  })
}

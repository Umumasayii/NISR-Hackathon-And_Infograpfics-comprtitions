# ---- Page: Households (Agricultural Household Survey 2017, 2020, 2024) ----------
# Shares of farm households (not plots). The area filter applies; years, seasons and
# crops do not (the AHS has its own rounds). 2024 used a new questionnaire on the
# EICV7 sub-sample, so it is always drawn apart from 2017-2020, never joined.
ahs_years <- c(2017L, 2020L, 2024L)
ahs_year_cols <- c("2017" = "#1976B9", "2020" = "#0F7044", "2024" = "#B07A1C")
ahs_trend_inds <- c("irrigates", "irrig_modern", "irrig_motorised", "improved_seed", "inorganic_fert", "organic_fert",
                    "pesticide", "erosion_control", "extension_any", "coop_member", "twigire_muhinzi", "contract_farming")
ahs_practice_inds <- c("improved_seed", "inorganic_fert", "organic_fert", "pesticide", "erosion_control",
                       "agroforestry", "kitchen_garden")
ahs_enabler_themes <- list(
  services = c("extension_any", "extension_irrigation", "farmer_field_school", "twigire_muhinzi"),
  groups   = c("coop_member", "water_user_coop", "contract_farming"),
  finance  = c("bank_account", "savings", "loan_requested", "grant_received", "crop_insurance", "girinka_cow"),
  info     = c("has_telephone", "has_radio", "has_internet"))
ahs_theme_cols <- c(services = "#0F7044", groups = "#B07A1C", finance = "#1976B9", info = "#6A4C93")
ahs_map_inds <- c("irrigates", "improved_seed", "inorganic_fert", "extension_any", "coop_member")
ahs_eq_dims <- c("head_sex", "head_age_band", "head_education", "farm_size_band", "ubudehe")
ahs_eq_order <- c("Female", "Male", "Under 35", "35-54", "55+", "No formal education", "Primary", "Secondary / vocational",
                  "Tertiary", "< 0.25 ha", "0.25-0.5 ha", "0.5-1 ha", "> 1 ha", paste("Category", 1:4))

mod_households_ui <- function(id, tr) {
  ns <- NS(id)
  sel_box <- function(inputId, choices, selected = choices[1], width = "100%")
    selectizeInput(ns(inputId), NULL, choices = choices, selected = selected, width = width,
                   options = list(dropdownParent = "body"))
  tagList(
    section_title(tr("ahs_t"), tr("ahs_sub")),
    filters_used(tr, "area"),
    div(class = "ahs-note", fontawesome::fa("triangle-exclamation"),
        span(tr("ahs_break"), " ", tr("ahs_years_note"))),
    section_title(tr("ahs_s_findings"), tr("ahs_s_findings_sub")),
    uiOutput(ns("findings")),
    uiOutput(ns("tiles")),
    layout_columns(
      col_widths = c(6, 6),
      chart_card(tr("ac_trend"),
                 tagList(div(class = "card-tools", sel_box("trend_ind", setNames(ahs_trend_inds, tr(paste0("ai_", ahs_trend_inds))))),
                         plotlyOutput(ns("trend"), height = "300px")),
                 ns("trend_means"), tr("src_ahs"), icon = "people-roof"),
      chart_card(tr("ac_practices"), plotlyOutput(ns("practices"), height = "352px"), ns("practices_means"), tr("src_ahs"),
                 icon = "seedling")),
    layout_columns(
      col_widths = c(4, 4, 4),
      chart_card(tr("ac_enablers"), plotlyOutput(ns("enablers"), height = "372px"), ns("enablers_means"), tr("src_ahs"),
                 icon = "handshake"),
      chart_card(tr("ac_equity"),
                 tagList(div(class = "card-tools", sel_box("eq_dim", setNames(ahs_eq_dims, tr(paste0("eq_", ahs_eq_dims))))),
                         plotlyOutput(ns("equity"), height = "320px")),
                 ns("equity_means"), tr("src_ahs_nat"), icon = "people-group"),
      chart_card(tr("ac_mix"),
                 tagList(div(class = "card-tools", sel_box("mix_dim", setNames(c("technique", "water_source", "tool"),
                                                                              tr(c("mx_technique", "mx_water_source", "mx_tool"))))),
                         plotlyOutput(ns("mix"), height = "320px")),
                 ns("mix_means"), tr("src_ahs_nat"), icon = "faucet-drip")),
    layout_columns(
      col_widths = c(7, 5),
      chart_card(tr("ac_map"),
                 tagList(div(class = "card-tools d-flex gap-2",
                             sel_box("map_ind", setNames(ahs_map_inds, tr(paste0("ai_", ahs_map_inds)))),
                             sel_box("map_year", setNames(as.character(ahs_years), c("2017", "2020", tr("break_lbl"))),
                                     selected = "2020", width = "60%")),
                         plotlyOutput(ns("map"), height = "380px")),
                 ns("map_means"), tr("src_ahs"), icon = "map-location-dot"),
      chart_card(tr("ac_rank"), plotlyOutput(ns("rank"), height = "432px"), NULL, tr("src_ahs"),
                 icon = "arrow-down-wide-short")))
}

mod_households_server <- function(id, f, tr, set_district) {
  moduleServer(id, function(input, output, session) {
    # label from a translation key when one exists, else the raw value
    lab <- function(prefix, x) vapply(x, \(v) if (!is.null(i18n[[paste0(prefix, v)]])) tr(paste0(prefix, v)) else v,
                                      character(1), USE.NAMES = FALSE)
    yr_lab <- function(y) ifelse(y == 2024, "2024*", as.character(y))
    hover_ci <- function(d) paste0(fmt_pct(d$estimate), " (95% CI ", fmt_pct(d$ci_low), "–", fmt_pct(d$ci_high),
                                   ")<br>n = ", fmt_num(d$n), " · ", d$reliability,
                                   ifelse(d$year == 2024, paste0("<br><i>", tr("break_lbl"), "</i>"), ""))
    all_d <- reactive({ req(D$ahs); ahs_for(f(), unique(D$ahs$indicators$indicator)) })

    # ---- findings and tiles
    output$findings <- renderUI({
      d <- all_d(); if (!nrow(d)) return(div(class = "muted", tr("no_data")))
      v <- function(ind, yr) ahs_val(d, ind, yr)
      eq <- D$ahs$equity |> filter(dimension == "head_sex", year == 2024)
      fem <- eq$estimate[eq$group == "Female"]; mal <- eq$estimate[eq$group == "Male"]
      latest <- function(ind) { x <- d |> filter(indicator == ind) |> arrange(desc(year)); if (nrow(x)) x$estimate[1] else NA }
      div(class = "insight-grid",
        insight("droplet", tr("ah_f1_t", fmt_pct(v("irrigates", 2024), 0)),
                tr("ah_f1", f()$area, fmt_pct(v("irrigates", 2024)), fmt_pct(v("irrigates", 2017)), fmt_pct(v("irrigates", 2020))),
                brand$blue),
        insight("venus-mars", tr("ah_f2_t", fmt_num(mal - fem, 0)), tr("ah_f2", fmt_pct(fem), fmt_pct(mal)), "#B07A1C"),
        insight("seedling", tr("ah_f3_t"),
                tr("ah_f3", fmt_pct(v("improved_seed", 2024), 0), fmt_pct(v("inorganic_fert", 2024), 0),
                   fmt_pct(v("improved_seed", 2020), 0), fmt_pct(v("inorganic_fert", 2020), 0)), brand$green),
        insight("handshake", tr("ah_f4_t"),
                tr("ah_f4", fmt_pct(latest("water_user_coop")), fmt_pct(latest("crop_insurance")), fmt_pct(latest("coop_member"))),
                brand$terracotta))
    })

    output$tiles <- renderUI({
      d <- all_d(); if (!nrow(d)) return(NULL)
      tile <- function(ind, key, icon, col) {
        x <- d |> filter(indicator == ind) |> arrange(year); if (!nrow(x)) return(NULL)
        last <- tail(x, 1); prev <- x |> filter(year == 2020)
        stat_tile(tr(key), fmt_pct(last$estimate), icon, col, NULL, TRUE, NULL,
                  tagList(if (nrow(prev) && last$year != 2020) tr("ak_vs2020", yr_lab(last$year), fmt_pct(prev$estimate))
                          else tr("ak_round", last$year), " ", rel_badge(last$reliability, tr)),
                  num = last$estimate, suffix = "%", decimals = 1)
      }
      tile_row(tile("irrigates", "ak_irrig", "droplet", brand$blue),
               tile("improved_seed", "ak_seed", "seedling", brand$green),
               tile("inorganic_fert", "ak_fert", "flask", "#6A4C93"),
               tile("extension_any", "ak_ext", "chalkboard-user", "#B07A1C"))
    })

    # ---- trend: 2017-2020 joined, 2024 drawn apart
    trend_d <- reactive(all_d() |> filter(indicator == (input$trend_ind %||% "irrigates")) |> arrange(year))
    output$trend <- renderPlotly({
      d <- trend_d(); validate(need(nrow(d) > 0, tr("no_data")))
      old <- d |> filter(!series_break); new <- d |> filter(series_break)
      top <- max(d$estimate, 1) * 1.25
      p <- plot_ly()
      if (nrow(old)) p <- p |>
        add_trace(data = old, x = ~year, y = ~estimate, type = "scatter", mode = "lines+markers", name = "2017–2020",
                  line = list(color = col_irrigated, width = 3, shape = "spline", smoothing = 0.5),
                  marker = list(size = 11, color = col_irrigated, line = list(color = "#fff", width = 2)),
                  hovertext = hover_ci(old), hoverinfo = "text")
      if (nrow(new)) p <- p |>
        add_trace(data = new, x = ~year, y = ~estimate, type = "scatter", mode = "markers", name = tr("break_lbl"),
                  marker = list(size = 11, symbol = "diamond", color = ahs_year_cols[["2024"]], line = list(color = "#fff", width = 2)),
                  hovertext = hover_ci(new), hoverinfo = "text")
      plotly_std(p, y = if (d$population[1] == "Irrigating households") tr("y_pct_irr_hh") else tr("y_pct_hh")) |>
        layout(xaxis = list(tickvals = ahs_years, ticktext = c("2017", "2020", "2024*"), range = c(2016, 2025)),
               yaxis = list(range = c(0, top)),
               shapes = list(list(type = "line", x0 = 2022.2, x1 = 2022.2, y0 = 0, y1 = 1, yref = "paper",
                                  line = list(color = brand$grey, width = 1.5, dash = "dot"))),
               annotations = list(list(x = 2022.2, y = 1, yref = "paper", text = tr("break_short"), showarrow = FALSE,
                                       xanchor = "left", yanchor = "top", xshift = 4, font = list(size = 11, color = "#5E6A66")))) |>
        simple_lines()
    })
    output$trend_means <- renderUI({
      d <- trend_d(); if (!nrow(d)) return(NULL)
      v <- function(y) fmt_pct(ahs_val(d, d$indicator[1], y))
      span(tr("am_trend", tr(paste0("ai_", d$indicator[1])), v(2017), v(2020), v(2024)))
    })

    # ---- farm practices by round (grouped bars)
    prac_d <- reactive(all_d() |> filter(indicator %in% ahs_practice_inds))
    output$practices <- renderPlotly({
      d <- prac_d(); validate(need(nrow(d) > 0, tr("no_data")))
      ord <- d |> filter(year == max(year)) |> arrange(estimate) |> pull(indicator)
      ord <- c(setdiff(ahs_practice_inds, ord), ord)
      d <- d |> mutate(lbl = factor(lab("ai_", indicator), levels = lab("ai_", ord)), yl = yr_lab(year))
      p <- plot_ly()
      for (y in sort(unique(d$year))) {
        x <- d |> filter(year == y)
        p <- p |> add_trace(data = x, y = ~lbl, x = ~estimate, type = "bar", orientation = "h",
                            name = if (y == 2024) tr("break_lbl") else as.character(y),
                            marker = list(color = ahs_year_cols[[as.character(y)]], line = list(color = "#fff", width = 1)),
                            hovertext = paste0("<b>", x$lbl, "</b> · ", x$yl, "<br>", hover_ci(x)), hoverinfo = "text",
                            textposition = "none")
      }
      plotly_std(p) |>
        layout(barmode = "group", bargap = 0.22, yaxis = list(title = "", tickfont = list(size = 11)),
               xaxis = list(range = c(0, 100), ticksuffix = "%"), legend = list(y = -0.14, traceorder = "normal"))
    })
    output$practices_means <- renderUI({
      d <- prac_d(); if (!nrow(d)) return(NULL)
      ch <- d |> group_by(indicator) |> filter(n() >= 2) |> arrange(year) |>
        summarise(a = first(estimate), b = last(estimate), .groups = "drop") |> slice_max(b - a, n = 1)
      if (!nrow(ch)) return(NULL)
      span(tr("am_practices", tr(paste0("ai_", ch$indicator)), fmt_pct(ch$a, 0), fmt_pct(ch$b, 0)))
    })

    # ---- services, groups and finance: latest round for each indicator
    en_d <- reactive({
      th <- tibble::enframe(ahs_enabler_themes, "theme", "indicator") |> tidyr::unnest(indicator)
      all_d() |> inner_join(th, by = "indicator") |> group_by(indicator) |> slice_max(year, n = 1) |> ungroup() |>
        mutate(lbl = lab("ai_", indicator))
    })
    output$enablers <- renderPlotly({
      d <- en_d(); validate(need(nrow(d) > 0, tr("no_data")))
      d <- d |> arrange(estimate); lv <- d$lbl
      p <- plot_ly()
      for (t in names(ahs_enabler_themes)) {
        x <- d |> filter(theme == t); if (!nrow(x)) next
        p <- p |> add_trace(data = x, y = ~factor(lbl, levels = lv), x = ~estimate, type = "bar", orientation = "h",
                            name = tr(paste0("th_", t)),
                            marker = list(color = ahs_theme_cols[[t]], opacity = ifelse(x$reliability == "Unreliable", 0.45, 1)),
                            text = paste0(fmt_pct(x$estimate, 0), " · ", yr_lab(x$year)), textposition = "outside",
                            textfont = list(size = 10.5, color = brand$ink), cliponaxis = FALSE,
                            hovertext = paste0("<b>", x$lbl, "</b> · AHS ", yr_lab(x$year), "<br>", hover_ci(x)), hoverinfo = "text")
      }
      plotly_std(p) |>
        layout(barmode = "overlay", bargap = 0.28, yaxis = list(title = "", tickfont = list(size = 10.5)),
               xaxis = list(range = c(0, 118), ticksuffix = "%"), legend = list(y = -0.1, font = list(size = 10.5)))
    })
    output$enablers_means <- renderUI({
      d <- en_d() |> arrange(desc(estimate)); if (nrow(d) < 2) return(NULL)
      span(tr("am_enablers", d$lbl[1], fmt_pct(d$estimate[1], 0), tail(d$lbl, 1), fmt_pct(tail(d$estimate, 1))))
    })

    # ---- equity (national only)
    eq_d <- reactive(D$ahs$equity |> filter(dimension == (input$eq_dim %||% "head_sex")) |>
                       mutate(group = factor(group, levels = intersect(ahs_eq_order, unique(group)))) |> arrange(group))
    output$equity <- renderPlotly({
      d <- eq_d(); validate(need(nrow(d) > 0, tr("no_data")))
      d <- d |> mutate(ci_low = estimate - 1.96 * se, ci_high = estimate + 1.96 * se)
      lv <- levels(droplevels(d$group)); gl <- lab("grp_", lv)
      p <- plot_ly()
      for (y in sort(unique(d$year))) {
        x <- d |> filter(year == y)
        p <- p |> add_trace(data = x, x = factor(lab("grp_", as.character(x$group)), levels = gl), y = ~estimate, type = "bar",
                            name = if (y == 2024) tr("break_lbl") else as.character(y),
                            marker = list(color = ahs_year_cols[[as.character(y)]], opacity = ifelse(x$reliability == "Unreliable", 0.35, 1),
                                          line = list(color = "#fff", width = 1)),
                            hovertext = paste0("<b>", lab("grp_", as.character(x$group)), "</b> · ", yr_lab(x$year), "<br>", hover_ci(x)),
                            hoverinfo = "text", textposition = "none")
      }
      plotly_std(p, y = tr("y_pct_hh")) |>
        layout(barmode = "group", bargap = 0.25, xaxis = list(title = "", tickfont = list(size = 11)), legend = list(y = -0.18))
    })
    output$equity_means <- renderUI({
      d <- eq_d() |> filter(year == max(year), reliability != "Unreliable") |> arrange(desc(estimate)); if (nrow(d) < 2) return(NULL)
      span(tr("am_equity", yr_lab(d$year[1]), lab("grp_", as.character(d$group[1])), fmt_pct(d$estimate[1]),
              lab("grp_", as.character(tail(d$group, 1))), fmt_pct(tail(d$estimate, 1))))
    })

    # ---- irrigation mix (national, named answers only, re-scaled to 100%)
    mix_d <- reactive(D$ahs$irrigation_mix |> filter(dimension == (input$mix_dim %||% "technique")))
    output$mix <- renderPlotly({
      d <- mix_d(); validate(need(nrow(d) > 0, tr("no_data")))
      cats <- d |> group_by(category) |> summarise(s = mean(share)) |> arrange(desc(s)) |> pull(category)
      cols <- setNames(rep(c(series_cols, "#7FA88F", "#C2A06A"), length.out = length(cats)), cats)
      ys <- yr_lab(sort(unique(d$year)))
      p <- plot_ly()
      for (cc in cats) {
        x <- d |> filter(category == cc)
        p <- p |> add_trace(data = x, x = factor(yr_lab(x$year), levels = ys), y = ~share, type = "bar",
                            name = lab("mc_", cc), marker = list(color = cols[[cc]], line = list(color = "#fff", width = 1.5)),
                            hovertext = paste0("<b>", lab("mc_", cc), "</b> · ", yr_lab(x$year), "<br>", fmt_pct(x$share),
                                               " · n = ", fmt_num(x$n)), hoverinfo = "text",
                            textposition = "none")
      }
      plotly_std(p, y = tr("y_pct_irr_hh")) |>
        layout(barmode = "group", bargap = 0.3, xaxis = list(title = "", type = "category"),
               yaxis = list(ticksuffix = "%"), legend = list(y = -0.12, font = list(size = 10.5)))
    })
    output$mix_means <- renderUI({
      d <- mix_d() |> filter(year == max(year)) |> arrange(desc(share)); if (!nrow(d)) return(NULL)
      span(tr("am_mix", yr_lab(d$year[1]), lab("mc_", d$category[1]), fmt_pct(d$share[1], 0)))
    })

    # ---- district map and ranking
    map_d <- reactive({
      req(D$ahs)
      D$ahs$indicators |> filter(level == "district", indicator == (input$map_ind %||% "irrigates"),
                                 year == as.integer(input$map_year %||% "2020")) |>
        transmute(district = area, value = estimate, ci_low, ci_high, n, reliability, year)
    })
    sel_d <- reactive(if (f()$area_level != "national") f()$districts else character())
    output$map <- renderPlotly({
      d <- map_d(); validate(need(nrow(d) > 0, tr("no_data")))
      d$hover <- paste0("<b>", d$district, "</b> · AHS ", yr_lab(d$year), "<br>", tr(paste0("ai_", input$map_ind)), ": ",
                        fmt_pct(d$value), " (95% CI ", fmt_pct(d$ci_low), "–", fmt_pct(d$ci_high), ")<br>n = ",
                        fmt_num(d$n), " · ", d$reliability)
      choropleth(d, D$geo, "value", tr("y_pct_hh"), colorscale = seq_blue, source = "ahs_map", selected = sel_d())
    })
    observeEvent(plotly_clicked(session, "ahs_map"), set_district(plotly_clicked(session, "ahs_map")))
    output$map_means <- renderUI({
      d <- map_d() |> arrange(desc(value)); if (nrow(d) < 2) return(NULL)
      span(tr("am_map", yr_lab(d$year[1]), d$district[1], fmt_pct(d$value[1]), tail(d$district, 1), fmt_pct(tail(d$value, 1))))
    })
    output$rank <- renderPlotly({
      d <- map_d() |> arrange(value); validate(need(nrow(d) > 0, tr("no_data")))
      col <- ifelse(d$district %in% sel_d(), brand$amber, brand$blue)
      plot_ly(d, y = ~factor(district, levels = district), x = ~value, type = "bar", orientation = "h",
              marker = list(color = col, opacity = ifelse(d$reliability == "Unreliable", 0.45, 1)),
              hovertext = ~paste0("<b>", district, "</b>: ", fmt_pct(value), " (95% CI ", fmt_pct(ci_low), "–",
                                  fmt_pct(ci_high), ")<br>n = ", fmt_num(n), " · ", reliability),
              hoverinfo = "text", textposition = "none") |>
        plotly_std(x = tr("y_pct_hh"), legend = FALSE) |>
        layout(yaxis = list(title = "", tickfont = list(size = 10.5)), xaxis = list(ticksuffix = "%"), bargap = 0.25)
    })
  })
}

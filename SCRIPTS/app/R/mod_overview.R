# ---- Page 1: Overview (includes the former Home page) ------------------------
trend_inds <- c("irrigated", "irrig_modern", "irrig_any_farmer", "inorganic_fert", "organic_fert", "anti_erosion")

mod_overview_ui <- function(id, tr) {
  ns <- NS(id)
  tagList(
    div(class = "hero",
        div(class = "hero-text",
            span(class = "hero-kicker", fontawesome::fa("droplet"), " NISR Big Data Hackathon 2026 \u00B7 Track 1"),
            h1(tr("hero_title")), p(tr("hero_sub")),
            div(class = "hero-meta",
                span(fontawesome::fa("database"), " ", tr("hero_m1")), span(fontawesome::fa("calendar"), " ", tr("hero_m2")),
                span(fontawesome::fa("map"), " ", tr("hero_m3")), span(fontawesome::fa("cloud-rain"), " ", tr("hero_m4")),
                span(fontawesome::fa("people-roof"), " ", tr("hero_m5")))),
        div(class = "hero-steps",
            actionLink(ns("go_map"), tagList(fontawesome::fa("droplet"), tr("act_gap"))),
            actionLink(ns("go_evidence"), tagList(fontawesome::fa("seedling"), tr("act_payoff"))),
            actionLink(ns("go_priority"), tagList(fontawesome::fa("map-location-dot"), tr("act_action")))),
        div(class = "hero-hills")),
    filters_used(tr, c("years", "seasons", "area")),
    section_title(tr("s_numbers"), tr("s_numbers_sub")),
    uiOutput(ns("tiles")),
    section_title(tr("s_findings"), tr("s_findings_sub")),
    uiOutput(ns("findings")),
    layout_columns(
      col_widths = c(6, 6),
      chart_card(tr("c_trend"),
                 tagList(div(class = "card-tools",
                             selectizeInput(ns("trend_ind"), NULL, width = "100%",
                                            choices = setNames(trend_inds, tr(paste0("ind_", trend_inds))),
                                            options = list(dropdownParent = "body"))),
                         plotlyOutput(ns("trend"), height = "300px")),
                 ns("trend_means"), tr("src_sas_ci"), icon = "chart-line"),
      chart_card(tr("c_inputs"), plotlyOutput(ns("inputs"), height = "352px"), ns("inputs_means"), tr("src_sas_ci"),
                 icon = "flask")),
    layout_columns(
      col_widths = c(4, 4, 4),
      chart_card(tr("c_province"), plotlyOutput(ns("prov"), height = "290px"), ns("prov_means"), tr("src_sas_ci"),
                 icon = "layer-group"),
      chart_card(tr("c_production"), plotlyOutput(ns("prod"), height = "290px"), ns("prod_means"), tr("src_sas_totals"),
                 icon = "wheat-awn"),
      chart_card(tr("c_season_c"), plotlyOutput(ns("seasonc"), height = "290px"), ns("seasonc_means"), tr("src_sas_ci"),
                 icon = "sun")))
}

mod_overview_server <- function(id, f, tr, goto = NULL) {
  moduleServer(id, function(input, output, session) {
    if (!is.null(goto)) {
      observeEvent(input$go_map, goto("map")); observeEvent(input$go_evidence, goto("evidence"))
      observeEvent(input$go_priority, goto("priority"))
    }
    # yearly series for an indicator (n-weighted mean of the chosen seasons)
    yearly <- function(ind, ff = f(), seasons = c("A", "B")) {
      s <- if (identical(seasons, "C")) "C" else intersect(ff$seasons, seasons) %||% seasons
      by_year(est_for(ff, ind, seasons = s))
    }

    output$findings <- renderUI({
      ab <- yearly("irrigated")
      eq <- D$equity$equity |> filter(dimension == "gender")
      cs <- D$equity$equity |> filter(dimension == "consolidated")
      top <- D$screen$table |> arrange(rank) |> head(3)
      ya <- D$model_yield$table |> filter(adjusted_low > 0) |> arrange(desc(adjusted_pct))
      if (nrow(ab) < 2) return(NULL)
      div(class = "insight-grid",
        insight("droplet", tr("f1_t", in100(tail(ab$estimate, 1), tr)),
                tr("f1", f()$area, tail(ab$sas_year, 1), fmt_pct(ab$estimate[1]), ab$sas_year[1]), brand$blue),
        insight("seedling", tr("f2_t", nrow(ya)), tr("f2", paste(head(ya$crop_name, 4), collapse = ", ")), brand$green),
        insight("venus-mars", tr("f3_t"), tr("f3", fmt_pct(eq$estimate[eq$group == "Female"]), fmt_pct(eq$estimate[eq$group == "Male"]),
                fmt_pct(cs$estimate[cs$group == "In consolidated site"])), "#B07A1C"),
        insight("ranking-star", tr("f4_t"), tr("f4", paste(top$district_std, collapse = ", ")), brand$terracotta),
        staple_insight(),
        insight("hand-holding-dollar", tr("f6_t"),
                tr("f6", in100(hv("improved_seed", 2024), tr), in100(hv("improved_seed", 2020), tr),
                   in100(hv("crop_insurance", 2024), tr)), "#6A4C93"))
    })
    # main food crops (maize, beans, Irish potato, rice, cassava, wheat, banana): harvest change in the selection
    staple_crops <- c("Maize", "Bush bean", "Climbing bean", "Small red bean", "Irish potato", "Paddy rice",
                      "Cassava", "Wheat", "Cooking banana", "Dessert banana", "Banana for beer")
    hv <- function(ind, yr) if (is.null(D$ahs)) NA else ahs_val(ahs_for(f(), ind), ind, yr)
    staple_insight <- function() {
      pc <- crops_for(modifyList(f(), list(seasons = intersect(f()$seasons, c("A", "B")) %||% c("A", "B"),
                                           crops = character(), crop_groups = character()))) |>
        filter(crop_name %in% staple_crops) |> group_by(sas_year) |>
        summarise(t = sum(production_t, na.rm = TRUE) / 1000, .groups = "drop") |> arrange(sas_year)
      if (nrow(pc) < 2) return(NULL)
      ch <- 100 * (tail(pc$t, 1) / pc$t[1] - 1)
      insight("wheat-awn", tr("f5_t", paste0(if (ch >= 0) "+" else "", fmt_num(ch), "%"), pc$sas_year[1]),
              tr("f5", fmt_num(pc$t[1]), pc$sas_year[1], fmt_num(tail(pc$t, 1)), tail(pc$sas_year, 1)), "#00897B")
    }

    output$tiles <- renderUI({
      irr <- yearly("irrigated"); mod <- yearly("irrig_modern"); anyf <- yearly("irrig_any_farmer")
      fert <- yearly("inorganic_fert")
      sc <- yearly("irrigated", seasons = "C")
      tot_all <- totals_for(f()) |> filter(sas_season != "C") |> group_by(sas_year) |>
        # areas: average per main season (seasons A and B farm the same land, so adding them double counts);
        # harvests: added up over the seasons
        summarise(ha = mean(irrigated_area_ha, na.rm = TRUE), t = sum(production_t, na.rm = TRUE),
                  cult = mean(cultivated_area_ha, na.rm = TRUE), .groups = "drop") |> arrange(sas_year)
      # NISR does not publish the area of plots that report irrigation: that tile stays on the survey years
      tot <- tot_all |> filter(is.finite(ha))
      pub_t <- totals_for(f()) |> filter(sas_season != "C", sas_year %in% PUB_YEARS)
      ya <- D$model_yield$table |> filter(crop_name == "Maize")
      lst <- function(d, v = "estimate") if (nrow(d)) tail(d[[v]], 1) else NA
      latest_pub <- function(d) nrow(d) > 0 && "source" %in% names(d) && tail(d$source, 1) == "nisr"
      # change since the first year: survey years only (a published season is not compared with them)
      dlt <- function(d, v = "estimate") {
        if (latest_pub(d)) return(NA)
        if (nrow(d) >= 2) tail(d[[v]], 1) - d[[v]][1] else NA
      }
      yr <- function(d) if (!nrow(d)) "" else if (latest_pub(d))
        tagList(span(class = "st-pub", fontawesome::fa("building-columns"), " ", tr("k_pub_line", tail(d$sas_year, 1), tail(d$seasons, 1))), " ")
        else paste0(tail(d$sas_year, 1), " \u00B7 ")
      since <- function(d) if (nrow(d)) tr("k_pts_since", d$sas_year[1]) else ""
      tagList(
        tile_row(
          stat_tile(tr("k_irrigated"), fmt_pct(lst(irr)), "droplet", brand$blue, dlt(irr), TRUE, irr$estimate,
                    tagList(yr(irr), since(irr), " ", rel_badge(lst(irr, "rel"), tr)), num = lst(irr), suffix = "%", decimals = 1),
          stat_tile(tr("k_area"), paste(fmt_num(lst(tot, "ha")), "ha"), "water", "#00897B", NULL, TRUE, tot$ha,
                    tagList(yr(tot), tr("k_area_sub2", fmt_pct(100 * lst(tot, "ha") / lst(tot, "cult")))),
                    num = round(lst(tot, "ha")), suffix = " ha"),
          stat_tile(tr("k_modern"), fmt_pct(lst(mod)), "gears", "#B07A1C", dlt(mod), TRUE, mod$estimate,
                    tagList(yr(mod), tr("k_modern_sub2"), " ", if (!latest_pub(mod)) rel_badge(lst(mod, "rel"), tr)),
                    num = lst(mod), suffix = "%", decimals = 1),
          stat_tile(tr("ind_irrig_any_farmer"), fmt_pct(lst(anyf)), "user-check", brand$green, dlt(anyf), TRUE, anyf$estimate,
                    tagList(yr(anyf), tr("k_any_sub")), num = lst(anyf), suffix = "%", decimals = 1)),
        tile_row(
          stat_tile(tr("ind_inorganic_fert"), fmt_pct(lst(fert)), "flask", "#6A4C93", dlt(fert), TRUE, fert$estimate,
                    tagList(yr(fert), tr("k_fert_sub")), num = lst(fert), suffix = "%", decimals = 1),
          stat_tile(tr("k_production"), paste(fmt_num(lst(tot_all, "t") / 1000), "kt"), "wheat-awn", "#B07A1C", NULL, TRUE, tot_all$t,
                    tagList(if (nrow(tot_all) && tail(tot_all$sas_year, 1) %in% pub_t$sas_year)
                              span(class = "st-pub", fontawesome::fa("building-columns"), " ", tr("k_pub_prod", tail(tot_all$sas_year, 1)))
                            else yr(tot_all), " ", tr("k_production_sub")),
                    num = round(lst(tot_all, "t") / 1000), suffix = " kt"),
          stat_tile(tr("k_season_c"), fmt_pct(lst(sc)), "sun", brand$terracotta, dlt(sc), TRUE, sc$estimate,
                    tagList(yr(sc), tr("k_season_c_sub")), num = lst(sc), suffix = "%", decimals = 1),
          stat_tile(tr("k_maize"), paste0("+", fmt_num(ya$adjusted_pct, 0), "%"), "seedling", brand$green, NULL, TRUE, NULL,
                    tr("k_maize_sub", fmt_num(ya$adjusted_low, 0), fmt_num(ya$adjusted_high, 0), fmt_num(ya$raw_pct, 0)),
                    num = round(ya$adjusted_pct), suffix = "%", prefix = "+")))
    })

    trend_d <- reactive(est_for(f(), input$trend_ind %||% "irrigated"))
    output$trend <- renderPlotly({
      e <- trend_d(); validate(need(nrow(e) > 0, tr("no_data")))
      p <- plot_ly()
      for (s in intersect(c("A", "B", "C"), unique(e$sas_season))) {
        d <- e |> filter(sas_season == s, source == "survey") |> arrange(sas_year)
        if (nrow(d)) p <- p |>
          add_trace(data = d, x = ~sas_year, y = ~estimate, type = "scatter", mode = "lines+markers",
                    name = tr(paste0("season_", tolower(s))),
                    line = list(color = season_cols[[s]], width = 3, shape = "spline", smoothing = 0.5),
                    marker = list(size = 8, color = season_cols[[s]], line = list(color = "#fff", width = 2)),
                    text = ~paste0(sas_year, sas_season, ": <b>", fmt_pct(estimate), "</b> (95% CI ", fmt_pct(ci_low), "\u2013",
                                   fmt_pct(ci_high), ") \u00B7 n = ", fmt_num(n)),
                    hoverinfo = "text")
        # NISR published seasons: their own marker, not joined to the survey line
        pb <- e |> filter(sas_season == s, source == "nisr") |> arrange(sas_year)
        if (nrow(pb)) p <- p |>
          add_trace(data = pb, x = ~sas_year, y = ~estimate, type = "scatter", mode = "markers",
                    name = paste0(tr(paste0("season_", tolower(s))), " \u00B7 ", tr("pub_short")),
                    marker = list(size = 11, symbol = "diamond", color = season_cols[[s]], line = list(color = "#fff", width = 2)),
                    text = ~paste0(sas_year, sas_season, ": <b>", fmt_pct(estimate), "</b> \u00B7 ", tr("pub_hover")),
                    hoverinfo = "text")
      }
      plotly_std(p, y = tr(paste0("ind_", input$trend_ind %||% "irrigated")), dtick = 1) |> layout(hovermode = "x unified") |> simple_lines()
    })
    output$trend_means <- renderUI({
      e <- trend_d() |> filter(sas_season != "C", source == "survey") |> arrange(sas_year)
      if (nrow(e) < 2) return(NULL)
      a <- e |> slice(1); b <- e |> slice(n())
      sig <- b$ci_low > a$ci_high || b$ci_high < a$ci_low
      span(tr(if (!sig) "m_trend_stable" else if (b$estimate > a$estimate) "m_trend_up" else "m_trend_down",
              f()$area, season_label(a$sas_year, a$sas_season), fmt_pct(a$estimate),
              season_label(b$sas_year, b$sas_season), fmt_pct(b$estimate)))
    })

    inputs_d <- reactive({
      ind <- c("irrigated", "inorganic_fert", "organic_fert", "pesticide", "anti_erosion", "mechanised", "agroforestry", "land_consolidated")
      # one survey season set, so every bar has the same definition and year
      e <- est_for(f(), ind, seasons = intersect(f()$seasons, c("A", "B")) %||% "A") |> filter(source == "survey")
      if (!nrow(e)) return(e)
      ly <- max(e$sas_year)
      e |> filter(sas_year == ly) |> group_by(indicator) |>
        summarise(estimate = weighted.mean(estimate, wsum), ci_low = weighted.mean(ci_low, wsum), ci_high = weighted.mean(ci_high, wsum),
                  n = sum(n), year = ly, .groups = "drop") |>
        mutate(label = tr(paste0("ind_", indicator))) |> arrange(estimate)
    })
    output$inputs <- renderPlotly({
      d <- inputs_d(); validate(need(nrow(d) > 0, tr("no_data")))
      plot_ly(d, y = ~factor(label, levels = label), x = ~estimate, type = "bar", orientation = "h",
              marker = list(color = ifelse(d$indicator == "irrigated", brand$blue, "#3E8E63"),
                            line = list(width = 0)),
              hovertext = ~paste0("<b>", label, "</b><br>", fmt_pct(estimate), " (95% CI ", fmt_pct(ci_low), "\u2013", fmt_pct(ci_high), ")<br>n = ", fmt_num(n)),
              text = ~fmt_pct(estimate, 0), textposition = "outside", hoverinfo = "text",
              textfont = list(size = 12, color = brand$ink), cliponaxis = FALSE) |>
        plotly_std(x = tr("x_pct_plots"), legend = FALSE) |>
        layout(yaxis = list(title = "", ticksuffix = "  "), bargap = 0.4,
               xaxis = list(range = c(0, max(d$estimate, 1) * 1.18), ticksuffix = "%"))
    })
    output$inputs_means <- renderUI({
      d <- inputs_d(); if (!nrow(d)) return(NULL)
      hi <- d |> slice_max(estimate, n = 1); irr <- d |> filter(indicator == "irrigated")
      span(tr("m_inputs", d$year[1], hi$label, fmt_pct(hi$estimate), fmt_pct(irr$estimate)))
    })

    prov_d <- reactive({
      D$est |> filter(level == "province", indicator == "irrigated", sas_season %in% (intersect(f()$seasons, c("A", "B")) %||% "A"),
                      sas_year %in% f()$years, area %in% f()$provinces) |>
        mutate(period = if_else(sas_year >= 2023, "2023-2025", "2019-2022")) |>
        group_by(area, period) |> summarise(estimate = weighted.mean(estimate, wsum), n = sum(n), .groups = "drop")
    })
    output$prov <- renderPlotly({
      d <- prov_d(); validate(need(nrow(d) > 0, tr("no_data")))
      ord <- d |> filter(period == max(period)) |> arrange(estimate) |> pull(area)
      w <- d |> tidyr::pivot_wider(id_cols = area, names_from = period, values_from = estimate)
      p <- plot_ly()
      if (ncol(w) == 3) p <- p |> add_segments(data = w, x = w[[2]], xend = w[[3]], y = ~factor(area, levels = ord),
                                               yend = ~factor(area, levels = ord), line = list(color = "#D5DDD8", width = 5),
                                               hoverinfo = "skip", showlegend = FALSE)
      pc <- c("2019-2022" = "#A9C7B5", "2023-2025" = brand$blue)
      for (pp in names(pc)) { x <- d |> filter(period == pp); if (!nrow(x)) next
        p <- p |> add_markers(data = x, x = ~estimate, y = ~factor(area, levels = ord), name = pp,
                              marker = list(size = 14, color = pc[[pp]], line = list(color = "#fff", width = 2)),
                              text = ~paste0("<b>", area, "</b> ", pp, "<br>", fmt_pct(estimate), " \u00B7 n = ", fmt_num(n)), hoverinfo = "text") }
      plotly_std(p, x = tr("y_pct_plots_ab")) |> layout(yaxis = list(title = ""))
    })
    output$prov_means <- renderUI({
      d <- prov_d() |> filter(period == max(period)) |> arrange(desc(estimate)); if (!nrow(d)) return(NULL)
      span(tr("m_prov", d$area[1], fmt_pct(d$estimate[1]), tail(d$area, 1), fmt_pct(tail(d$estimate, 1))))
    })

    prod_d <- reactive({
      crops_for(f()) |> group_by(sas_year, crop_group) |>
        summarise(production_t = sum(production_t, na.rm = TRUE), .groups = "drop")
    })
    output$prod <- renderPlotly({
      d <- prod_d(); validate(need(nrow(d) > 0, tr("no_data")))
      grp <- d |> group_by(crop_group) |> summarise(t = sum(production_t)) |> arrange(desc(t)) |> pull(crop_group)
      top <- head(grp, 4)
      # the four largest groups only, as clustered bars (no "Other" bucket)
      d <- d |> filter(crop_group %in% top) |> mutate(crop_group = factor(crop_group, levels = top))
      cols <- setNames(series_cols[seq_along(top)], top)
      plot_ly(d, x = ~sas_year, y = ~production_t / 1000, color = ~crop_group, colors = cols, type = "bar",
              text = ~paste0("<b>", crop_group, "</b> \u00B7 ", sas_year, "<br>", fmt_num(production_t / 1000), " kt"),
              hoverinfo = "text", textposition = "none") |>
        plotly_std(dtick = 1) |>
        layout(barmode = "group", bargap = 0.22, yaxis = list(ticksuffix = " kt"),
               legend = list(orientation = "h", y = -0.18, font = list(size = 10.5), entrywidth = 0.5, entrywidthmode = "fraction"))
    })
    output$prod_means <- renderUI({
      d <- prod_d(); if (!nrow(d)) return(NULL)
      g <- d |> group_by(crop_group) |> summarise(t = sum(production_t)) |> mutate(s = 100 * t / sum(t)) |> slice_max(t, n = 1)
      span(tr("m_prod", g$crop_group, fmt_pct(g$s, 0)))
    })

    sc_d <- reactive(est_for(f(), "irrigated", seasons = "C") |> arrange(sas_year))
    output$seasonc <- renderPlotly({
      d <- sc_d(); validate(need(nrow(d) > 0, tr("no_data")))
      plot_ly(d, x = ~sas_year, y = ~estimate, type = "bar", marker = list(color = "#B07A1C"),
              hovertext = ~paste0("<b>", sas_year, "C</b><br>", fmt_pct(estimate), " (95% CI ", fmt_pct(ci_low), "\u2013", fmt_pct(ci_high),
                                  ")<br>n = ", fmt_num(n), " \u00B7 ", reliability),
              text = ~fmt_pct(estimate, 0), textposition = "outside", hoverinfo = "text",
              textfont = list(color = brand$ink, size = 12), cliponaxis = FALSE) |>
        plotly_std(y = tr("y_pct_plots"), legend = FALSE, dtick = 1) |>
        layout(bargap = 0.4, yaxis = list(range = c(0, max(d$estimate, 1) * 1.2)))
    })
    output$seasonc_means <- renderUI({
      d <- sc_d(); if (!nrow(d)) return(NULL)
      ab <- yearly("irrigated")
      span(tr("m_season_c", fmt_pct(min(d$estimate), 0), fmt_pct(max(d$estimate), 0),
              if (nrow(ab)) fmt_pct(mean(ab$estimate)) else "\u2013"))
    })
  })
}

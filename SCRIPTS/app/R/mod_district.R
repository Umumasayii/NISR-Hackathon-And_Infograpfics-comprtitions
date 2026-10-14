# ---- District report card: everything about one district on one page ---------
mod_district_ui <- function(id, tr) {
  ns <- NS(id)
  tagList(
    div(class = "district-bar",
        div(class = "db-pick", fontawesome::fa("location-dot"),
            selectInput(ns("d"), NULL, choices = sort(D$lookup$district), selected = "Kirehe", width = "240px")),
        uiOutput(ns("badges"), class = "db-badges")),
    uiOutput(ns("tiles")),
    layout_columns(
      col_widths = c(7, 5),
      chart_card(tr("c_d_trend"), plotlyOutput(ns("trend"), height = "300px"), ns("trend_means"), tr("src_sas_ci"), icon = "chart-line"),
      chart_card(tr("c_d_radar"), plotlyOutput(ns("radar"), height = "300px"), ns("radar_means"), tr("src_priority"), icon = "bullseye")),
    layout_columns(
      col_widths = c(6, 6),
      chart_card(tr("c_d_gap"), plotlyOutput(ns("gap"), height = "300px"), ns("gap_means"), tr("src_sas_ci"), icon = "scale-unbalanced"),
      chart_card(tr("c_d_crops"), plotlyOutput(ns("crops"), height = "300px"), ns("crops_means"), tr("src_table"), icon = "wheat-awn")),
    chart_card(tr("c_d_rain"), plotlyOutput(ns("rain"), height = "250px"), ns("rain_means"), tr("src_chirps"), icon = "cloud-rain"))
}

mod_district_server <- function(id, f, tr, set_district) {
  moduleServer(id, function(input, output, session) {
    # follow the sidebar: one district selected, or the first of several
    observeEvent(f()$districts, {
      if (f()$area_level != "national" && !isolate(input$d) %in% f()$districts)
        updateSelectInput(session, "d", selected = f()$districts[1])
    })
    dist <- reactive(input$d %||% "Kirehe")
    prov <- reactive(D$lookup$province[D$lookup$district == dist()])
    seas <- reactive(intersect(f()$seasons, c("A", "B")) %||% c("A", "B"))
    agg <- function(lv, ar, inds, years = f()$years) D$est |>
      filter(level == lv, area == ar, indicator %in% inds, sas_year %in% years, sas_season %in% seas()) |>
      group_by(indicator) |> summarise(v = weighted.mean(estimate, wsum), lo = weighted.mean(ci_low, wsum), hi = weighted.mean(ci_high, wsum),
                                       n = sum(n), rel = names(sort(table(reliability), decreasing = TRUE))[1], .groups = "drop")
    sc <- reactive(D$screen$table |> filter(district_std == dist()))
    nd <- reactive(D$rain$district |> filter(district_std == dist()))

    output$badges <- renderUI({
      s <- sc(); n <- nd()
      tagList(span(class = "pill", fontawesome::fa("map"), " ", prov()),
              if (nrow(s)) span(class = "pill strong", fontawesome::fa("ranking-star"), " ", tr("profile_rank", s$rank, s$stability)),
              if (nrow(n)) span(class = "pill warn", fontawesome::fa("cloud-sun-rain"), " ", tr(paste0("q_", gsub("[^a-z]", "", tolower(n$quadrant))))))
    })

    output$tiles <- renderUI({
      inds <- c("irrigated", "irrig_modern", "inorganic_fert", "anti_erosion")
      a <- agg("district", dist(), inds); r <- agg("national", "Rwanda", inds)
      g <- function(d, i, v = "v") { x <- d[[v]][d$indicator == i]; if (length(x)) x else NA }
      ser <- D$est |> filter(level == "district", area == dist(), indicator == "irrigated", sas_season %in% seas()) |>
        group_by(sas_year) |> summarise(e = weighted.mean(estimate, wsum), .groups = "drop") |> arrange(sas_year)
      tot <- D$totals |> filter(level == "district", area == dist(), sas_season %in% seas(), sas_year %in% f()$years) |>
        group_by(sas_year) |> summarise(t = sum(production_t, na.rm = TRUE), cult = sum(cultivated_area_ha, na.rm = TRUE), .groups = "drop")
      n <- nd()
      tile <- function(i, icon, col) stat_tile(tr(paste0("ind_", i)), fmt_pct(g(a, i)), icon, col, g(a, i) - g(r, i), TRUE,
        if (i == "irrigated") ser$e else NULL,
        tagList(tr("vs_rwanda", fmt_pct(g(r, i))), " ", rel_badge(g(a, i, "rel"), tr)), num = g(a, i), suffix = "%", decimals = 1)
      tagList(
        p(class = "muted small", fontawesome::fa("calendar"), " ",
          tr("d_period2", paste(range(f()$years), collapse = "\u2013"), paste(seas(), collapse = "+"))),
        tile_row(tile("irrigated", "droplet", brand$blue), tile("irrig_modern", "gears", "#B07A1C"),
                 tile("inorganic_fert", "flask", "#6A4C93"), tile("anti_erosion", "mountain", brand$green)),
        tile_row(
          stat_tile(tr("need_score"), fmt_num(n$need_score, 0), "temperature-arrow-up", brand$terracotta, NULL, TRUE, NULL,
                    tr("d_need_sub", fmt_num(n$rain_normal_ab_mm), n$dry_seasons_2016_2025), num = round(n$need_score), suffix = "/100"),
          stat_tile(tr("k_production"), paste(fmt_num(mean(tot$t) / 1000, 1), "kt"), "wheat-awn", "#B07A1C", NULL, TRUE, NULL,
                    tr("d_prod_sub"), num = round(mean(tot$t) / 1000, 1), suffix = " kt", decimals = 1),
          stat_tile(tr("w_c_scale"), paste(fmt_num(mean(tot$cult) / 1000, 1), "k ha"), "seedling", brand$green, NULL, TRUE, NULL,
                    tr("d_area_sub"), num = round(mean(tot$cult) / 1000, 1), suffix = "k ha", decimals = 1),
          stat_tile(tr("score"), fmt_num(sc()$score, 0), "ranking-star", brand$blue, NULL, TRUE, NULL,
                    tr("d_score_sub", sc()$rank, round(sc()$rank_p10), round(sc()$rank_p90)), num = round(sc()$score), suffix = "/100")))
    })

    trend_d <- reactive({
      ser <- function(lv, ar, nm) D$est |> filter(level == lv, area == ar, indicator == "irrigated", sas_season %in% seas(),
                                                 sas_year %in% f()$years) |>
        group_by(sas_year) |> summarise(e = weighted.mean(estimate, wsum), lo = weighted.mean(ci_low, wsum), hi = weighted.mean(ci_high, wsum),
                                        n = sum(n), .groups = "drop") |> mutate(who = nm)
      bind_rows(ser("district", dist(), dist()), ser("province", prov(), prov()), ser("national", "Rwanda", "Rwanda"))
    })
    output$trend <- renderPlotly({
      d <- trend_d(); validate(need(nrow(d) > 0, tr("no_data")))
      cols <- setNames(c(brand$blue, "#B07A1C", brand$grey), c(dist(), prov(), "Rwanda"))
      p <- plot_ly()
      for (w in names(cols)) { x <- d |> filter(who == w); if (!nrow(x)) next
        p <- p |> add_trace(data = x, x = ~sas_year, y = ~e, type = "scatter", mode = "lines+markers", name = w,
                            line = list(color = cols[[w]], width = if (w == dist()) 3 else 2, dash = if (w == "Rwanda") "dot" else "solid",
                                        shape = "spline", smoothing = 0.5),
                            marker = list(size = if (w == dist()) 9 else 6, color = cols[[w]]),
                            text = ~paste0(who, " ", sas_year, ": ", fmt_pct(e), " \u00B7 n = ", fmt_num(n)), hoverinfo = "text") }
      plotly_std(p, y = tr("y_pct_plots_ab"), dtick = 1) |> layout(hovermode = "x unified")
    })
    output$trend_means <- renderUI({
      d <- trend_d() |> filter(who == dist()) |> arrange(sas_year); if (nrow(d) < 2) return(NULL)
      r <- trend_d() |> filter(who == "Rwanda")
      above <- sum(d$e > r$e[match(d$sas_year, r$sas_year)], na.rm = TRUE)
      span(tr("m_d_trend", dist(), above, nrow(d), fmt_pct(tail(d$e, 1)), tail(d$sas_year, 1)))
    })

    output$radar <- renderPlotly({
      s <- sc(); validate(need(nrow(s) > 0, tr("no_data")))
      lab <- vapply(tr(paste0("w_", comp_names)), function(s) paste(strwrap(s, 16), collapse = "<br>"), "")
      med <- sapply(comp_names, \(cn) median(D$screen$table[[cn]], na.rm = TRUE))
      v <- 100 * unlist(s[comp_names])
      plot_ly(type = "scatterpolar", mode = "lines+markers") |>
        add_trace(r = c(100 * med, 100 * med[1]), theta = c(lab, lab[1]), name = tr("median_district"),
                  line = list(color = brand$grey, dash = "dot"), marker = list(color = brand$grey, size = 5), fill = "none",
                  hoverinfo = "text", text = paste0(c(lab, lab[1]), ": ", round(100 * c(med, med[1])))) |>
        add_trace(r = c(v, v[1]), theta = c(lab, lab[1]), name = dist(), fill = "toself", fillcolor = paste0(brand$blue, "33"),
                  line = list(color = brand$blue, width = 2.5), marker = list(color = brand$blue, size = 7),
                  hoverinfo = "text", text = paste0(c(lab, lab[1]), ": ", round(c(v, v[1])))) |>
        layout(polar = list(domain = list(x = c(0.12, 0.88), y = c(0.05, 0.95)), radialaxis = list(range = c(0, 100), gridcolor = "#E4EAE5", tickfont = list(size = 10)),
                            angularaxis = list(gridcolor = "#E4EAE5", tickfont = list(size = 10.5)), bgcolor = "rgba(0,0,0,0)"),
               font = list(family = FONT_BODY, color = brand$ink), paper_bgcolor = "rgba(0,0,0,0)",
               legend = list(orientation = "h", y = -0.1), margin = list(l = 20, r = 20, t = 30, b = 20)) |>
        config(displaylogo = FALSE)
    })
    output$radar_means <- renderUI({
      s <- sc(); if (!nrow(s)) return(NULL)
      v <- unlist(s[comp_names]); top <- names(which.max(v)); low <- names(which.min(v))
      span(tr("m_d_radar", dist(), tr(paste0("w_", top)), tr(paste0("w_", low))))
    })

    gap_d <- reactive({
      inds <- c("irrigated", "irrig_modern", "irrig_any_farmer", "inorganic_fert", "organic_fert", "pesticide", "anti_erosion",
                "land_consolidated", "agroforestry")
      a <- agg("district", dist(), inds); r <- agg("national", "Rwanda", inds) |> select(indicator, nat = v)
      a |> left_join(r, by = "indicator") |> mutate(label = tr(paste0("ind_", indicator)), gap = v - nat) |> arrange(gap)
    })
    output$gap <- renderPlotly({
      d <- gap_d(); validate(need(nrow(d) > 0, tr("no_data")))
      ord <- d$label
      plot_ly(d) |>
        add_segments(x = ~nat, xend = ~v, y = ~factor(label, levels = ord), yend = ~factor(label, levels = ord),
                     line = list(color = "#D5DDD8", width = 5), hoverinfo = "skip", showlegend = FALSE) |>
        add_markers(x = ~nat, y = ~factor(label, levels = ord), name = "Rwanda", marker = list(size = 11, color = brand$grey),
                    text = ~paste0(label, " \u00B7 Rwanda: ", fmt_pct(nat)), hoverinfo = "text") |>
        add_markers(x = ~v, y = ~factor(label, levels = ord), name = dist(),
                    marker = list(size = 13, color = ifelse(d$gap >= 0, brand$green, brand$terracotta), line = list(color = "#fff", width = 2)),
                    text = ~paste0("<b>", label, "</b> \u00B7 ", dist(), ": ", fmt_pct(v), " (", ifelse(gap >= 0, "+", ""), fmt_num(gap, 1),
                                   " pts)<br>n = ", fmt_num(n), " \u00B7 ", rel), hoverinfo = "text") |>
        plotly_std(x = tr("x_pct_plots")) |> layout(yaxis = list(title = ""))
    })
    output$gap_means <- renderUI({
      d <- gap_d(); if (!nrow(d)) return(NULL)
      span(tr("m_d_gap", dist(), tail(d$label, 1), fmt_num(tail(d$gap, 1), 1), d$label[1], fmt_num(d$gap[1], 1)))
    })

    crops_d <- reactive(D$crop_dist |> filter(district_std == dist(), sas_year %in% f()$years, sas_season %in% f()$seasons,
                                              !length(f()$crop_groups) | crop_group %in% f()$crop_groups,
                                              !length(f()$crops) | crop_name %in% f()$crops) |>
      group_by(crop_name, crop_group) |> summarise(t = sum(production_t, na.rm = TRUE) / n_distinct(sas_year),
                                                   irr = weighted.mean(yield_irrigated_kg_ha, n_irrigated_yield, na.rm = TRUE),
                                                   .groups = "drop") |> slice_max(t, n = 10) |> arrange(t))
    output$crops <- renderPlotly({
      d <- crops_d(); validate(need(nrow(d) > 0, tr("no_data")))
      grp <- sort(unique(D$crop$crop_group))
      cols <- setNames(rep(c(series_cols, brand$grey, "#7FA88F", "#C2A06A", "#7DA7CC"), length.out = length(grp)), grp)
      plot_ly(d, y = ~factor(crop_name, levels = crop_name), x = ~t / 1000, type = "bar", orientation = "h",
              color = ~crop_group, colors = cols,
              hovertext = ~paste0("<b>", crop_name, "</b> (", crop_group, ")<br>", fmt_num(t / 1000, 1), " kt ", tr("per_year")),
              hoverinfo = "text", text = ~paste(fmt_num(t / 1000, 1), "kt"), textposition = "outside",
              textfont = list(size = 11, color = brand$ink), cliponaxis = FALSE) |>
        plotly_std(x = tr("y_kt")) |> layout(yaxis = list(title = ""), legend = list(y = -0.25), bargap = 0.3,
                                             xaxis = list(range = c(0, max(d$t / 1000) * 1.25)))
    })
    output$crops_means <- renderUI({
      d <- crops_d() |> arrange(desc(t)); if (!nrow(d)) return(NULL)
      span(tr("m_d_crops", dist(), d$crop_name[1], fmt_num(d$t[1] / 1000, 1), paste(d$crop_name[2:min(3, nrow(d))], collapse = ", ")))
    })

    rain_d <- reactive(D$rain$rain |> filter(district_std == dist(), sas_year >= 2010, sas_season %in% seas()))
    output$rain <- renderPlotly({
      d <- rain_d(); validate(need(nrow(d) > 0, tr("no_data")))
      d <- d |> mutate(x = paste0(sas_year, sas_season), col = ifelse(rain_anomaly_pct < -15, brand$terracotta,
                                                                       ifelse(rain_anomaly_pct > 15, brand$blue, "#A9C7B5")),
                       col = ifelse(sas_year %in% f()$years, col, paste0(col, "55")))
      plot_ly(d, x = ~x, y = ~rain_anomaly_pct, type = "bar", marker = list(color = ~col),
              text = ~paste0("<b>", x, "</b><br>", fmt_num(rain_mm), " mm (", tr("normal"), " ", fmt_num(rain_normal_mm), ")<br>",
                             ifelse(rain_anomaly_pct > 0, "+", ""), fmt_num(rain_anomaly_pct, 0), "%"), hoverinfo = "text",
              textposition = "none") |>
        plotly_std(y = tr("anomaly_pct"), legend = FALSE) |>
        layout(xaxis = list(type = "category", tickangle = -60, tickfont = list(size = 10)), yaxis = list(rangemode = "normal"))
    })
    output$rain_means <- renderUI({
      d <- rain_d(); if (!nrow(d)) return(NULL)
      dry <- d |> filter(rain_anomaly_pct < -15)
      span(tr("m_d_rain", dist(), nrow(dry), nrow(d), if (nrow(dry)) paste(paste0(dry$sas_year, dry$sas_season), collapse = ", ") else "\u2013"))
    })
  })
}

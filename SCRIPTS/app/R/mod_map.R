# ---- Page 2: Irrigation map + District Profile side panel ---------------------
map_metrics <- c("irrigated", "irrig_modern", "irrig_any_farmer", "inorganic_fert", "anti_erosion",
                 "irrigated_area_ha", "production_t")

mod_map_ui <- function(id, tr) {
  ns <- NS(id)
  tagList(
    filters_used(tr, c("years", "seasons", "area")),
    layout_columns(
      col_widths = c(8, 4),
      chart_card(
        tr("c_map"),
        tagList(div(class = "d-flex gap-3 align-items-center flex-wrap",
                    selectInput(ns("metric"), NULL, width = "320px",
                                choices = setNames(map_metrics, sapply(paste0("ind_", map_metrics), tr))),
                    div(class = "form-switch-wrap", checkboxInput(ns("animate"), tagList(fontawesome::fa("play"), " ", tr("animate_years")), FALSE))),
                conditionalPanel("!input.animate", ns = ns, plotlyOutput(ns("map"), height = "470px")),
                conditionalPanel("input.animate", ns = ns, plotlyOutput(ns("map_anim"), height = "520px"))),
        ns("map_means"), tr("src_map"), icon = "map-location-dot"),
      card(class = "profile-card", card_header(fontawesome::fa("location-dot"), " ", tr("c_profile")),
           card_body(uiOutput(ns("profile"))))),
    chart_card(tr("c_ranking"), plotlyOutput(ns("rank"), height = "560px"), ns("rank_means"), tr("src_map"), icon = "arrow-down-wide-short"))
}

mod_map_server <- function(id, f, tr, set_district) {
  moduleServer(id, function(input, output, session) {
    # Average over the selected seasons, weighting each season by its sample
    dist_vals <- reactive({
      m <- input$metric; req(m)
      if (m %in% c("irrigated_area_ha", "production_t")) {
        D$totals |> filter(level == "district", sas_year %in% f()$years, sas_season %in% f()$seasons) |>
          group_by(district = area, sas_year) |> summarise(v = sum(.data[[m]], na.rm = TRUE), .groups = "drop") |>
          group_by(district) |> summarise(value = mean(v), n = NA_integer_, reliability = NA_character_, .groups = "drop")
      } else {
        D$est |> filter(level == "district", indicator == m, sas_year %in% f()$years, sas_season %in% f()$seasons) |>
          group_by(district = area) |>
          summarise(value = weighted.mean(estimate, n), n = sum(n),
                    reliability = names(sort(table(reliability), decreasing = TRUE))[1], .groups = "drop")
      }
    })
    is_total <- reactive(input$metric %in% c("irrigated_area_ha", "production_t"))
    unit <- reactive(if (input$metric == "production_t") " t" else if (input$metric == "irrigated_area_ha") " ha" else "%")

    output$map <- renderPlotly({
      d <- dist_vals(); validate(need(nrow(d) > 0, tr("no_data")))
      d$hover <- paste0("<b>", d$district, "</b><br>", tr(paste0("ind_", input$metric)), ": ",
                        fmt_num(d$value, if (is_total()) 0 else 1), unit(),
                        if (!is_total()) paste0("<br>n = ", fmt_num(d$n), " \u00B7 ", d$reliability) else "")
      choropleth(d, D$geo, "value", tr(paste0("unit_", if (is_total()) input$metric else "pct")),
                 colorscale = if (input$metric == "production_t") seq_amber else seq_green, source = "map_click")
    })
    observeEvent(plotly_clicked(session, "map_click"), set_district(plotly_clicked(session, "map_click")))
    observeEvent(plotly_clicked(session, "map_anim"), set_district(plotly_clicked(session, "map_anim")))
    # animated choropleth: one frame per year (selected seasons averaged)
    output$map_anim <- renderPlotly({
      m <- input$metric; req(m, isTRUE(input$animate))
      d <- if (is_total()) {
        D$totals |> filter(level == "district", sas_year %in% f()$years, sas_season %in% f()$seasons) |>
          group_by(district = area, sas_year) |> summarise(value = sum(.data[[m]], na.rm = TRUE), .groups = "drop")
      } else {
        D$est |> filter(level == "district", indicator == m, sas_year %in% f()$years, sas_season %in% f()$seasons) |>
          group_by(district = area, sas_year) |> summarise(value = weighted.mean(estimate, n), .groups = "drop")
      }
      validate(need(nrow(d) > 0, tr("no_data")))
      d <- d |> arrange(sas_year) |> mutate(hover = paste0("<b>", district, "</b> \u00B7 ", sas_year, "<br>",
                                                         fmt_num(value, if (is_total()) 0 else 1), unit()))
      plot_ly(d, type = "choropleth", geojson = D$geo, featureidkey = "properties.district", locations = ~district,
              z = ~value, frame = ~sas_year, zmin = 0, zmax = quantile(d$value, 0.97, na.rm = TRUE),
              colorscale = if (m == "production_t") seq_amber else seq_green, customdata = ~district,
              text = ~hover, hoverinfo = "text", marker = list(line = list(color = "#FFFFFF", width = 1)),
              colorbar = list(title = list(text = tr(paste0("unit_", if (is_total()) m else "pct"))), thickness = 12, len = 0.7),
              source = "map_anim") |>
        layout(geo = list(fitbounds = "locations", visible = FALSE, bgcolor = "rgba(0,0,0,0)"),
               margin = list(l = 0, r = 0, t = 0, b = 0), paper_bgcolor = "rgba(0,0,0,0)",
               font = list(family = FONT_BODY)) |>
        animation_opts(frame = 1100, transition = 500, redraw = TRUE) |>
        animation_slider(currentvalue = list(prefix = paste0(tr("year"), ": "), font = list(color = brand$green, size = 15))) |>
        animation_button(label = tr("play")) |>
        config(displaylogo = FALSE, topojsonURL = "") |> event_register("plotly_click")
    })

    output$map_means <- renderUI({
      d <- dist_vals() |> filter(!is.na(value)) |> arrange(desc(value))
      if (nrow(d) < 3) return(NULL)
      span(tr("m_map", tr(paste0("ind_", input$metric)), paste(head(d$district, 3), collapse = ", "),
           paste(rev(tail(d$district, 3)), collapse = ", ")), " ", tr("m_click"))
    })

    output$rank <- renderPlotly({
      d <- dist_vals() |> filter(!is.na(value)) |> arrange(value); validate(need(nrow(d) > 0, tr("no_data")))
      sel <- f()$district
      plot_ly(d, y = ~factor(district, levels = district), x = ~value, type = "bar", orientation = "h",
              marker = list(color = ifelse(d$district == sel, brand$amber, col_irrigated)),
              text = ~paste0(district, ": ", fmt_num(value, if (is_total()) 0 else 1), unit()),
              hoverinfo = "text", textposition = "none") |>
        plotly_std(x = tr(paste0("unit_", if (is_total()) input$metric else "pct")), legend = FALSE) |>
        layout(yaxis = list(title = "", tickfont = list(size = 11)))
    })
    output$rank_means <- renderUI(span(tr("m_rank")))

    output$profile <- renderUI({
      dist <- f()$district
      if (!nzchar(dist)) return(div(class = "profile-empty", fontawesome::fa("hand-pointer"), p(tr("profile_empty"))))
      inds <- c("irrigated", "irrig_modern", "inorganic_fert", "organic_fert", "anti_erosion", "mechanised")
      pick <- function(lv, ar) D$est |> filter(level == lv, area == ar, indicator %in% inds,
                                               sas_year %in% f()$years, sas_season %in% f()$seasons) |>
        group_by(indicator) |> summarise(v = weighted.mean(estimate, n), n = sum(n),
                                         rel = names(sort(table(reliability), decreasing = TRUE))[1], .groups = "drop")
      dd <- pick("district", dist); nn <- pick("national", "Rwanda") |> select(indicator, nat = v)
      rr <- D$rain$district |> filter(district_std == dist)
      sc <- D$screen$table |> filter(district_std == dist)
      tab <- dd |> left_join(nn, by = "indicator")
      tagList(
        h4(dist), p(class = "muted", D$lookup$province[D$lookup$district == dist], " \u00B7 ",
                    tr("profile_period", min(f()$years), max(f()$years), paste(f()$seasons, collapse = "+"))),
        tags$table(class = "profile-table",
          tags$thead(tags$tr(tags$th(""), tags$th(dist), tags$th("Rwanda"), tags$th("n"))),
          tags$tbody(lapply(seq_len(nrow(tab)), \(i) tags$tr(
            tags$td(tr(paste0("ind_", tab$indicator[i]))),
            tags$td(fmt_pct(tab$v[i]), " ", rel_badge(tab$rel[i], tr)),
            tags$td(class = "muted", fmt_pct(tab$nat[i])),
            tags$td(class = "muted", fmt_num(tab$n[i])))))),
        if (nrow(rr)) p(fontawesome::fa("cloud-rain"), " ",
                        tr("profile_rain", fmt_num(rr$rain_normal_ab_mm), fmt_num(rr$rain_cv_pct, 0), rr$dry_seasons_2016_2025)),
        if (nrow(sc)) p(fontawesome::fa("ranking-star"), " ", tr("profile_rank", sc$rank, sc$stability)),
        p(class = "source", tr("src_sas_ci")))
    })
  })
}

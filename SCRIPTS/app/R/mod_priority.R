# ---- Page 9: Priority screening (PRELIMINARY, adjustable weights) -----------
# Section 13: a screening aid, not an allocation rule. No RWF/tonnes what-if.
comp_names <- c("c_need", "c_gap", "c_scale", "c_equity", "c_readiness")

mod_priority_ui <- function(id, tr) {
  ns <- NS(id)
  w0 <- D$screen$default_weights
  tagList(
    filters_used(tr, c("area")),
    div(class = "callout warn", fontawesome::fa("triangle-exclamation"), " ", strong(tr("prelim_title")), " ", tr("prelim_text")),
    layout_columns(
      col_widths = c(3, 9),
      card(class = "chart-card", card_header(span(class = "ch-icon", fontawesome::fa("sliders")), span(tr("weights"))),
           card_body(
             lapply(seq_along(comp_names), \(i)
               sliderInput(ns(comp_names[i]), tr(paste0("w_", comp_names[i])), 0, 1, unname(w0[i]), step = 0.05)),
             actionButton(ns("reset_w"), tr("reset_weights"), class = "btn-sm btn-outline-secondary"),
             p(class = "source mt-2", tr("weights_help")))),
      layout_columns(col_widths = c(6, 6),
        chart_card(tr("c_priority_map"), plotlyOutput(ns("map"), height = "380px"), ns("map_means"), tr("src_priority"), icon = "map"),
        chart_card(tr("c_sensitivity"), plotlyOutput(ns("sens"), height = "380px"), ns("sens_means"), tr("src_sensitivity"),
                   icon = "arrows-up-down"))),
    card(class = "chart-card", full_screen = TRUE, card_header(span(class = "ch-icon", fontawesome::fa("table")), span(tr("c_priority_table"))),
         card_body(DT::DTOutput(ns("table"))), card_footer(div(class = "source", tr("src_priority")))))
}

mod_priority_server <- function(id, f, tr, set_district) {
  moduleServer(id, function(input, output, session) {
    S <- D$screen$table
    observeEvent(input$reset_w, for (i in seq_along(comp_names))
      updateSliderInput(session, comp_names[i], value = unname(D$screen$default_weights[i])))

    scored <- reactive({
      w <- sapply(comp_names, \(x) input[[x]] %||% 0)
      if (sum(w) == 0) w <- D$screen$default_weights
      S |> mutate(score_user = 100 * as.vector(as.matrix(S[comp_names]) %*% w) / sum(w),
                  rank_user = rank(-score_user, ties.method = "min")) |> arrange(rank_user)
    })

    output$map <- renderPlotly({
      d <- scored() |> transmute(district = district_std, value = score_user,
                                 hover = paste0("<b>", district, "</b> #", rank_user, "<br>", tr("score"), ": ", fmt_num(value, 0),
                                                "/100<br>", tr("stability"), ": ", stability))
      choropleth(d, D$geo, "value", tr("score"), colorscale = seq_green, source = "prio_map", zmin = 0, zmax = 100,
                 selected = if (f()$area_level != "national") f()$districts)
    })
    observeEvent(plotly_clicked(session, "prio_map"), set_district(plotly_clicked(session, "prio_map")))
    output$map_means <- renderUI({
      d <- scored(); top <- head(d, 5)
      moved <- sum(d$rank_user != d$rank)
      p(tr("m_priority", paste(top$district_std, collapse = ", ")), " ",
        if (moved) tr("m_priority_moved", moved) else tr("m_priority_default"))
    })

    output$sens <- renderPlotly({
      d <- scored()
      d <- (if (f()$area_level != "national") filter(d, district_std %in% f()$districts) else head(d, 15)) |>
        arrange(desc(rank_user))
      ord <- d$district_std
      scol <- c("Stable" = col_irrigated, "Moderately sensitive" = "#B07A1C", "Sensitive to weights" = brand$terracotta)
      plot_ly(d, y = ~factor(district_std, levels = ord), colors = scol) |>
        add_segments(x = ~rank_p10, xend = ~rank_p90, yend = ~factor(district_std, levels = ord),
                     line = list(color = "#C9D3CD", width = 8), hoverinfo = "skip", showlegend = FALSE) |>
        add_markers(x = ~rank_user, color = ~stability, marker = list(size = 12, line = list(color = "#fff", width = 1.5)),
                    text = ~paste0("<b>", district_std, "</b><br>", tr("your_rank"), ": ", rank_user, "<br>",
                                   tr("rank_range"), ": ", round(rank_p10), "\u2013", round(rank_p90), "<br>", tr("prob_top5"), ": ",
                                   fmt_pct(prob_top5_pct, 0)), hoverinfo = "text") |>
        plotly_std(x = tr("x_rank")) |>
        layout(xaxis = list(autorange = "reversed", dtick = 5), yaxis = list(title = "", tickfont = list(size = 11)))
    })
    output$sens_means <- renderUI({
      st <- S |> filter(stability == "Stable", rank <= 10)
      p(tr("m_sens", if (nrow(st)) paste(st$district_std, collapse = ", ") else "\u2013"))
    })

    output$table <- DT::renderDT({
      d <- scored() |> filter(district_std %in% f()$districts) |> left_join(D$lookup |> rename(prov = province), by = c("district_std" = "district")) |>
        transmute(`#` = rank_user, District = district_std, Province = prov, Score = round(score_user, 1),
                  Need = round(100 * c_need), Gap = round(100 * c_gap), Scale = round(100 * c_scale),
                  Equity = round(100 * c_equity), Readiness = round(100 * c_readiness),
                  `Adoption %` = round(adoption_pct, 1), Reliability = adoption_reliability,
                  `Rank p10-p90` = paste0(round(rank_p10), "\u2013", round(rank_p90)), `Top-5 %` = round(prob_top5_pct), Stability = stability)
      names(d)[2:14] <- c(tr("district"), tr("province"), tr("score"), tr("w_c_need"), tr("w_c_gap"), tr("w_c_scale"),
                          tr("w_c_equity"), tr("w_c_readiness"), tr("ind_irrigated"), tr("reliability"),
                          tr("rank_range"), tr("prob_top5"), tr("stability"))
      DT::datatable(d, rownames = FALSE, class = "compact stripe hover",
                    options = list(pageLength = 10, scrollX = TRUE, dom = "ftip")) |>
        DT::formatStyle(4, background = DT::styleColorBar(c(0, 100), "#CFE5D8"), backgroundSize = "95% 70%",
                        backgroundRepeat = "no-repeat", backgroundPosition = "center")
    })
  })
}

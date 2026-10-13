# ---- Page 7: Who is left behind (equity of irrigation access) -----------------
eq_dims <- c("gender", "age_band", "plot_size", "erosion", "consolidated")

mod_who_ui <- function(id, tr) {
  ns <- NS(id)
  tagList(
    filters_used(tr, c("years", "area", "gender")),
    layout_columns(
      col_widths = c(6, 6),
      chart_card(tr("c_equity"), plotlyOutput(ns("eq"), height = "520px"), ns("eq_means"), tr("src_equity")),
      chart_card(tr("c_gender_trend"), plotlyOutput(ns("gtrend"), height = "520px"), ns("gtrend_means"), tr("src_sas_ci"))),
    chart_card(tr("c_gender_district"), plotlyOutput(ns("gdist"), height = "620px"), ns("gdist_means"), tr("src_equity")))
}

mod_who_server <- function(id, f, tr) {
  moduleServer(id, function(input, output, session) {
    eq <- D$equity$equity |> filter(dimension %in% eq_dims) |>
      mutate(dimension = factor(dimension, levels = eq_dims),
             group_lbl = paste0(tr(paste0("dim_", dimension)), ": ", group)) |>
      arrange(dimension, estimate)

    output$eq <- renderPlotly({
      d <- eq |> mutate(hl = f()$gender != "" & dimension == "gender" & group == f()$gender)
      dcols <- setNames(c("#0F7044", "#1976B9", "#B07A1C", "#B65F47", "#6A4C93"), eq_dims)
      plot_ly(d, y = ~factor(group_lbl, levels = rev(group_lbl)), x = ~estimate, type = "bar", orientation = "h",
              marker = list(color = unname(dcols[as.character(d$dimension)]),
                            line = list(color = ifelse(d$hl, brand$ink, "rgba(0,0,0,0)"), width = 2)),
              error_x = list(type = "data", symmetric = FALSE, array = ~ci_high - estimate,
                             arrayminus = ~estimate - ci_low, color = brand$grey, thickness = 1),
              text = ~paste0(group_lbl, "<br>", fmt_pct(estimate), " (", fmt_pct(ci_low), "\u2013", fmt_pct(ci_high),
                             ")<br>n = ", fmt_num(n), " \u00B7 ", reliability), hoverinfo = "text", textposition = "none") |>
        plotly_std(x = tr("x_pct_plots"), legend = FALSE) |> layout(yaxis = list(title = "", tickfont = list(size = 11)))
    })
    output$eq_means <- renderUI({
      g <- eq |> filter(dimension == "gender"); fe <- g |> filter(group == "Female"); ma <- g |> filter(group == "Male")
      cs <- eq |> filter(dimension == "consolidated")
      p(tr("m_equity", fmt_pct(fe$estimate), fmt_pct(ma$estimate),
           fmt_pct(cs$estimate[cs$group == "In consolidated site"]), fmt_pct(cs$estimate[cs$group == "Not consolidated"])))
    })

    gt <- reactive(D$equity$equity |> filter(dimension == "gender_trend", sas_year %in% f()$years))
    output$gtrend <- renderPlotly({
      d <- gt(); validate(need(nrow(d) > 0, tr("no_data")))
      gc <- c(Female = "#B07A1C", Male = "#1976B9")
      p <- plot_ly()
      for (g in c("Female", "Male")) {
        x <- d |> filter(group == g)
        p <- p |>
          add_ribbons(data = x, x = ~sas_year, ymin = ~ci_low, ymax = ~ci_high, fillcolor = paste0(gc[[g]], "26"),
                      line = list(width = 0), hoverinfo = "skip", showlegend = FALSE) |>
          add_trace(data = x, x = ~sas_year, y = ~estimate, type = "scatter", mode = "lines+markers",
                    name = tr(tolower(g)), line = list(color = gc[[g]], width = if (f()$gender == g) 4 else 2),
                    marker = list(color = gc[[g]], size = 8),
                    text = ~paste0(tr(tolower(g)), " ", sas_year, ": ", fmt_pct(estimate), "<br>n = ", fmt_num(n)),
                    hoverinfo = "text")
      }
      plotly_std(p, y = tr("y_pct_plots_ab"), dtick = 1)
    })
    output$gtrend_means <- renderUI({
      d <- gt() |> select(sas_year, group, estimate) |> tidyr::pivot_wider(names_from = group, values_from = estimate)
      if (!nrow(d)) return(NULL)
      p(tr("m_gender_trend", sum(d$Male > d$Female, na.rm = TRUE), nrow(d)))
    })

    gd <- reactive({
      d <- D$equity$gender_district |> left_join(D$lookup, by = c("district_std" = "district"))
      if (nzchar(f()$province)) d <- filter(d, province == f()$province)
      d
    })
    output$gdist <- renderPlotly({
      d <- gd(); validate(need(nrow(d) > 0, tr("no_data")))
      w <- d |> select(district_std, gender, estimate) |> tidyr::pivot_wider(names_from = gender, values_from = estimate) |>
        arrange(Male)
      ord <- w$district_std
      plot_ly(colors = c(Female = "#B07A1C", Male = "#1976B9")) |>
        add_segments(data = w, x = ~Female, xend = ~Male, y = ~factor(district_std, levels = ord),
                     yend = ~factor(district_std, levels = ord), line = list(color = "#D5DBD7", width = 4),
                     hoverinfo = "skip", showlegend = FALSE) |>
        add_markers(data = d, x = ~estimate, y = ~factor(district_std, levels = ord), color = ~gender, marker = list(size = 11),
                    symbol = ~I(ifelse(reliability == "Unreliable", "circle-open", "circle")),
                    text = ~paste0(district_std, " \u00B7 ", gender, ": ", fmt_pct(estimate), "<br>n = ", fmt_num(n), " \u00B7 ", reliability),
                    hoverinfo = "text") |>
        plotly_std(x = tr("x_pct_plots_2325")) |> layout(yaxis = list(title = "", tickfont = list(size = 11)))
    })
    output$gdist_means <- renderUI({
      w <- gd() |> select(district_std, gender, estimate) |> tidyr::pivot_wider(names_from = gender, values_from = estimate) |>
        mutate(gap = Male - Female) |> arrange(desc(gap))
      if (!nrow(w)) return(NULL)
      p(tr("m_gender_district", sum(w$gap > 0, na.rm = TRUE), nrow(w), paste(head(w$district_std, 3), collapse = ", ")),
        " ", tr("m_open_unreliable"))
    })
  })
}

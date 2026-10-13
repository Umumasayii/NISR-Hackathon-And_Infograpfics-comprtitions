# ---- Brand, palette, translation and chart helpers ---------------------------
# Team NiyoIshimwe brand (Section 13). Data-mark colours are the brand hues
# nudged to pass the colour-blind validator on the canvas (#F7F9F6):
# lightness band, chroma, CVD separation and >= 3:1 contrast all PASS.
brand <- list(green = "#176B45", blue = "#1976B9", amber = "#D39A32", terracotta = "#B65F47",
              canvas = "#F7F9F6", ink = "#1B2C2A", grey = "#858F8A", white = "#FFFFFF")
series_cols <- c("#0F7044", "#B07A1C", "#1976B9", "#B65F47", "#6A4C93", "#00897B")  # fixed order
col_irrigated <- "#0F7044"; col_rainfed <- "#858F8A"
season_cols   <- c(A = "#0F7044", B = "#1976B9", C = "#B07A1C")
seq_green <- list(c(0, "#EAF4EE"), c(0.5, "#5FA97F"), c(1, "#0B4F30"))
seq_blue  <- list(c(0, "#E8F1F9"), c(0.5, "#5B9BD0"), c(1, "#0D4C80"))
seq_amber <- list(c(0, "#FBF3E4"), c(0.5, "#D9A44A"), c(1, "#7A5210"))
div_rain  <- list(c(0, "#8C5A2B"), c(0.5, "#ECEDE8"), c(1, "#1976B9"))   # dry - normal - wet
rel_cols  <- c("Good" = "#0F7044", "Use with caution" = "#B07A1C", "Unreliable" = "#B65F47")

FONT_BODY <- "'Plus Jakarta Sans', 'Segoe UI', sans-serif"
FONT_HEAD <- "'Sora', 'Segoe UI', sans-serif"

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || identical(a, "")) b else a

# ---- translation ---------------------------------------------------------------
i18n <- jsonlite::fromJSON("i18n/translations.json", simplifyVector = FALSE)
langs <- c(en = "English", rw = "Kinyarwanda", fr = "Fran\u00E7ais")
make_tr <- function(lang) function(key, ...) {
  if (length(key) > 1) return(vapply(key, \(k) make_tr(lang)(k, ...), character(1), USE.NAMES = FALSE))
  txt <- i18n[[key]][[lang]] %||% i18n[[key]][["en"]] %||% key
  if (length(list(...))) do.call(sprintf, c(list(txt), list(...))) else txt
}
get_lang <- function(query) { l <- shiny::parseQueryString(query %||% "")$lang %||% "en"; if (l %in% names(langs)) l else "en" }

# ---- number formatting -----------------------------------------------------------
fmt_num <- function(x, d = 0) ifelse(is.na(x), "\u2013", formatC(x, format = "f", digits = d, big.mark = ","))
fmt_pct <- function(x, d = 1) ifelse(is.na(x), "\u2013", paste0(formatC(x, format = "f", digits = d), "%"))

# ---- plotly standard -----------------------------------------------------------------
plotly_std <- function(p, x = NULL, y = NULL, legend = TRUE, ...) {
  p |>
    plotly::layout(
      font = list(family = FONT_BODY, size = 13, color = brand$ink),
      paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
      xaxis = list(title = list(text = x %||% "", font = list(size = 12, color = "#5E6A66")), gridcolor = "#EDF0EC",
                   zeroline = FALSE, linecolor = "#D5DDD8", tickfont = list(color = "#5E6A66"), ...),
      yaxis = list(title = list(text = y %||% "", font = list(size = 12, color = "#5E6A66")), gridcolor = "#EDF0EC",
                   zeroline = FALSE, rangemode = "tozero", tickfont = list(color = "#5E6A66")),
      transition = list(duration = 500, easing = "cubic-in-out"),
      legend = list(orientation = "h", y = -0.2, x = 0), showlegend = legend,
      hoverlabel = list(font = list(family = FONT_BODY, size = 13), bgcolor = "#FFFFFF", bordercolor = "#D5DDD8"),
      margin = list(l = 10, r = 10, t = 10, b = 10)) |>
    plotly::config(displaylogo = FALSE,
                   modeBarButtonsToRemove = c("lasso2d", "select2d", "autoScale2d", "toggleSpikelines",
                                              "hoverCompareCartesian", "hoverClosestCartesian"),
                   toImageButtonOptions = list(format = "png", filename = "smartirrigate_chart", scale = 2))
}

choropleth <- function(d, geojson, value, label, colorscale = seq_green, unit = "", source = "map",
                       zmin = NULL, zmax = NULL) {
  d <- d[!is.na(d[[value]]), ]
  plotly::plot_ly(source = source) |>
    plotly::add_trace(type = "choropleth", geojson = geojson, featureidkey = "properties.district",
                      locations = d$district, z = d[[value]], zmin = zmin, zmax = zmax,
                      colorscale = colorscale, customdata = d$district,
                      text = d$hover %||% paste0(d$district, "<br>", label, ": ", fmt_num(d[[value]], 1), unit),
                      hoverinfo = "text", marker = list(line = list(color = "#FFFFFF", width = 1)),
                      colorbar = list(title = list(text = label), thickness = 12, len = 0.7)) |>
    plotly::layout(geo = list(fitbounds = "locations", visible = FALSE, bgcolor = "rgba(0,0,0,0)"),
                   margin = list(l = 0, r = 0, t = 0, b = 0), paper_bgcolor = "rgba(0,0,0,0)") |>
    # base-map file served from www/ (empty: only district shapes are drawn), so
    # the map also works offline and never waits for cdn.plot.ly
    plotly::config(displaylogo = FALSE, topojsonURL = "") |>
    plotly::event_register("plotly_click")
}

# ---- cards -------------------------------------------------------------------------
# Every chart card: icon + title, chart, an insight line ("What this means") and a
# source/limitations line (Section 13)
chart_card <- function(title, output, means_id = NULL, source_txt = NULL, height = NULL, full = TRUE, icon = "chart-column") {
  bslib::card(
    full_screen = full, class = "chart-card",
    bslib::card_header(if (!is.null(icon)) shiny::span(class = "ch-icon", fontawesome::fa(icon)), shiny::span(title)),
    bslib::card_body(output, min_height = height),
    if (!is.null(means_id) || !is.null(source_txt)) bslib::card_footer(
      if (!is.null(means_id)) shiny::div(class = "means", fontawesome::fa("lightbulb"), shiny::uiOutput(means_id, inline = TRUE)),
      if (!is.null(source_txt)) shiny::div(class = "source", fontawesome::fa("circle-info"), " ", source_txt)))
}

# Tiny inline SVG trend line for stat tiles (no JS, crisp at any size)
sparkline_svg <- function(y, col = brand$green, w = 120, h = 34) {
  y <- y[!is.na(y)]; if (length(y) < 2) return(NULL)
  x <- seq(2, w - 2, length.out = length(y))
  r <- range(y); yy <- if (diff(r) == 0) rep(h / 2, length(y)) else h - 3 - (y - r[1]) / diff(r) * (h - 6)
  pts <- paste(sprintf("%.1f,%.1f", x, yy), collapse = " ")
  area <- paste0("2,", h, " ", pts, " ", w - 2, ",", h)
  shiny::HTML(sprintf('<svg class="spark" viewBox="0 0 %d %d" preserveAspectRatio="none" aria-hidden="true">
    <polygon points="%s" fill="%s" fill-opacity="0.12"/><polyline points="%s" fill="none" stroke="%s" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>
    <circle cx="%.1f" cy="%.1f" r="3" fill="%s"/></svg>', w, h, area, col, pts, col, tail(x, 1), tail(yy, 1), col))
}

# Stat tile: icon chip, label, animated number, change pill, sparkline, footnote
stat_tile <- function(label, value, icon_name, col = brand$green, delta = NULL, delta_good = TRUE,
                      spark = NULL, foot = NULL, num = NULL, suffix = "", decimals = 0) {
  dl <- if (!is.null(delta) && !is.na(delta)) {
    up <- delta >= 0
    cls <- if (xor(up, delta_good)) "delta bad" else "delta good"
    shiny::span(class = cls, fontawesome::fa(if (up) "arrow-trend-up" else "arrow-trend-down"),
                paste0(if (up) "+" else "", formatC(delta, format = "f", digits = 1)))
  }
  shiny::div(class = "stat-tile", style = paste0("--accent:", col),
    shiny::div(class = "st-top", shiny::span(class = "st-icon", fontawesome::fa(icon_name)),
               shiny::span(class = "st-label", label)),
    shiny::div(class = "st-mid",
      shiny::span(class = "st-value", `data-count` = num, `data-suffix` = suffix, `data-dec` = decimals, value), dl),
    if (!is.null(spark)) shiny::div(class = "st-spark", sparkline_svg(spark, col)),
    if (!is.null(foot)) shiny::div(class = "st-foot", foot))
}
tile_row <- function(...) shiny::div(class = "tile-row", ...)

# Insight card for the "Key findings" strips
insight <- function(icon_name, title, text, col = brand$green)
  shiny::div(class = "insight", style = paste0("--accent:", col),
             shiny::span(class = "in-icon", fontawesome::fa(icon_name)),
             shiny::div(shiny::div(class = "in-title", title), shiny::div(class = "in-text", text)))

# Section heading inside a page
section_title <- function(title, sub = NULL) shiny::div(class = "section-title", shiny::h3(title), if (!is.null(sub)) shiny::p(sub))

# Read a plotly click straight from the input (no event_data warnings before the
# chart has drawn). Returns the clicked customdata / location, or NULL.
plotly_clicked <- function(session, source) {
  v <- session$rootScope()$input[[paste0("plotly_click-", source)]]
  if (is.null(v)) return(NULL)
  d <- tryCatch(jsonlite::fromJSON(v), error = function(e) NULL)
  if (is.null(d)) return(NULL)
  as.character(d$customdata %||% d$location)[1]
}
rel_badge <- function(r, tr = NULL) {
  if (is.null(r) || is.na(r)) return(NULL)
  key <- c("Good" = "rb_good", "Use with caution" = "rb_caution", "Unreliable" = "rb_unreliable")[[r]]
  shiny::span(class = "rel-badge", style = paste0("border-color:", rel_cols[[r]], ";color:", rel_cols[[r]]),
              if (is.null(tr)) r else tr(key))
}
p <- shiny::p

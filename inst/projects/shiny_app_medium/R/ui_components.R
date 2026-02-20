# R/ui_components.R — reusable UI helper functions

#' Build the application sidebar
#'
#' Returns a `shiny::sidebarPanel` containing date-range, group-select,
#' and score-threshold inputs, plus the filter module UI.
#'
#' @param groups Character vector of group levels for the select input.
#' @return A `shiny.tag` sidebar panel.
#' @export
make_sidebar <- function(groups = character(0)) {
  shiny::sidebarPanel(
    width = 3L,
    make_title_bar("Filters"),
    shiny::dateRangeInput(
      "date_range",
      label = "Date range",
      start = Sys.Date() - 365L,
      end = Sys.Date()
    ),
    shiny::selectizeInput(
      "group_select",
      label = "Groups",
      choices = groups,
      multiple = TRUE,
      selected = groups
    ),
    shiny::sliderInput(
      "score_threshold",
      label = "Min score",
      min = 0L,
      max = 100L,
      value = 0L
    ),
    filterUI("filter_mod"),
    shiny::actionButton(
      "btn_reset",
      "Reset filters",
      class = "btn-sm btn-secondary"
    )
  )
}

#' Build the application main panel
#'
#' Returns a `shiny::mainPanel` with tabs for plots, a summary table,
#' KPI cards, and a data download section.
#'
#' @return A `shiny.tag` main panel.
#' @export
make_main_panel <- function() {
  shiny::mainPanel(
    width = 9L,
    shiny::tabsetPanel(
      id = "main_tabs",
      shiny::tabPanel(
        "Overview",
        shiny::fluidRow(
          shiny::uiOutput("kpi_cards")
        ),
        shiny::fluidRow(
          shiny::column(6L, shiny::plotOutput("hist_plot")),
          shiny::column(6L, shiny::plotOutput("scatter_plot"))
        )
      ),
      shiny::tabPanel(
        "Trends",
        shiny::plotOutput("time_series_plot", height = "400px")
      ),
      shiny::tabPanel(
        "Groups",
        shiny::plotOutput("boxplot", height = "400px")
      ),
      shiny::tabPanel(
        "Data",
        shiny::tableOutput("summary_table"),
        shiny::downloadButton("btn_download", "Download CSV")
      ),
      shiny::tabPanel("About", make_about_panel())
    )
  )
}

#' Build a styled title bar widget
#'
#' Returns a `shiny::tags$div` with the provided title text styled as a
#' section header.
#'
#' @param title Character(1). The header text.
#' @return A `shiny.tag`.
#' @export
make_title_bar <- function(title) {
  shiny::tags$div(
    class = "filter-header",
    shiny::tags$h5(title, style = "margin-top:0; font-weight:600;")
  )
}

#' Build the About panel content
#'
#' Returns a `shiny.tag` with application metadata: version, data source
#' notes, and contact information.
#'
#' @return A `shiny.tag` div.
#' @export
make_about_panel <- function() {
  shiny::tags$div(
    shiny::tags$h4("About this application"),
    shiny::tags$p(
      "Survey Dashboard v0.1.0 — rrlmgraph benchmark fixture."
    ),
    shiny::tags$p(
      "This application demonstrates reactive filtering, Shiny modules, ",
      "and ggplot2 visualisations across multiple tabs."
    ),
    shiny::tags$hr(),
    shiny::tags$p(shiny::tags$em("Data: synthetic survey data."))
  )
}

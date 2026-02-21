# Solution for task_026_rf_shiny
# Extract sidebar and main panel UI into helper functions in ui_components.R

#' Sidebar panel UI component
#' @return A \code{shiny::sidebarPanel} object.
#' @export
sidebar_ui <- function() {
  shiny::sidebarPanel(
    shiny::sliderInput("age_min", "Min Age", min = 18, max = 100, value = 18),
    shiny::sliderInput("age_max", "Max Age", min = 18, max = 100, value = 100),
    shiny::selectInput("category", "Category", choices = c("", "A", "B", "C")),
    shiny::actionButton("reset", "Reset Filters")
  )
}

#' Main panel UI component
#' @return A \code{shiny::mainPanel} object.
#' @export
main_panel_ui <- function() {
  shiny::mainPanel(
    shiny::plotOutput("score_hist"),
    shiny::tableOutput("summary_table"),
    shiny::downloadButton("download_data", "Download CSV")
  )
}

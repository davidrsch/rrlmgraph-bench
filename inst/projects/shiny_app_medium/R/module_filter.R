# R/module_filter.R — Shiny module for advanced filtering

#' UI function for the filter module
#'
#' Renders a collapsible "Advanced filters" section with an optional
#' keyword search input and an outlier-exclusion checkbox.
#'
#' @param id Character(1). The Shiny module namespace ID.
#' @return A `shiny.tag` containing the module UI elements.
#' @export
filterUI <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::tags$hr(),
    shiny::tags$strong("Advanced filters"),
    shiny::textInput(
      ns("keyword"),
      label = "Keyword search",
      placeholder = "Filter by ID..."
    ),
    shiny::checkboxInput(
      ns("exclude_outliers"),
      label = "Exclude outliers (> 3 SD)",
      value = FALSE
    )
  )
}

#' Server function for the filter module
#'
#' Applies keyword and outlier-exclusion filters to the reactive data
#' passed in via `data_r`.  Returns a reactive data frame.
#'
#' @param id     Character(1). The Shiny module namespace ID.
#' @param data_r A reactive expression that returns the base data frame.
#' @return A reactive expression returning the filtered data frame.
#' @export
filterServer <- function(id, data_r) {
  shiny::moduleServer(id, function(input, output, session) {
    choices_r <- shiny::reactive({
      get_filter_choices(data_r())
    })

    shiny::observe({
      shiny::updateSelectizeInput(
        session,
        "keyword",
        choices = choices_r()
      )
    })

    shiny::reactive({
      df <- data_r()
      kw <- input$keyword

      # Keyword filter
      if (!is.null(kw) && nzchar(kw)) {
        df <- df[grepl(kw, df$id, fixed = TRUE), , drop = FALSE]
      }

      # Outlier exclusion
      if (isTRUE(input$exclude_outliers) && nrow(df) > 3L) {
        mu <- mean(df$score, na.rm = TRUE)
        sig <- stats::sd(df$score, na.rm = TRUE)
        df <- df[abs(df$score - mu) <= 3 * sig, , drop = FALSE]
      }

      df
    })
  })
}

#' Get unique ID values for the filter keyword choices
#'
#' Extracts and sorts unique values of the `id` column for use as
#' auto-complete choices in the filter text input.
#'
#' @param df A data.frame with an `id` column.
#' @return A sorted character vector of unique IDs.
#' @export
get_filter_choices <- function(df) {
  sort(unique(as.character(df$id)))
}

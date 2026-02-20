# Solution for task_005_bd_shiny
# Fix filterServer() using updateSelectizeInput on a textInput widget.
#
# Key decision: replace shiny::updateSelectizeInput() with
# shiny::updateTextInput(), which is the correct update function for
# widgets created with shiny::textInput().

#' Server function for the filter module
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
      # FIX: use updateTextInput (not updateSelectizeInput) since
      # the 'keyword' input was created with shiny::textInput()
      shiny::updateTextInput(
        session,
        "keyword",
        value = choices_r()[1L]
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

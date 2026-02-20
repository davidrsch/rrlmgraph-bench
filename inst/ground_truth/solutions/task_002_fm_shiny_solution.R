# Solution for task_002_fm_shiny
# Extend update_filtered_data() with a score_max two-sided filter.
#
# Key decision: add score_max as an explicit parameter with default NULL
# rather than reading from input$score_max, so the function remains
# testable outside a Shiny session.

#' Apply sidebar filters to the base data frame
#'
#' @param df A pre-processed data frame from [preprocess_data()].
#' @param input Shiny input list with `date_range`, `group_select`,
#'   `score_threshold`, and optionally `score_max` elements.
#' @param score_max Numeric(1) or NULL. Upper bound for score filtering.
#' @return A filtered data.frame.
#' @export
update_filtered_data <- function(df, input, score_max = NULL) {
  # Date range
  if (!is.null(input$date_range)) {
    df <- df[
      df$date >= input$date_range[1L] &
        df$date <= input$date_range[2L],
      ,
      drop = FALSE
    ]
  }

  # Group selection
  if (length(input$group_select) > 0L) {
    df <- df[df$group %in% input$group_select, , drop = FALSE]
  }

  # Score lower threshold
  if (!is.null(input$score_threshold) && input$score_threshold > 0L) {
    df <- df[df$score >= input$score_threshold, , drop = FALSE]
  }

  # Score upper threshold (new)
  effective_max <- if (!is.null(score_max)) score_max else input$score_max
  if (!is.null(effective_max) && is.numeric(effective_max)) {
    df <- df[df$score <= effective_max, , drop = FALSE]
  }

  df
}

# Solution for task_011_rf_shiny
# Refactor update_filtered_data() by extracting three filter helpers.
#
# Key decision: each helper is a pure function of (df, value) with
# no reference to 'input', so they are independently unit-testable.

filter_by_date <- function(df, date_range) {
  if (is.null(date_range)) {
    return(df)
  }
  df[df$date >= date_range[1L] & df$date <= date_range[2L], , drop = FALSE]
}

filter_by_group <- function(df, group_select) {
  if (length(group_select) == 0L) {
    return(df)
  }
  df[df$group %in% group_select, , drop = FALSE]
}

filter_by_score <- function(df, score_threshold) {
  if (is.null(score_threshold) || score_threshold <= 0L) {
    return(df)
  }
  df[df$score >= score_threshold, , drop = FALSE]
}

#' Apply sidebar filters to the base data frame
#'
#' @param df    A pre-processed data frame from [preprocess_data()].
#' @param input Shiny input list.
#' @return A filtered data.frame.
#' @export
update_filtered_data <- function(df, input) {
  df <- filter_by_date(df, input$date_range)
  df <- filter_by_group(df, input$group_select)
  df <- filter_by_score(df, input$score_threshold)
  df
}

# Solution for task_014_doc_shiny
# Full Roxygen documentation for render_summary_table().
#
# Key decision: wrap @examples in \dontrun{} because the function
# calls compute_summary_stats() which expects validated survey data.

#' Render the summary statistics table
#'
#' Calls [compute_summary_stats()] on the supplied data frame and
#' formats the result for use with [shiny::renderTable()].  The
#' `mean_score` column is rounded to 2 decimal places.
#'
#' @param df A filtered data.frame, as returned by
#'   [update_filtered_data()] or [preprocess_data()].  Must contain
#'   at least columns `group` and `score`.
#'
#' @return A `data.frame` suitable for [shiny::renderTable()], with
#'   columns `group`, `n`, `mean_score`, `sd_score`, `min_score`,
#'   and `max_score`.
#'
#' @seealso [compute_summary_stats()] for the underlying aggregation;
#'   [preprocess_data()] for preparing the input data frame.
#'
#' @examples
#' \dontrun{
#' df <- data.frame(
#'   group = c("A", "A", "B", "B"),
#'   score = c(3.1, 4.2, 2.0, 5.5),
#'   stringsAsFactors = FALSE
#' )
#' render_summary_table(df)
#' }
#'
#' @export
render_summary_table <- function(df) {
  stats_df <- compute_summary_stats(df)
  stats_df$mean_score <- round(stats_df$mean_score, 2L)
  stats_df
}

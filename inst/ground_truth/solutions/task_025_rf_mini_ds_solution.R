# Solution for task_025_rf_mini_ds
# Extract duplicated load/validate logic into load_and_validate()

#' Load and validate a data CSV
#'
#' Thin wrapper that calls [load_data()], then checks that required columns
#' `id` and `score` are present, and returns the cleaned data frame.
#'
#' @param path Character(1). Path to a CSV file.
#' @param required_cols Character vector. Columns that must be present.
#' @return A cleaned `data.frame` (via [clean_data()]).
#' @export
load_and_validate <- function(path, required_cols = c("id", "score")) {
  df <- load_data(path)
  missing <- setdiff(required_cols, names(df))
  if (length(missing)) {
    stop(sprintf("Required columns missing from data: %s",
         paste(missing, collapse = ", ")))
  }
  clean_data(df)
}

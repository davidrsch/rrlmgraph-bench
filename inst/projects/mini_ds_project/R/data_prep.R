#' Load a data CSV into a data frame
#'
#' A thin wrapper around [utils::read.csv()] that adds sensible defaults and
#' checks for file existence.
#'
#' @param path Character(1). Path to a CSV file.
#' @return A `data.frame`.
#' @export
load_data <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("Data file not found: %s", path))
  }
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

#' Clean a raw data frame
#'
#' Removes rows with NA in key columns and standardises the `score` variable
#' by computing a z-score.  Uses `dplyr` for readable non-standard evaluation.
#'
#' @param df A `data.frame` with at least columns `id` and `score`.
#' @return A cleaned `data.frame` with an additional `score_z` column.
#' @importFrom dplyr filter mutate
#' @export
clean_data <- function(df) {
  df |>
    dplyr::filter(!is.na(score), !is.na(id)) |>
    dplyr::mutate(score_z = (score - mean(score)) / sd(score))
}

#' Split a data object into training and test sets
#'
#' @param df   A data object.
#' @param ratio Numeric(1) in (0, 1). Fraction allocated to training.
#' @param ...  Passed to methods.
#' @return A list with elements `train` and `test`.
#' @export
split_data <- function(df, ratio = 0.8, ...) {
  UseMethod("split_data")
}

#' @rdname split_data
#' @export
split_data.data.frame <- function(df, ratio = 0.8, ...) {
  n <- nrow(df)
  n_train <- floor(n * ratio)
  idx <- seq_len(n)
  list(
    train = df[idx[seq_len(n_train)], , drop = FALSE],
    test = df[idx[seq(n_train + 1L, n)], , drop = FALSE]
  )
}

# R/data.R — data loading and preparation helpers

#' Load survey data from a CSV file
#'
#' Reads the project's survey CSV and coerces column types.  Returns
#' a validated data frame ready for downstream processing.
#'
#' @param path Character(1). Path to the CSV file.
#' @return A data.frame.
#' @export
load_survey_data <- function(path) {
  if (!file.exists(path)) {
    stop(paste0("File not found: ", path))
  }
  df <- utils::read.csv(path, stringsAsFactors = FALSE)
  validate_data(df)
}

#' Validate the structure of a survey data frame
#'
#' Checks for required columns and reasonable row counts.
#' Stops with an informative error if validation fails.
#'
#' @param df data.frame returned by [load_survey_data()].
#' @return `df`, invisibly, after validation.
#' @export
validate_data <- function(df) {
  required <- c("id", "group", "score", "date")
  missing_cols <- setdiff(required, names(df))
  if (length(missing_cols) > 0L) {
    stop(paste0("Missing columns: ", paste(missing_cols, collapse = ", ")))
  }
  if (nrow(df) == 0L) {
    stop("Data frame has zero rows after loading.")
  }
  invisible(df)
}

#' Pre-process survey data for visualisation
#'
#' Converts the `date` column to `Date`, strips rows with `NA` scores,
#' and adds a `week` column for time-series aggregation.
#'
#' @param df A validated data frame from [validate_data()].
#' @return A data.frame with additional columns `date` (as `Date`) and
#'   `week`.
#' @export
preprocess_data <- function(df) {
  df$date <- as.Date(df$date)
  df <- df[!is.na(df$score), , drop = FALSE]
  df$week <- format(df$date, "%Y-W%V")
  df
}

#' Compute per-group summary statistics
#'
#' Returns a data frame with columns `group`, `n`, `mean_score`,
#' `sd_score`, `min_score`, and `max_score`.
#'
#' @param df A pre-processed data frame from [preprocess_data()].
#' @return A data.frame of summary statistics.
#' @export
compute_summary_stats <- function(df) {
  groups <- unique(df$group)
  rows <- lapply(groups, function(g) {
    sub_df <- df[df$group == g, , drop = FALSE]
    data.frame(
      group = g,
      n = nrow(sub_df),
      mean_score = mean(sub_df$score, na.rm = TRUE),
      sd_score = stats::sd(sub_df$score, na.rm = TRUE),
      min_score = min(sub_df$score, na.rm = TRUE),
      max_score = max(sub_df$score, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

#' Cache a processed data object for the session
#'
#' Stores the data frame in an environment keyed by `key`, returning
#' the previously cached value if `key` already exists and `refresh`
#' is `FALSE`.
#'
#' @param data A data.frame to cache.
#' @param key  Character(1). Cache key.
#' @param env  An `environment` used as the cache store.  Defaults to
#'   a package-level cache.
#' @param refresh Logical(1).  Force re-caching even if `key` is
#'   already present.  Default `FALSE`.
#' @return The cached data.frame.
#' @export
cache_data <- function(data, key, env = .data_cache, refresh = FALSE) {
  if (!refresh && exists(key, envir = env, inherits = FALSE)) {
    return(get(key, envir = env, inherits = FALSE))
  }
  assign(key, data, envir = env)
  data
}

# Package-level cache environment
.data_cache <- new.env(parent = emptyenv())

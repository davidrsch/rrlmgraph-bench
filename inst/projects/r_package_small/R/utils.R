# R/utils.R — internal metric computation utilities

#' Compute Root Mean Squared Error
#'
#' @param predicted Numeric vector of predicted values.
#' @param actual    Numeric vector of observed values.
#' @return Numeric(1) RMSE.
#' @keywords internal
compute_rmse_s4 <- function(predicted, actual) {
  sqrt(mean((predicted - actual)^2, na.rm = TRUE))
}

#' Compute Mean Absolute Error
#'
#' @param residuals Numeric vector of residuals (actual - predicted).
#' @return Numeric(1) MAE.
#' @keywords internal
compute_mae <- function(residuals) {
  mean(abs(residuals), na.rm = TRUE)
}

#' Compute R-squared
#'
#' @param residuals Numeric vector of residuals.
#' @param actuals   Numeric vector of observed values.
#' @return Numeric(1) R-squared in `[0, 1]`.
#' @keywords internal
compute_r_squared <- function(residuals, actuals) {
  ss_res <- sum(residuals^2, na.rm = TRUE)
  ss_tot <- sum((actuals - mean(actuals, na.rm = TRUE))^2, na.rm = TRUE)
  if (ss_tot == 0) {
    return(NA_real_)
  }
  1 - ss_res / ss_tot
}

#' Format a numeric metric for display
#'
#' Rounds to `digits` significant figures and returns a character string
#' with the metric name prefixed.
#'
#' @param name  Character(1). Metric label.
#' @param value Numeric(1). Metric value.
#' @param digits Integer(1). Significant figures.  Default `4L`.
#' @return Character(1).
#' @keywords internal
format_metric <- function(name, value, digits = 4L) {
  formatted <- if (is.na(value)) "NA" else signif(value, digits)
  paste0(name, " = ", formatted)
}

#' Check that a data frame has the required columns
#'
#' Stops with an informative error if any required column is missing.
#'
#' @param df       data.frame to check.
#' @param required Character vector of required column names.
#' @return `df`, invisibly.
#' @keywords internal
check_columns <- function(df, required) {
  missing <- setdiff(required, names(df))
  if (length(missing) > 0L) {
    stop("Missing required columns: ", paste(missing, collapse = ", "))
  }
  invisible(df)
}

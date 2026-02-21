# Solution for task_027_rf_rpkg
# Split utils.R into string_utils.R and math_utils.R

# ---- R/string_utils.R -----------------------------------------------
#' Format a formula as a character string
#' @export
format_formula_string <- function(formula) {
  paste(deparse(formula), collapse = " ")
}

#' Sanitise a column name for use in formulas
#' @export
sanitise_colname <- function(x) {
  make.names(x)
}

# ---- R/math_utils.R -------------------------------------------------
#' Compute Root Mean Squared Error
#' @export
compute_rmse <- function(predicted, actual) {
  sqrt(mean((predicted - actual)^2, na.rm = TRUE))
}

#' Scale numeric predictors in a data frame
#' @export
scale_predictors <- function(df, formula) {
  pred_cols <- all.vars(formula)[-1L]
  for (col in pred_cols) {
    if (is.numeric(df[[col]])) {
      df[[col]] <- as.numeric(scale(df[[col]]))
    }
  }
  df
}

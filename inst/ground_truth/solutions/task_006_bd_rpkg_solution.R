# Solution for task_006_bd_rpkg
# Fix scale_predictors() matrix-vs-vector bug.
#
# Key decision: wrap each scale() call in as.numeric() to drop
# the matrix class and dimnames attributes produced by base::scale().
# This ensures data frame columns remain atomic numeric vectors,
# which is required by stats::lm() and other downstream functions.

#' Scale numeric predictors in a data frame
#'
#' @param df      data.frame to scale.
#' @param formula A formula identifying the response variable.
#' @return A data.frame with scaled numeric predictors.
#' @export
scale_predictors <- function(df, formula) {
  response <- all.vars(formula)[1L]
  num_cols <- setdiff(
    names(df)[vapply(df, is.numeric, logical(1))],
    response
  )
  # FIX: wrap scale() in as.numeric() to drop matrix attributes
  df[num_cols] <- lapply(df[num_cols], function(x) as.numeric(scale(x)))
  df
}

# Solution for task_028_doc_mini_ds
# Roxygen documentation for compute_rmse()

#' Compute Root Mean Squared Error
#'
#' Calculates the RMSE between a vector of predicted values and the
#' corresponding vector of actual (observed) values.
#'
#' @param predicted Numeric vector of model-predicted values.
#' @param actual    Numeric vector of observed values; must be the same length
#'   as \code{predicted}.
#' @return A single non-negative numeric value representing the RMSE.
#' @examples
#' compute_rmse(c(1.0, 2.0, 3.0), c(1.1, 1.9, 3.2))
#' @export
compute_rmse <- function(predicted, actual) {
  sqrt(mean((predicted - actual)^2, na.rm = TRUE))
}

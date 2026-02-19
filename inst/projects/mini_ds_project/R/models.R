#' Fit a linear regression model
#'
#' A convenience wrapper around [stats::lm()] that stores the training-data
#' summary for downstream evaluation.
#'
#' @param train_data A `data.frame` to train on.
#' @param formula    A `formula` describing the model.
#' @return An object of class `c("lm_result", "lm")`.
#' @export
fit_model <- function(train_data, formula) {
  model <- stats::lm(formula = formula, data = train_data)
  class(model) <- c("lm_result", class(model))
  model
}

#' Evaluate a fitted model against a test set
#'
#' @param model     A fitted model object.
#' @param test_data A `data.frame` with the same variables used in training.
#' @param ...       Passed to methods.
#' @return A named list with `rmse` and `predictions`.
#' @export
evaluate_model <- function(model, test_data, ...) {
  UseMethod("evaluate_model")
}

#' @rdname evaluate_model
#' @export
evaluate_model.lm_result <- function(model, test_data, ...) {
  predicted <- stats::predict(model, newdata = test_data)
  actual <- test_data[[as.character(formula(model)[[2L]])]]
  list(
    rmse = compute_rmse(predicted, actual),
    predictions = predicted
  )
}

#' Compute Root Mean Squared Error
#'
#' @param predicted Numeric vector of predicted values.
#' @param actual    Numeric vector of observed values.
#' @return Numeric(1): RMSE.
#' @export
compute_rmse <- function(predicted, actual) {
  sqrt(mean((predicted - actual)^2))
}

# R/exported_fns.R — top-level user-facing functions

#' Fit a linear model and return a ModelResult
#'
#' Applies optional scaling, fits a model using the specified method
#' from `config`, and wraps the result in a [`ModelResult`][ModelResult-class].
#'
#' @param train  data.frame of training observations.
#' @param config A [`FitConfig`][FitConfig-class] object created by
#'   [new_fit_config()].
#' @return A [`ModelResult`][ModelResult-class] object.
#' @export
fit_model_s4 <- function(train, config) {
  check_columns(train, all.vars(config@formula))

  if (config@scale) {
    train <- scale_predictors(train, config@formula)
  }

  set.seed(config@seed)

  fitted_model <- switch(
    config@method,
    lm = stats::lm(config@formula, data = train),
    glm = stats::glm(config@formula, data = train),
    ridge = {
      if (!requireNamespace("MASS", quietly = TRUE)) {
        stop("MASS package required for ridge regression.")
      }
      MASS::lm.ridge(config@formula, data = train)
    }
  )

  preds <- as.numeric(stats::fitted(fitted_model))
  actuals <- train[[all.vars(config@formula)[1L]]]
  new_model_result(fitted_model, preds, actuals, call = match.call())
}

#' Perform k-fold cross-validation
#'
#' Splits `data` into `config@cv_folds` folds, fits via [fit_model_s4()]
#' on each training partition, evaluates on the held-out fold, and
#' returns the mean metrics across folds.
#'
#' @param data   A data.frame.
#' @param config A [`FitConfig`][FitConfig-class] object.
#' @return A named numeric vector of mean cross-validated metrics.
#' @export
cross_validate <- function(data, config) {
  set.seed(config@seed)
  n <- nrow(data)
  folds <- sample(rep_len(seq_len(config@cv_folds), n))
  metric_rows <- vector("list", config@cv_folds)

  for (k in seq_len(config@cv_folds)) {
    train_k <- data[folds != k, , drop = FALSE]
    test_k <- data[folds == k, , drop = FALSE]
    res_k <- fit_model_s4(train_k, config)
    metric_rows[[k]] <- evaluate(res_k, newdata = test_k)
  }

  metric_mat <- do.call(rbind, metric_rows)
  colMeans(metric_mat, na.rm = TRUE)
}

#' Scale numeric predictors in a data frame
#'
#' Standardises all numeric predictor columns (not the response) to
#' zero mean and unit variance using [base::scale()].
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
  df[num_cols] <- lapply(df[num_cols], scale)
  df
}

#' Compare multiple ModelResult objects
#'
#' Extracts the stored metrics from each `ModelResult` and returns
#' a data.frame with one row per model and one column per metric.
#'
#' @param ...   One or more [`ModelResult`][ModelResult-class] objects
#'   (or a list of them).
#' @param names Character vector of model labels.  Defaults to
#'   `"model_1"`, `"model_2"`, etc.
#' @return A data.frame of metrics.
#' @export
compare_models <- function(..., names = NULL) {
  models <- c(list(...))
  # Flatten if a single list was passed
  if (
    length(models) == 1L &&
      is.list(models[[1L]]) &&
      !methods::is(models[[1L]], "ModelResult")
  ) {
    models <- models[[1L]]
  }
  if (is.null(names)) {
    names <- paste0("model_", seq_along(models))
  }
  rows <- lapply(models, function(m) as.list(m@metrics))
  df <- do.call(rbind, lapply(rows, as.data.frame))
  df <- cbind(model = names, df, stringsAsFactors = FALSE)
  rownames(df) <- NULL
  df
}

#' Print a formatted metrics report
#'
#' Writes a human-readable metrics table to the console.
#'
#' @param result A [`ModelResult`][ModelResult-class] or named numeric
#'   vector of metrics.
#' @param digits Integer(1). Decimal places for rounding.  Default `4L`.
#' @return `result`, invisibly.
#' @export
print_metrics <- function(result, digits = 4L) {
  if (methods::is(result, "ModelResult")) {
    metrics <- result@metrics
  } else {
    metrics <- as.numeric(result)
    names(metrics) <- names(result)
  }
  cat("Metrics:\n")
  for (nm in names(metrics)) {
    cat(sprintf("  %-14s %.*f\n", nm, digits, metrics[[nm]]))
  }
  invisible(result)
}

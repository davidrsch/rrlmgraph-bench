# Solution for task_012_rf_rpkg
# Replace for-loop in cross_validate() with lapply().
#
# Key decision: use lapply over seq_len(config@cv_folds); the rest of
# the function logic is unchanged. The set.seed() call remains before
# the fold assignment to preserve reproducibility with the same seed.

#' Perform k-fold cross-validation
#'
#' @param data   A data.frame.
#' @param config A [`FitConfig`][FitConfig-class] object.
#' @return A named numeric vector of mean cross-validated metrics.
#' @export
cross_validate <- function(data, config) {
  set.seed(config@seed)
  n <- nrow(data)
  folds <- sample(rep_len(seq_len(config@cv_folds), n))

  metric_rows <- lapply(seq_len(config@cv_folds), function(k) {
    train_k <- data[folds != k, , drop = FALSE]
    test_k <- data[folds == k, , drop = FALSE]
    res_k <- fit_model_s4(train_k, config)
    evaluate(res_k, newdata = test_k)
  })

  metric_mat <- do.call(rbind, metric_rows)
  colMeans(metric_mat, na.rm = TRUE)
}

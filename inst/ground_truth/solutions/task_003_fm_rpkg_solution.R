# Solution for task_003_fm_rpkg
# Add verbose parameter to cross_validate().
#
# Key decision: print is wrapped in if (verbose) so the default FALSE
# produces zero extra output, preserving existing behaviour.

#' Perform k-fold cross-validation
#'
#' @param data   A data.frame.
#' @param config A [`FitConfig`][FitConfig-class] object.
#' @param verbose Logical(1). If TRUE, print per-fold metrics to the console.
#' @return A named numeric vector of mean cross-validated metrics.
#' @export
cross_validate <- function(data, config, verbose = FALSE) {
  set.seed(config@seed)
  n <- nrow(data)
  folds <- sample(rep_len(seq_len(config@cv_folds), n))
  metric_rows <- vector("list", config@cv_folds)

  for (k in seq_len(config@cv_folds)) {
    train_k <- data[folds != k, , drop = FALSE]
    test_k <- data[folds == k, , drop = FALSE]
    res_k <- fit_model_s4(train_k, config)
    metrics_k <- evaluate(res_k, newdata = test_k)
    metric_rows[[k]] <- metrics_k

    if (verbose) {
      cat(sprintf(
        "Fold %d/%d: %s\n",
        k,
        config@cv_folds,
        paste(names(metrics_k), round(metrics_k, 4L), sep = "=", collapse = " ")
      ))
    }
  }

  metric_mat <- do.call(rbind, metric_rows)
  colMeans(metric_mat, na.rm = TRUE)
}

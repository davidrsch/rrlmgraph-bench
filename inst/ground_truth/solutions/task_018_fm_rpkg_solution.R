# Solution for task_018_fm_rpkg
# Add na.rm parameter to cross_validate()

#' @rdname cross_validate
#' @param na.rm Logical(1). When TRUE (default), remove rows with NA values
#'   before forming cross-validation folds.
#' @export
cross_validate <- function(data, config, na.rm = TRUE) {
  if (na.rm) {
    resp_col <- all.vars(config@formula)[1L]
    pred_cols <- all.vars(config@formula)[-1L]
    keep_cols <- intersect(c(resp_col, pred_cols), names(data))
    na_rows <- apply(data[, keep_cols, drop = FALSE], 1L, anyNA)
    data <- data[!na_rows, , drop = FALSE]
  }
  n     <- nrow(data)
  folds <- cut(seq_len(n), breaks = config@cv_folds, labels = FALSE)
  folds <- sample(folds)  # shuffle

  fold_metrics <- vector("list", config@cv_folds)
  for (f in seq_len(config@cv_folds)) {
    train_idx <- which(folds != f)
    test_idx  <- which(folds == f)
    fold_res  <- fit_model_s4(data[train_idx, , drop = FALSE], config)
    eval_res  <- evaluate_model(fold_res, data[test_idx, , drop = FALSE])
    fold_metrics[[f]] <- eval_res
  }
  fold_rmse <- vapply(fold_metrics, `[[`, numeric(1L), "rmse")
  list(mean_rmse = mean(fold_rmse), fold_rmse = fold_rmse)
}

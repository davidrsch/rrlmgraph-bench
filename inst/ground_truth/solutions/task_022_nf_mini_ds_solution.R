# Solution for task_022_nf_mini_ds
# Add cross_validate_model() to R/benchmark.R

#' Run k-fold cross-validation on the mini_ds pipeline
#'
#' @param data    A data.frame.
#' @param formula A formula object.
#' @param k       Integer. Number of folds. Default 5L.
#' @param seed    Integer. Random seed. Default 42L.
#' @return A list with `mean_rmse` (numeric) and `rmse` (length-k numeric vector).
#' @export
cross_validate_model <- function(data, formula, k = 5L, seed = 42L) {
  set.seed(seed)
  n     <- nrow(data)
  folds <- sample(rep_len(seq_len(k), n))
  rmse_vec <- numeric(k)
  for (fold in seq_len(k)) {
    train <- data[folds != fold, , drop = FALSE]
    test  <- data[folds == fold, , drop = FALSE]
    model <- fit_model(train, formula)
    res   <- evaluate_model(model, test)
    rmse_vec[[fold]] <- res$rmse
  }
  list(mean_rmse = mean(rmse_vec), rmse = rmse_vec)
}

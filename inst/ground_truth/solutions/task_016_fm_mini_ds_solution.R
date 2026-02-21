# Solution for task_016_fm_mini_ds
# Add `seed` parameter to split_data.data.frame() for reproducible splits

#' @rdname split_data
#' @param seed Integer(1) or NULL. When non-NULL, passed to set.seed() before
#'   sampling so that splits are reproducible.
#' @export
split_data.data.frame <- function(df, ratio = 0.8, seed = NULL, ...) {
  if (!is.null(seed)) set.seed(seed)
  n <- nrow(df)
  train_idx <- sample(n, size = floor(ratio * n))
  list(
    train = df[train_idx, , drop = FALSE],
    test  = df[-train_idx, , drop = FALSE]
  )
}

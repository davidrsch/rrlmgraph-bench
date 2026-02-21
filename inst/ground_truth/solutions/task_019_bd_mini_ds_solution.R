# Solution for task_019_bd_mini_ds
# Fix off-by-one edge case in split_data.data.frame() for 1-row data frames

#' @rdname split_data
#' @export
split_data.data.frame <- function(df, ratio = 0.8, ...) {
  n <- nrow(df)
  if (n == 0L) {
    return(list(train = df, test = df))
  }
  n_train <- max(1L, floor(ratio * n))
  if (n_train >= n) n_train <- n - 1L  # ensure at least one test row when n > 1
  train_idx <- sample(n, size = n_train, replace = FALSE)
  list(
    train = df[train_idx, , drop = FALSE],
    test  = df[-train_idx, , drop = FALSE]
  )
}

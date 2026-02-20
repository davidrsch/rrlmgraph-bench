# Solution for task_013_doc_mini_ds
# Full Roxygen documentation for split_data.data.frame().
#
# Key decision: include @examples with a minimal 10-row data frame;
# keep @rdname split_data so it renders alongside the generic.

#' Split a data.frame into training and test sets
#'
#' The default S3 method for [split_data()] when the input is a
#' `data.frame`.  Allocates the first `floor(n * ratio)` rows to the
#' training set and the rest to the test set.  Row order is preserved;
#' for random splits, shuffle `df` before calling.
#'
#' @param df    A `data.frame` to split.
#' @param ratio Numeric(1) in (0, 1).  Fraction of rows allocated to
#'   the training set.  Defaults to `0.8`.
#' @param ...   Currently unused; present for S3 method consistency.
#'
#' @return A named list with two elements:
#'   \describe{
#'     \item{`train`}{A `data.frame` containing `floor(n * ratio)` rows.}
#'     \item{`test`}{A `data.frame` containing the remaining rows.}
#'   }
#'
#' @seealso [split_data()] for the generic; [fit_model()] and
#'   [evaluate_model()] for typical downstream usage.
#'
#' @examples
#' df <- data.frame(
#'   id    = 1:10,
#'   score = rnorm(10)
#' )
#' splits <- split_data(df, ratio = 0.7)
#' nrow(splits$train)   # 7
#' nrow(splits$test)    # 3
#'
#' @rdname split_data
#' @export
split_data.data.frame <- function(df, ratio = 0.8, ...) {
  n <- nrow(df)
  n_train <- floor(n * ratio)
  idx <- seq_len(n)
  list(
    train = df[idx[seq_len(n_train)], , drop = FALSE],
    test = df[idx[seq(n_train + 1L, n)], , drop = FALSE]
  )
}

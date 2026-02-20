# Solution for task_001_fm_mini_ds
# Add `stratified` parameter to split_data.data.frame()
#
# Key decision: when stratified = TRUE, iterate over unique strata and
# apply the ratio split within each group, then row-bind the pieces.
# This preserves class proportions in both train and test.

#' @rdname split_data
#' @param stratified Logical(1). If TRUE, perform stratified splitting
#'   using the column named by `strata`.
#' @param strata Character(1). Column name to stratify on. Only used
#'   when `stratified = TRUE`.
#' @export
split_data.data.frame <- function(
  df,
  ratio = 0.8,
  stratified = FALSE,
  strata = NULL,
  ...
) {
  if (stratified) {
    if (is.null(strata) || !strata %in% names(df)) {
      stop(
        "`strata` must be the name of a column in `df` when stratified = TRUE."
      )
    }
    groups <- unique(df[[strata]])
    train_parts <- vector("list", length(groups))
    test_parts <- vector("list", length(groups))
    for (i in seq_along(groups)) {
      sub_df <- df[df[[strata]] == groups[i], , drop = FALSE]
      n_sub <- nrow(sub_df)
      n_tr <- floor(n_sub * ratio)
      idx <- seq_len(n_sub)
      train_parts[[i]] <- sub_df[idx[seq_len(n_tr)], , drop = FALSE]
      test_parts[[i]] <- sub_df[idx[seq(n_tr + 1L, n_sub)], , drop = FALSE]
    }
    return(list(
      train = do.call(rbind, train_parts),
      test = do.call(rbind, test_parts)
    ))
  }

  # Original non-stratified path (unchanged)
  n <- nrow(df)
  n_train <- floor(n * ratio)
  idx <- seq_len(n)
  list(
    train = df[idx[seq_len(n_train)], , drop = FALSE],
    test = df[idx[seq(n_train + 1L, n)], , drop = FALSE]
  )
}

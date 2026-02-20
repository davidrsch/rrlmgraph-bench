# Solution for task_010_rf_mini_ds
# Refactor calculate_mrr() to eliminate explicit vapply + which pattern.
#
# Key decision: use match(TRUE, relevant) for first-hit detection.
# This is idiomatic, avoids which(), and handles NA-safe logic cleanly
# using the same !is.na(r) & as.logical(r) guard from task_004.

#' Calculate Mean Reciprocal Rank
#'
#' @param ranked_results A list of integer/logical vectors where `1`/`TRUE`
#'   marks a relevant item.
#' @return Numeric(1): MRR in `[0, 1]`.
#' @export
calculate_mrr <- function(ranked_results) {
  rr <- vapply(
    ranked_results,
    function(r) {
      relevant <- !is.na(r) & as.logical(r)
      first_hit <- match(TRUE, relevant) # returns NA if no TRUE
      if (is.na(first_hit)) 0 else 1 / first_hit
    },
    numeric(1)
  )
  mean(rr)
}

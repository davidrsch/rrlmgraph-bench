# Solution for task_004_bd_mini_ds
# Fix calculate_mrr() NA-handling bug.
#
# Key decision: use !is.na(r) & as.logical(r) to produce a logical
# vector where both NA and FALSE values are treated as non-relevant.
# This avoids which(NA) returning NA_integer_ which is not FALSE.

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
      # Treat NA relevance flags as non-relevant (FALSE)
      relevant <- !is.na(r) & as.logical(r)
      first_hit <- which(relevant)[1L]
      if (is.na(first_hit)) 0 else 1 / first_hit
    },
    numeric(1)
  )
  mean(rr)
}

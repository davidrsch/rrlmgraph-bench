#' Run the end-to-end data-science benchmark pipeline
#'
#' Loads data from `data_path`, cleans and splits it, fits a linear model,
#' and evaluates it.  Returns a list suitable for [calculate_mrr()] and
#' [format_results()].
#'
#' @param data_path Character(1). Path to the input CSV.
#' @param formula   A `formula` for the model (default: `score ~ .`).
#' @return A list of class `"benchmark_result"` with elements `rmse`,
#'   `predictions`, `n_train`, and `n_test`.
#' @export
run_benchmark <- function(data_path, formula = score ~ .) {
  raw <- load_data(data_path)
  clean <- clean_data(raw)
  splits <- split_data(clean, ratio = 0.8)

  model <- fit_model(splits$train, formula)
  eval <- evaluate_model(model, splits$test)

  result <- list(
    rmse = eval$rmse,
    predictions = eval$predictions,
    n_train = nrow(splits$train),
    n_test = nrow(splits$test)
  )
  class(result) <- "benchmark_result"
  result
}

#' Calculate Mean Reciprocal Rank
#'
#' Given a list of ranked results (each element a numeric vector of 0/1
#' relevance flags in retrieval order), returns the MRR across all queries.
#'
#' @param ranked_results A list of integer/logical vectors where `1`/`TRUE`
#'   marks a relevant item.
#' @return Numeric(1): MRR in `[0, 1]`.
#' @export
calculate_mrr <- function(ranked_results) {
  rr <- vapply(
    ranked_results,
    function(r) {
      first_hit <- which(as.logical(r))[1L]
      if (is.na(first_hit)) 0 else 1 / first_hit
    },
    numeric(1)
  )
  mean(rr)
}

#' Format benchmark results for display
#'
#' @param results A `"benchmark_result"` object from [run_benchmark()].
#' @param digits  Integer(1). Decimal places for rounding.
#' @return Invisibly returns `results`; prints a formatted summary.
#' @export
format_results <- function(results, digits = 3) {
  cat(sprintf(
    "Benchmark Results\n-----------------\n  RMSE:    %s\n  N train: %d\n  N test:  %d\n",
    format(round(results$rmse, digits), nsmall = digits),
    results$n_train,
    results$n_test
  ))
  invisible(results)
}

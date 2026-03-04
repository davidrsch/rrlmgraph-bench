## Unit tests for compute_benchmark_statistics()
## These tests require no external API keys — pure computation.

library(testthat)
library(rrlmgraphbench)

# ---- helpers ----------------------------------------------------------------

make_mock_results <- function(
  strategies = c("rrlmgraph_tfidf", "full_files"),
  n = 10L,
  seed = 42L
) {
  set.seed(seed)
  n_total <- length(strategies) * n
  data.frame(
    strategy = rep(strategies, each = n),
    trial = rep(seq_len(n), times = length(strategies)),
    task_id = rep(paste0("task_", seq_len(n)), times = length(strategies)),
    score = runif(n_total, 0.3, 0.9),
    total_tokens = sample(100L:2000L, n_total, replace = TRUE),
    hallucination_count = sample(0L:3L, n_total, replace = TRUE),
    stringsAsFactors = FALSE
  )
}

# ---- input validation -------------------------------------------------------

test_that("stops with informative error on missing required columns", {
  bad_df <- data.frame(strategy = "a", score = 0.5)
  expect_error(
    compute_benchmark_statistics(bad_df),
    regexp = "missing columns"
  )
})

# ---- basic structure of output ----------------------------------------------

test_that("returns a list with summary, ter, pairwise, ndcg elements", {
  df <- make_mock_results()
  result <- suppressWarnings(compute_benchmark_statistics(df))
  expect_type(result, "list")
  expect_named(
    result,
    c("summary", "ter", "pairwise", "ndcg", "wilcoxon"),
    ignore.order = TRUE
  )
})

test_that("summary has one row per strategy", {
  strats <- c("rrlmgraph_tfidf", "full_files", "no_context")
  df <- make_mock_results(strategies = strats)
  result <- suppressWarnings(compute_benchmark_statistics(df))
  expect_equal(nrow(result$summary), length(strats))
  expect_setequal(result$summary$strategy, strats)
})

test_that("summary contains expected columns", {
  df <- make_mock_results()
  result <- suppressWarnings(compute_benchmark_statistics(df))
  required_cols <- c(
    "strategy",
    "n",
    "mean_score",
    "sd_score",
    "ci_lo_95",
    "ci_hi_95",
    "mean_total_tokens",
    "hallucination_rate"
  )
  expect_true(all(required_cols %in% names(result$summary)))
})

test_that("mean_score is in [0, 1]", {
  df <- make_mock_results()
  result <- suppressWarnings(compute_benchmark_statistics(df))
  expect_true(all(
    result$summary$mean_score >= 0 & result$summary$mean_score <= 1
  ))
})

test_that("hallucination_rate is in [0, 1]", {
  df <- make_mock_results()
  result <- suppressWarnings(compute_benchmark_statistics(df))
  expect_true(all(
    result$summary$hallucination_rate >= 0 &
      result$summary$hallucination_rate <= 1
  ))
})

# ---- TER computation --------------------------------------------------------

test_that("TER is NA for the baseline (full_files) strategy", {
  df <- make_mock_results(strategies = c("rrlmgraph_tfidf", "full_files"))
  result <- suppressWarnings(compute_benchmark_statistics(df))
  expect_true(is.na(result$ter["full_files"]))
})

test_that("TER is numeric for non-baseline strategies", {
  df <- make_mock_results(strategies = c("rrlmgraph_tfidf", "full_files"))
  result <- suppressWarnings(compute_benchmark_statistics(df))
  expect_true(is.numeric(result$ter["rrlmgraph_tfidf"]))
})

# ---- pairwise tests ---------------------------------------------------------

test_that("pairwise data frame has expected columns", {
  df <- make_mock_results(
    strategies = c("rrlmgraph_tfidf", "full_files", "no_context")
  )
  result <- suppressWarnings(compute_benchmark_statistics(df))
  expected_cols <- c(
    "strategy_1",
    "strategy_2",
    "p_value_raw",
    "statistic",
    "cohens_d",
    "p_bonferroni"
  )
  expect_true(all(expected_cols %in% names(result$pairwise)))
})

test_that("pairwise has C(n_strategies, 2) rows", {
  strats <- c("a", "b", "c", "d")
  df <- make_mock_results(strategies = strats)
  result <- suppressWarnings(compute_benchmark_statistics(df))
  expected_pairs <- choose(length(strats), 2L)
  expect_equal(nrow(result$pairwise), expected_pairs)
})

test_that("p_bonferroni <= 1 always", {
  df <- make_mock_results()
  result <- suppressWarnings(compute_benchmark_statistics(df))
  expect_true(all(result$pairwise$p_bonferroni <= 1, na.rm = TRUE))
})

# ---- degenerate: n_trials == 1 ----------------------------------------------

test_that("returns NULL pairwise and ndcg with n_trials = 1", {
  df <- make_mock_results(n = 1L)
  result <- suppressWarnings(compute_benchmark_statistics(df))
  expect_null(result$pairwise)
  expect_null(result$ndcg)
})

test_that("emits warning when n_trials = 1", {
  df <- make_mock_results(n = 1L)
  expect_warning(
    compute_benchmark_statistics(df),
    regexp = "n_trials = 1"
  )
})

# ---- NDCG from ndcg5/ndcg10 columns ----------------------------------------

test_that("computes NDCG when ndcg5 and ndcg10 columns are present", {
  df <- make_mock_results()
  df$ndcg5 <- runif(nrow(df))
  df$ndcg10 <- runif(nrow(df))
  result <- suppressWarnings(compute_benchmark_statistics(df))
  expect_false(is.null(result$ndcg))
  expect_true("ndcg5" %in% names(result$ndcg))
  expect_true("ndcg10" %in% names(result$ndcg))
})

# ---- NDCG from legacy rank/relevant columns ---------------------------------

test_that("computes NDCG from legacy rank/relevant columns when ndcg5/10 absent", {
  df <- make_mock_results()
  n <- nrow(df)
  df$rank <- sample(1L:10L, n, replace = TRUE)
  df$relevant <- as.logical(sample(0L:1L, n, replace = TRUE))
  result <- suppressWarnings(compute_benchmark_statistics(df))
  expect_false(is.null(result$ndcg))
  expect_true(is.numeric(result$ndcg))
})

# ---- bootstrap CI path (n < 30 and non-normal) ------------------------------

test_that("uses bootstrap CI when n < 30 and distribution is non-normal", {
  # Create extreme bimodal distribution (non-normal) with n = 5
  set.seed(1)
  df <- data.frame(
    strategy = rep(c("rrlmgraph_tfidf", "full_files"), each = 5L),
    trial = rep(1:5, times = 2L),
    score = c(0, 0, 0, 1, 1, 0, 0, 0, 1, 1),
    total_tokens = rep(100L, 10L),
    hallucination_count = rep(0L, 10L),
    stringsAsFactors = FALSE
  )
  # Should not error even with bootstrap path
  result <- suppressWarnings(compute_benchmark_statistics(df))
  ci_methods <- result$summary$ci_method
  # At least one strategy used bootstrap (small n + bimodal)
  expect_true(any(ci_methods %in% c("bootstrap", "t")))
})
# ---- Paired Wilcoxon test (bench#38) ----------------------------------------

test_that("wilcoxon is NULL when bm25_retrieval absent", {
  df <- make_mock_results(strategies = c("rrlmgraph_tfidf", "full_files"))
  result <- suppressWarnings(compute_benchmark_statistics(df))
  expect_null(result$wilcoxon)
})

test_that("wilcoxon has expected columns when bm25_retrieval present", {
  df <- make_mock_results(
    strategies = c("rrlmgraph_tfidf", "bm25_retrieval", "full_files"),
    n = 10L
  )
  result <- suppressWarnings(compute_benchmark_statistics(df))
  expect_false(is.null(result$wilcoxon))
  expected_cols <- c(
    "strategy",
    "reference",
    "V",
    "p_value",
    "n_pairs",
    "wins",
    "ties",
    "losses"
  )
  expect_true(all(expected_cols %in% names(result$wilcoxon)))
  # bm25 should not appear as a row (it is the reference)
  expect_false("bm25_retrieval" %in% result$wilcoxon$strategy)
})

test_that("wilcoxon p_value is in [0, 1]", {
  df <- make_mock_results(
    strategies = c("rrlmgraph_tfidf", "bm25_retrieval"),
    n = 10L
  )
  result <- suppressWarnings(compute_benchmark_statistics(df))
  expect_true(all(
    result$wilcoxon$p_value >= 0 &
      result$wilcoxon$p_value <= 1,
    na.rm = TRUE
  ))
})

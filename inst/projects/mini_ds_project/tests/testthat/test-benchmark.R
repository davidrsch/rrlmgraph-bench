test_that("calculate_mrr returns 1 when first hit is first result", {
  res <- calculate_mrr(list(c(1, 0, 0), c(1, 0, 0)))
  expect_equal(res, 1)
})

test_that("calculate_mrr returns 0.5 when first hit is at rank 2", {
  res <- calculate_mrr(list(c(0, 1, 0)))
  expect_equal(res, 0.5)
})

test_that("calculate_mrr handles no relevant results", {
  res <- calculate_mrr(list(c(0, 0, 0)))
  expect_equal(res, 0)
})

test_that("calculate_mrr averages correctly over multiple queries", {
  # Query 1: first hit rank 1 → RR = 1
  # Query 2: first hit rank 2 → RR = 0.5
  # MRR = 0.75
  res <- calculate_mrr(list(c(1, 0, 0), c(0, 1, 0)))
  expect_equal(res, 0.75)
})

test_that("format_results prints without error for a valid result", {
  fake <- list(rmse = 1.234, n_train = 80L, n_test = 20L)
  class(fake) <- "benchmark_result"
  expect_output(format_results(fake), regexp = "RMSE")
})

test_that("format_results returns invisibly", {
  fake <- list(rmse = 0.5, n_train = 10L, n_test = 5L)
  class(fake) <- "benchmark_result"
  ret <- withVisible(format_results(fake))
  expect_false(ret$visible)
})

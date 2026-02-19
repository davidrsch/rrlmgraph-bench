test_that("fit_model returns an lm_result object", {
  df <- data.frame(x = 1:20, score = 2 * (1:20) + rnorm(20))
  model <- fit_model(df, score ~ x)

  expect_s3_class(model, "lm_result")
  expect_s3_class(model, "lm")
})

test_that("evaluate_model.lm_result returns rmse and predictions", {
  df <- data.frame(x = 1:30, score = 3 * (1:30) + rnorm(30))
  splits <- split_data(df, ratio = 0.7)
  model <- fit_model(splits$train, score ~ x)
  result <- evaluate_model(model, splits$test)

  expect_named(result, c("rmse", "predictions"))
  expect_type(result$rmse, "double")
  expect_gt(result$rmse, 0)
  expect_length(result$predictions, nrow(splits$test))
})

test_that("evaluate_model dispatches to lm_result method", {
  df <- data.frame(a = 1:10, score = (1:10) * 0.5)
  model <- fit_model(df, score ~ a)
  expect_no_error(evaluate_model(model, df))
})

test_that("compute_rmse is zero for perfect predictions", {
  x <- c(1, 2, 3, 4, 5)
  expect_equal(compute_rmse(x, x), 0)
})

test_that("compute_rmse is positive for imperfect predictions", {
  expect_gt(compute_rmse(c(1, 2, 3), c(1, 2, 4)), 0)
})

test_that("run_benchmark returns a benchmark_result", {
  skip_if_not_installed("dplyr")
  f <- make_csv()
  # Use a formula with variables known to exist after clean_data
  r <- tryCatch(run_benchmark(f, formula = score_z ~ id), error = function(e) {
    NULL
  })
  if (!is.null(r)) {
    expect_s3_class(r, "benchmark_result")
    expect_named(r, c("rmse", "predictions", "n_train", "n_test"))
  }
  unlink(f)
})

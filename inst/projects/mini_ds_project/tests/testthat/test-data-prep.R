test_that("load_data throws on missing file", {
  expect_error(load_data(tempfile()))
})

test_that("load_data returns a data.frame", {
  f <- make_csv()
  df <- load_data(f)
  expect_s3_class(df, "data.frame")
  unlink(f)
})

test_that("clean_data removes NA rows and adds score_z", {
  f <- make_csv()
  raw <- load_data(f)
  clean <- clean_data(raw)

  expect_false(any(is.na(clean$score)))
  expect_true("score_z" %in% names(clean))
  unlink(f)
})

test_that("clean_data z-scores have approximately zero mean", {
  f <- make_csv()
  raw <- load_data(f)
  clean <- clean_data(raw)

  expect_lt(abs(mean(clean$score_z)), 1e-10)
  unlink(f)
})

test_that("split_data.data.frame splits into correct proportions", {
  f <- make_csv()
  df <- clean_data(load_data(f))
  splits <- split_data(df, ratio = 0.8)

  expect_named(splits, c("train", "test"))
  total <- nrow(splits$train) + nrow(splits$test)
  expect_equal(total, nrow(df))
  unlink(f)
})

test_that("split_data uses default ratio of 0.8", {
  df <- data.frame(x = 1:100, y = rnorm(100))
  splits <- split_data(df)
  expect_equal(nrow(splits$train), 80L)
  expect_equal(nrow(splits$test), 20L)
})

test_that("split_data dispatches to data.frame method", {
  df <- data.frame(x = 1:4, y = 1:4)
  expect_no_error(split_data(df))
})

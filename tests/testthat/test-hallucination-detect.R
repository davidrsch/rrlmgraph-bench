## Unit tests for count_hallucinations()
## These tests require no external API keys.

library(testthat)
library(rrlmgraphbench)

# ---- helpers ----------------------------------------------------------------

valid_r_code <- "
x <- 1 + 2
y <- mean(c(1, 2, 3))
z <- paste('hello', 'world', sep = ' ')
"

# ---- basic correctness ------------------------------------------------------

test_that("returns empty list for valid R code with no hallucinations", {
  result <- count_hallucinations(valid_r_code)
  expect_type(result, "list")
  expect_length(result, 0L)
})

test_that("returns empty list for empty string", {
  result <- count_hallucinations("")
  expect_type(result, "list")
  expect_length(result, 0L)
})

test_that("returns empty list for whitespace-only code", {
  result <- count_hallucinations("   \n\t  ")
  expect_type(result, "list")
  expect_length(result, 0L)
})

# ---- invented functions -----------------------------------------------------

test_that("detects invented function that doesn't exist in session", {
  code <- "result <- xyzzy_completely_invented_fn_abc123(mtcars)"
  result <- count_hallucinations(code)
  expect_gte(length(result), 1L)
  types <- vapply(result, `[[`, character(1L), "type")
  expect_true("invented_function" %in% types)
})

test_that("hallucination entry has required fields: type, fn, detail", {
  code <- "result <- totally_fake_function_xyz(1, 2)"
  result <- count_hallucinations(code)
  expect_gte(length(result), 1L)
  first <- result[[1L]]
  expect_named(first, c("type", "fn", "detail"), ignore.order = TRUE)
  expect_type(first$type, "character")
  expect_type(first$fn, "character")
  expect_type(first$detail, "character")
})

test_that("base R functions are not flagged as invented", {
  code <- "x <- sum(c(1, 2, 3)); y <- mean(x); z <- sqrt(y)"
  result <- count_hallucinations(code)
  fns_flagged <- vapply(result, `[[`, character(1L), "fn")
  expect_false("sum" %in% fns_flagged)
  expect_false("mean" %in% fns_flagged)
  expect_false("sqrt" %in% fns_flagged)
})

# ---- NSE wrapper exemption --------------------------------------------------

test_that("dplyr NSE wrapper calls (mutate, filter) are not flagged", {
  code <- "
library(dplyr)
mtcars |> mutate(kpl = mpg * 0.425) |> filter(cyl > 4)
"
  result <- count_hallucinations(code)
  fns_flagged <- vapply(result, `[[`, character(1L), "fn")
  expect_false("mutate" %in% fns_flagged)
  expect_false("filter" %in% fns_flagged)
})

# ---- wrong namespace --------------------------------------------------------

test_that("detects wrong_namespace when pkg::fn doesn't exist", {
  code <- "rrlmgraph::totally_nonexistent_export_xyz()"
  result <- count_hallucinations(code)
  types <- vapply(result, `[[`, character(1L), "type")
  expect_true("wrong_namespace" %in% types)
})

test_that("does not flag correct namespace calls", {
  # base::sum is correctly exported
  code <- "base::sum(c(1, 2, 3))"
  result <- count_hallucinations(code)
  wrong_ns <- Filter(function(x) x$type == "wrong_namespace", result)
  fns <- vapply(wrong_ns, `[[`, character(1L), "fn")
  expect_false("base::sum" %in% fns)
})

# ---- invalid arguments ------------------------------------------------------

test_that("detects invalid argument to a known function", {
  # nchar() formals: (x, type, allowNA, keepNA) -- no '...', so invalid args
  # are detectable.  'mean' accepts '...' and would not be caught.
  code <- "nchar('hello', nonexistent_arg_xyz = TRUE)"
  result <- count_hallucinations(code)
  types <- vapply(result, `[[`, character(1L), "type")
  expect_true("invalid_argument" %in% types)
  inv_args <- Filter(function(x) x$type == "invalid_argument", result)
  args_found <- vapply(inv_args, function(x) x$detail, character(1L))
  expect_true(any(grepl("nonexistent_arg_xyz", args_found)))
})

test_that("valid named args to base R functions are not flagged as invalid", {
  code <- "nchar('hello', type = 'chars', allowNA = FALSE)"
  result <- count_hallucinations(code)
  types <- vapply(result, `[[`, character(1L), "type")
  expect_false("invalid_argument" %in% types)
})

# ---- parse error handling ---------------------------------------------------

test_that("returns empty list and may warn for unparseable code", {
  bad_code <- "<<< this is NOT valid R code }}"
  # Should not error, may warn
  result <- suppressWarnings(count_hallucinations(bad_code))
  expect_type(result, "list")
  # May return empty list since parse fails
  expect_length(result, 0L)
})

# ---- graph trust list -------------------------------------------------------

test_that("functions in graph are trusted (not flagged as invented)", {
  # Simulate a graph with a custom node name
  fake_graph <- igraph::make_ring(1L)
  igraph::V(fake_graph)$name <- "my_custom_trusted_fn"

  code <- "result <- my_custom_trusted_fn(data)"
  result_without_graph <- count_hallucinations(code)
  result_with_graph <- count_hallucinations(code, graph = fake_graph)

  # Without graph: should flag as invented
  without_types <- vapply(result_without_graph, `[[`, character(1L), "type")
  expect_true("invented_function" %in% without_types)

  # With graph: should NOT flag as invented (trusted)
  with_types <- vapply(result_with_graph, `[[`, character(1L), "type")
  inv_without <- Filter(
    function(x) x$type == "invented_function" && x$fn == "my_custom_trusted_fn",
    result_with_graph
  )
  expect_length(inv_without, 0L)
})

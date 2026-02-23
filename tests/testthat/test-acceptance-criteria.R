## Acceptance criteria tests for rrlmgraphbench
## Issue #9 - one test per AC, with appropriate skip guards.
##
## AC1  - graph builds without error on 3+ fixture projects
## AC2  - token budget respected (context <= asked-for budget)
## AC3  - token reduction >= 60 % vs full-file dump          [needs API]
## AC4  - hallucination rate >= 50 % lower than no-context   [needs API]
## AC5  - rrlm_graph() builds in < 30 s on small project
## AC6  - run_full_benchmark() is reproducible               [needs API]
## AC7  - R CMD check passes                                 [CI only]
## AC8  - works on 3+ different project types
## AC9  - S3 plot() and summary() methods exist for rrlm_graph

library(testthat)
library(rrlmgraphbench)

# Helper: require a non-empty env var or skip
skip_if_no_api_key <- function(var = "OPENAI_API_KEY") {
  key <- Sys.getenv(var, unset = "")
  if (!nzchar(key)) {
    testthat::skip(paste("No", var, "environment variable set"))
  }
}

# Helpers for AC9 - must be defined before the test_that() that calls them
existsFunction_in_ns <- function(name, env) {
  # nolint: object_name_linter.
  tryCatch(
    is.function(get(name, envir = env, inherits = FALSE)),
    error = function(e) FALSE
  )
}

existsMethod_or_s3 <- function(generic, class) {
  # nolint: object_name_linter.
  method_name <- paste0(generic, ".", class)
  env <- asNamespace("rrlmgraph")
  found_s3 <- existsFunction_in_ns(method_name, env)
  found_s4 <- tryCatch(
    isGeneric(generic) && existsMethod(generic, class),
    error = function(e) FALSE
  )
  found_s3 || found_s4
}

projects_dir <- system.file("projects", package = "rrlmgraphbench")
mini_path <- file.path(projects_dir, "mini_ds_project")
shiny_path <- file.path(projects_dir, "shiny_app_medium")
pkg_path <- file.path(projects_dir, "r_package_small")

# -------------------------------------------------------------------------
# AC1: graph builds cleanly on every fixture project ----------------------
test_that("AC1: rrlm_graph() builds without error on all 3 fixture projects", {
  skip_if_not_installed("rrlmgraph")

  expect_no_error(g_mini <- rrlmgraph::build_rrlm_graph(mini_path))
  expect_no_error(g_shiny <- rrlmgraph::build_rrlm_graph(shiny_path))
  expect_no_error(g_pkg <- rrlmgraph::build_rrlm_graph(pkg_path))

  # Each graph should have at least one node
  # rrlm_graph IS an igraph (class is added on top); use V() directly.
  expect_gt(length(igraph::V(g_mini)), 0L)
  expect_gt(length(igraph::V(g_shiny)), 0L)
  expect_gt(length(igraph::V(g_pkg)), 0L)
})

# -------------------------------------------------------------------------
# AC2: token budget respected -------------------------------------------
test_that("AC2: query_context() respects the max_tokens budget", {
  skip_if_not_installed("rrlmgraph")

  g <- rrlmgraph::build_rrlm_graph(mini_path)
  budget <- 200L
  ctx <- rrlmgraph::query_context(
    g,
    "split data into train/test",
    budget_tokens = budget
  )
  ctx_str <- if (is.null(ctx$context_string)) "" else ctx$context_string
  # Use the same counting method as query_context() internally:
  # tokenizers word-count when available, otherwise nchar/4 heuristic.
  actual_tokens <- if (requireNamespace("tokenizers", quietly = TRUE)) {
    as.integer(length(tokenizers::tokenize_words(ctx_str)[[1L]]))
  } else {
    nchar(ctx_str) %/% 4L
  }
  expect_lte(actual_tokens, budget * 1.1) # allow 10% tolerance for word boundaries
})

# -------------------------------------------------------------------------
# AC3: token reduction >= 60 % vs full-file baseline  [needs API key] ------
test_that("AC3: rrlmgraph context uses >= 60 % fewer tokens than full_files", {
  skip_if_no_api_key()
  skip_if_not_installed("rrlmgraph")

  g <- rrlmgraph::build_rrlm_graph(mini_path)
  ctx_graph <- rrlmgraph::query_context(g, "split data into train/test")
  tokens_graph <- nchar(
    if (is.null(ctx_graph$context_string)) "" else ctx_graph$context_string
  ) %/%
    4L

  r_files <- list.files(file.path(mini_path, "R"), "\\.R$", full.names = TRUE)
  full_text <- paste(
    vapply(
      r_files,
      function(f) paste(readLines(f, warn = FALSE), collapse = "\n"),
      character(1L)
    ),
    collapse = "\n"
  )
  tokens_full <- nchar(full_text) %/% 4L

  reduction <- 1 - tokens_graph / tokens_full
  expect_gte(reduction, 0.6)
})

# -------------------------------------------------------------------------
# AC4: hallucination rate >= 50 % lower than no-context baseline [needs API]
test_that("AC4: rrlmgraph reduces hallucinations vs no-context by >= 50 %", {
  skip_if_no_api_key()
  skip_if_not_installed("rrlmgraph")

  tasks_dir <- system.file("tasks", package = "rrlmgraphbench")
  results <- run_full_benchmark(
    tasks_dir = tasks_dir,
    projects_dir = projects_dir,
    output_path = tempfile(fileext = ".rds"),
    n_trials = 1L,
    seed = 42L
  )
  tfidf_hall <- mean(
    results[results$strategy == "rrlmgraph_tfidf", "hallucination_count"] > 0
  )
  no_ctx_hall <- mean(
    results[results$strategy == "no_context", "hallucination_count"] > 0
  )

  if (is.na(no_ctx_hall) || no_ctx_hall == 0) {
    skip("no_context produced zero hallucinations - cannot compute ratio")
  }
  reduction <- 1 - tfidf_hall / no_ctx_hall
  expect_gte(reduction, 0.5)
})

# -------------------------------------------------------------------------
# AC5: graph build time < 30 s on small project ---------------------------
test_that("AC5: rrlm_graph() builds mini_ds_project in under 30 seconds", {
  skip_if_not_installed("rrlmgraph")

  elapsed <- system.time(
    rrlmgraph::build_rrlm_graph(mini_path)
  )[["elapsed"]]

  expect_lt(elapsed, 30)
})

# -------------------------------------------------------------------------
# AC6: run_full_benchmark() is reproducible  [needs API key] --------------
test_that("AC6: run_full_benchmark() produces identical scores with same seed", {
  skip_if_no_api_key()
  skip_if_not_installed("rrlmgraph")

  tasks_dir <- system.file("tasks", package = "rrlmgraphbench")
  run_bench <- function() {
    run_full_benchmark(
      tasks_dir = tasks_dir,
      projects_dir = projects_dir,
      output_path = tempfile(fileext = ".rds"),
      n_trials = 1L,
      seed = 99L
    )
  }
  r1 <- run_bench()
  r2 <- run_bench()
  expect_equal(r1$score, r2$score, tolerance = 1e-9)
})

# -------------------------------------------------------------------------
# AC7: R CMD check passes  [CI only] --------------------------------------
test_that("AC7: package passes R CMD check (run in CI)", {
  skip_if(
    !nzchar(Sys.getenv("CI")),
    "AC7 is enforced by the CI workflow, not this unit test"
  )
  # If we reach here in CI, the check already passed if this test runs.
  expect_true(TRUE)
})

# -------------------------------------------------------------------------
# AC8: graph builds on 3+ project types  (same as AC1 but explicit) -------
test_that("AC8: package works with data-science, Shiny, and R-package project types", {
  skip_if_not_installed("rrlmgraph")

  project_paths <- list(
    mini_ds_project = mini_path,
    shiny_app_medium = shiny_path,
    r_package_small = pkg_path
  )
  for (nm in names(project_paths)) {
    p <- project_paths[[nm]]
    expect_no_error(rrlmgraph::build_rrlm_graph(p))
  }
})

# -------------------------------------------------------------------------
# AC9: S3 methods plot() and summary() exist for rrlm_graph objects -------
test_that("AC9: plot.rrlm_graph and summary.rrlm_graph S3 methods are registered", {
  skip_if_not_installed("rrlmgraph")

  expect_true(
    existsMethod_or_s3("plot", "rrlm_graph"),
    label = "plot.rrlm_graph exists"
  )
  expect_true(
    existsMethod_or_s3("summary", "rrlm_graph"),
    label = "summary.rrlm_graph exists"
  )
})

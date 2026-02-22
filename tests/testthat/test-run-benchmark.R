## Unit tests for run_full_benchmark()
## Uses .dry_run = TRUE so no LLM or API calls are made.

library(testthat)
library(rrlmgraphbench)

skip_if_not_installed("rrlmgraph")
skip_if_not_installed("jsonlite")

# ---- helpers ----------------------------------------------------------------

#' Write a minimal task JSON to a temp directory and return it
make_task_dir <- function(project = "mini_ds_project") {
  tmp <- tempfile("bench_tasks_")
  dir.create(tmp)
  task <- list(
    task_id = "test_task_001",
    category = "function_modification",
    project = project,
    description = "A test task description.",
    seed_node = NULL,
    ground_truth_nodes = list(),
    ground_truth_file = NULL,
    evaluation_method = "ast_diff",
    difficulty = "easy"
  )
  jsonlite::write_json(
    task,
    file.path(tmp, "task_test_001.json"),
    auto_unbox = TRUE
  )
  tmp
}

projects_dir <- system.file("projects", package = "rrlmgraphbench")

# ---- basic output structure -------------------------------------------------

test_that("returns a data.frame with expected columns in dry_run mode", {
  tasks_dir <- make_task_dir()
  on.exit(unlink(tasks_dir, recursive = TRUE))

  result <- suppressMessages(suppressWarnings(
    run_full_benchmark(
      tasks_dir = tasks_dir,
      projects_dir = projects_dir,
      output_path = tempfile(fileext = ".rds"),
      n_trials = 1L,
      seed = 1L,
      .dry_run = TRUE
    )
  ))

  expect_s3_class(result, "data.frame")

  required_cols <- c(
    "task_id",
    "strategy",
    "trial",
    "score",
    "context_tokens",
    "response_tokens",
    "total_tokens",
    "latency_sec",
    "hallucination_count",
    "syntax_valid",
    "runs_without_error"
  )
  expect_true(
    all(required_cols %in% names(result)),
    label = paste(
      "Missing cols:",
      paste(setdiff(required_cols, names(result)), collapse = ", ")
    )
  )
})

test_that("dry_run produces score == 0.5 for all rows", {
  tasks_dir <- make_task_dir()
  on.exit(unlink(tasks_dir, recursive = TRUE))

  result <- suppressMessages(suppressWarnings(
    run_full_benchmark(
      tasks_dir = tasks_dir,
      projects_dir = projects_dir,
      output_path = tempfile(fileext = ".rds"),
      n_trials = 1L,
      seed = 1L,
      .dry_run = TRUE
    )
  ))

  expect_true(all(result$score == 0.5))
  expect_true(all(result$syntax_valid == TRUE))
  expect_true(all(result$runs_without_error == TRUE))
})

test_that("output_path RDS file is created by run_full_benchmark", {
  tasks_dir <- make_task_dir()
  output_rds <- tempfile(fileext = ".rds")
  on.exit({
    unlink(tasks_dir, recursive = TRUE)
    unlink(output_rds)
  })

  suppressMessages(suppressWarnings(
    run_full_benchmark(
      tasks_dir = tasks_dir,
      projects_dir = projects_dir,
      output_path = output_rds,
      n_trials = 1L,
      seed = 1L,
      .dry_run = TRUE
    )
  ))

  expect_true(file.exists(output_rds))
  loaded <- readRDS(output_rds)
  expect_s3_class(loaded, "data.frame")
})

test_that("result has 1 row per strategy per trial", {
  tasks_dir <- make_task_dir()
  on.exit(unlink(tasks_dir, recursive = TRUE))

  result <- suppressMessages(suppressWarnings(
    run_full_benchmark(
      tasks_dir = tasks_dir,
      projects_dir = projects_dir,
      output_path = tempfile(fileext = ".rds"),
      n_trials = 2L,
      seed = 1L,
      .dry_run = TRUE
    )
  ))

  # Rows = n_strategies (minus ollama if unavailable) × 1 task × 2 trials
  n_strats <- length(unique(result$strategy))
  expect_equal(nrow(result), n_strats * 1L * 2L)
  expect_equal(max(result$trial), 2L)
})

test_that("stops with informative error when tasks_dir has no JSON files", {
  empty_dir <- tempfile("empty_")
  dir.create(empty_dir)
  on.exit(unlink(empty_dir, recursive = TRUE))

  expect_error(
    run_full_benchmark(
      tasks_dir = empty_dir,
      projects_dir = projects_dir,
      output_path = tempfile(fileext = ".rds"),
      .dry_run = TRUE
    ),
    regexp = "No task JSON files"
  )
})

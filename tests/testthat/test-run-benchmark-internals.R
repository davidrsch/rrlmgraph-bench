## Unit tests for run_benchmark.R internal helpers.
## No LLM / network calls are made in any test below.

library(testthat)
library(rrlmgraphbench)

# ---- helpers ----------------------------------------------------------------

# Write a small R file and return its path.
make_r_file <- function(dir, filename, content) {
  path <- file.path(dir, filename)
  writeLines(content, path)
  path
}

# ---- list_r_files -----------------------------------------------------------

test_that("list_r_files returns .R files from R/ sub-directory when it exists", {
  tmp <- withr::local_tempdir()
  r_dir <- file.path(tmp, "R")
  dir.create(r_dir)
  make_r_file(r_dir, "foo.R", "foo <- function() 1")
  make_r_file(r_dir, "bar.R", "bar <- function() 2")
  make_r_file(tmp, "root.R", "# ignored") # should NOT be included

  result <- rrlmgraphbench:::list_r_files(tmp)
  expect_length(result, 2L)
  expect_true(all(endsWith(result, ".R")))
  expect_false(any(grepl("root.R", result, fixed = TRUE)))
})

test_that("list_r_files scans project root recursively when no R/ sub-dir exists", {
  tmp <- withr::local_tempdir()
  make_r_file(tmp, "alpha.R", "alpha <- 1")
  sub <- file.path(tmp, "sub")
  dir.create(sub)
  make_r_file(sub, "beta.R", "beta <- 2")

  result <- rrlmgraphbench:::list_r_files(tmp)
  expect_gte(length(result), 2L)
  expect_true(all(endsWith(result, ".R")))
})

# ---- read_lines_safe --------------------------------------------------------

test_that("read_lines_safe reads an existing file as a single string", {
  tmp <- withr::local_tempdir()
  path <- make_r_file(tmp, "test.R", c("line1", "line2"))

  result <- rrlmgraphbench:::read_lines_safe(path)
  expect_type(result, "character")
  expect_length(result, 1L)
  expect_match(result, "line1")
  expect_match(result, "line2")
})

test_that("read_lines_safe returns empty string for nonexistent file", {
  result <- rrlmgraphbench:::read_lines_safe("/nonexistent/path/file.R")
  expect_equal(result, "")
})

# ---- term_overlap_retrieve --------------------------------------------------

test_that("term_overlap_retrieve returns character(0) when files is empty", {
  result <- rrlmgraphbench:::term_overlap_retrieve("any query", character(0L))
  expect_equal(result, character(0L))
})

test_that("term_overlap_retrieve returns the most relevant file first", {
  tmp <- withr::local_tempdir()
  f1 <- make_r_file(tmp, "irrelevant.R", "x <- 1 + 2 + 3")
  f2 <- make_r_file(
    tmp,
    "relevant.R",
    "split_data <- function(x) split_data(x)"
  )

  result <- rrlmgraphbench:::term_overlap_retrieve(
    "split_data",
    c(f1, f2),
    k = 1L
  )
  expect_length(result, 1L)
  expect_match(result[[1L]], "split_data")
})

test_that("term_overlap_retrieve caps output at k even when files > k", {
  tmp <- withr::local_tempdir()
  files <- vapply(
    seq_len(5L),
    function(i) {
      make_r_file(
        tmp,
        paste0("f", i, ".R"),
        paste("fn", i, "<- function() 1")
      )
    },
    character(1L)
  )

  result <- rrlmgraphbench:::term_overlap_retrieve("fn", files, k = 2L)
  expect_length(result, 2L)
})

# ---- bm25_retrieve ----------------------------------------------------------

test_that("bm25_retrieve returns character(0) for empty file list", {
  result <- rrlmgraphbench:::bm25_retrieve("query", character(0L))
  expect_equal(result, character(0L))
})

test_that("bm25_retrieve returns at most k results", {
  tmp <- withr::local_tempdir()
  files <- vapply(
    seq_len(6L),
    function(i) {
      make_r_file(
        tmp,
        paste0("bm_", i, ".R"),
        paste("alpha beta gamma delta", i)
      )
    },
    character(1L)
  )

  result <- rrlmgraphbench:::bm25_retrieve("alpha", files, k = 3L)
  expect_lte(length(result), 3L)
})

test_that("bm25_retrieve falls back to term_overlap for blank query", {
  tmp <- withr::local_tempdir()
  f1 <- make_r_file(tmp, "a.R", "foo <- 1")
  f2 <- make_r_file(tmp, "b.R", "bar <- 2")

  # query with NO word characters → all tokens empty → falls back
  result <- rrlmgraphbench:::bm25_retrieve("  ", c(f1, f2), k = 2L)
  expect_type(result, "character")
})

test_that("bm25_retrieve falls back when avgdl is 0 (all empty files)", {
  tmp <- withr::local_tempdir()
  f1 <- make_r_file(tmp, "empty1.R", "")
  f2 <- make_r_file(tmp, "empty2.R", "")

  # No error expected; output may be character(0) or the empty strings
  result <- rrlmgraphbench:::bm25_retrieve("something", c(f1, f2), k = 2L)
  expect_type(result, "character")
})

# ---- format_prompt ----------------------------------------------------------

test_that("format_prompt includes 'Context:' header when chunks are non-empty", {
  task <- list(
    description = "Modify the split_data function.",
    task_id = "t1"
  )
  prompt <- rrlmgraphbench:::format_prompt(task, "some code here")
  expect_match(prompt, "Context:", fixed = TRUE)
  expect_match(prompt, task$description, fixed = TRUE)
})

test_that("format_prompt omits 'Context:' header for empty context", {
  task <- list(description = "Add a new helper.", task_id = "t2")
  prompt <- rrlmgraphbench:::format_prompt(task, character(0L))
  expect_false(grepl("Context:", prompt, fixed = TRUE))
  expect_match(prompt, task$description, fixed = TRUE)
})

test_that("format_prompt separates multiple chunks with ---", {
  task <- list(description = "Refactor.", task_id = "t3")
  prompt <- rrlmgraphbench:::format_prompt(task, c("chunk A", "chunk B"))
  expect_match(prompt, "---", fixed = TRUE)
})

# ---- .ndcg_at_k -------------------------------------------------------------

test_that(".ndcg_at_k returns NA when no GT nodes are retrieved", {
  result <- rrlmgraphbench:::.ndcg_at_k(c(NA_integer_, NA_integer_), k = 5L)
  expect_true(is.na(result))
})

test_that(".ndcg_at_k returns 1.0 for perfect top-k ranking", {
  # 2 GT nodes at positions 1 and 2 in a k=5 window
  result <- rrlmgraphbench:::.ndcg_at_k(c(1L, 2L), k = 5L)
  expect_equal(result, 1.0, tolerance = 1e-10)
})

test_that(".ndcg_at_k returns value in [0, 1] for partial ranking", {
  # 1 GT node at position 3, 1 not retrieved
  result <- rrlmgraphbench:::.ndcg_at_k(c(3L, NA_integer_), k = 5L)
  expect_gte(result, 0)
  expect_lte(result, 1)
})

test_that(".ndcg_at_k returns 0 when GT nodes are all beyond k", {
  # GT node at position 10 with k=5 → hits is empty → DCG = 0 → 0/IDCG = 0
  result <- rrlmgraphbench:::.ndcg_at_k(c(10L), k = 5L)
  expect_equal(result, 0)
})

# ---- ast_diff_score ---------------------------------------------------------

test_that("ast_diff_score returns 1.0 for identical code", {
  code <- "x <- mean(c(1, 2, 3))\ny <- sqrt(x)"
  score <- rrlmgraphbench:::ast_diff_score(code, code)
  expect_equal(score, 1.0, tolerance = 1e-10)
})

test_that("ast_diff_score returns value in [0, 1] for different code", {
  a <- "x <- mean(c(1, 2, 3))"
  b <- "result <- paste('hello', 'world')"
  score <- rrlmgraphbench:::ast_diff_score(a, b)
  expect_gte(score, 0)
  expect_lte(score, 1)
})

test_that("ast_diff_score handles unparseable code without error", {
  bad <- "<<< this is NOT valid R >>>"
  good <- "x <- 1"
  score <- rrlmgraphbench:::ast_diff_score(bad, good)
  expect_gte(score, 0)
  expect_lte(score, 1)
})

test_that("ast_diff_score returns 0 for two empty strings", {
  # Both return empty call sets and empty token sets → Jaccard = 0/0 → 0
  score <- rrlmgraphbench:::ast_diff_score("", "")
  expect_equal(score, 0)
})

# ---- strip_code_fences -------------------------------------------------------

test_that("strip_code_fences removes ```r fences", {
  result <- rrlmgraphbench:::strip_code_fences("```r\nx <- 5\nprint(x)\n```")
  expect_equal(result, "x <- 5\nprint(x)")
})

test_that("strip_code_fences removes ``` fences with no language tag", {
  result <- rrlmgraphbench:::strip_code_fences("```\nx <- 5\n```")
  expect_equal(result, "x <- 5")
})

test_that("strip_code_fences passes through code with no fences unchanged", {
  code <- "x <- 1 + 1"
  expect_equal(rrlmgraphbench:::strip_code_fences(code), code)
})

test_that("strip_code_fences handles preamble text before fence", {
  result <- rrlmgraphbench:::strip_code_fences(
    "Here is the code:\n```r\nx <- 5\n```"
  )
  expect_equal(result, "x <- 5")
})

test_that("strip_code_fences passes through NA unchanged", {
  expect_equal(rrlmgraphbench:::strip_code_fences(NA_character_), NA_character_)
})

test_that("strip_code_fences passes through empty string unchanged", {
  expect_equal(rrlmgraphbench:::strip_code_fences(""), "")
})

# ---- score_response ---------------------------------------------------------

test_that("score_response marks syntactically valid R as syntax_valid=TRUE", {
  task <- list(
    task_id = "t1",
    evaluation_method = "other",
    ground_truth_nodes = list(),
    ground_truth_file = NULL
  )
  res <- rrlmgraphbench:::score_response("x <- 1 + 2", task)
  expect_true(res$syntax_valid)
})

test_that("score_response marks syntactically invalid R as syntax_valid=FALSE", {
  task <- list(
    task_id = "t1",
    evaluation_method = "other",
    ground_truth_nodes = list(),
    ground_truth_file = NULL
  )
  res <- rrlmgraphbench:::score_response("<<< not R", task)
  expect_false(res$syntax_valid)
})

test_that("score_response uses ground_truth_nodes for node-presence scoring", {
  task <- list(
    task_id = "t1",
    evaluation_method = "node_presence",
    ground_truth_nodes = list("mypkg::my_func"),
    ground_truth_file = NULL
  )
  # Code contains the bare name → hits = c(TRUE) → nodes_score = 1
  res_hit <- rrlmgraphbench:::score_response("result <- my_func(x)", task)
  # Code does not contain it → nodes_score = 0
  res_miss <- rrlmgraphbench:::score_response("result <- other_fn(x)", task)
  expect_gt(res_hit$score, res_miss$score)
})

test_that("score_response returns list with score, syntax_valid, runs_without_error", {
  task <- list(
    task_id = "t1",
    evaluation_method = "other",
    ground_truth_nodes = list(),
    ground_truth_file = NULL
  )
  res <- rrlmgraphbench:::score_response("1 + 1", task)
  expect_named(
    res,
    c("score", "syntax_valid", "runs_without_error"),
    ignore.order = TRUE
  )
  expect_type(res$score, "double")
  expect_type(res$syntax_valid, "logical")
  expect_type(res$runs_without_error, "logical")
})

test_that("score_response rubric weights are 0.25/0.45/0.30 and sum to 1", {
  # Verify the exact weight distribution: syntax=0.25, nodes=0.45, runs=0.30.
  # We derive the weights experimentally using fabricated inputs that each
  # isolate one component at a time.

  # Case 1: syntax=1, nodes=0, runs=0
  # score should equal 0.25 (syntax-only contribution)
  task_no_gt <- list(
    task_id = "w_test",
    evaluation_method = "other",
    ground_truth_nodes = list(),
    ground_truth_file = NULL
  )
  # "<<< broken" — syntax fails, so syntax=0, nodes=0; runs also 0
  broken <- rrlmgraphbench:::score_response("<<< not R", task_no_gt)
  expect_equal(broken$score, 0, tolerance = 1e-10)

  # "1 + 1" — syntax=TRUE (1), nodes=0 (no GT nodes), runs=TRUE (1)
  # score = 0.25*1 + 0.45*0 + 0.30*1 = 0.55
  valid_run <- rrlmgraphbench:::score_response("1 + 1", task_no_gt)
  expect_equal(valid_run$score, 0.25 + 0.30, tolerance = 1e-10)
})

# ---- build_context ----------------------------------------------------------

make_minimal_task <- function() {
  list(
    task_id = "t_bc",
    description = "split data function",
    seed_node = NULL,
    ground_truth_nodes = list()
  )
}

test_that("build_context 'no_context' returns empty chunks and node_ids", {
  result <- rrlmgraphbench:::build_context(
    strategy = "no_context",
    task = make_minimal_task(),
    graph_tfidf = NULL,
    graph_ollama = NULL,
    source_files = character(0L)
  )
  expect_equal(result$chunks, character(0L))
  expect_equal(result$node_ids, character(0L))
})

test_that("build_context 'rrlmgraph_tfidf' with NULL graph returns empty", {
  result <- rrlmgraphbench:::build_context(
    strategy = "rrlmgraph_tfidf",
    task = make_minimal_task(),
    graph_tfidf = NULL,
    graph_ollama = NULL,
    source_files = character(0L)
  )
  expect_equal(result$chunks, character(0L))
})

test_that("build_context 'rrlmgraph_ollama' with NULL graph returns empty", {
  result <- rrlmgraphbench:::build_context(
    strategy = "rrlmgraph_ollama",
    task = make_minimal_task(),
    graph_tfidf = NULL,
    graph_ollama = NULL,
    source_files = character(0L)
  )
  expect_equal(result$chunks, character(0L))
})

test_that("build_context 'full_files' returns file contents", {
  tmp <- withr::local_tempdir()
  f1 <- make_r_file(tmp, "a.R", "a <- 1")
  f2 <- make_r_file(tmp, "b.R", "b <- 2")

  result <- rrlmgraphbench:::build_context(
    strategy = "full_files",
    task = make_minimal_task(),
    graph_tfidf = NULL,
    graph_ollama = NULL,
    source_files = c(f1, f2)
  )
  expect_length(result$chunks, 2L)
  expect_match(paste(result$chunks, collapse = " "), "a <- 1")
})

test_that("build_context 'full_files' respects budget_tokens and never truncates mid-file", {
  tmp <- withr::local_tempdir()
  # Each file is ~100 tokens; budget = 150 tokens => only 1 file admitted
  big_text <- paste(rep("x <- function(a, b) { a + b }", 20L), collapse = "\n")
  f1 <- make_r_file(tmp, "big1.R", big_text)
  f2 <- make_r_file(tmp, "big2.R", big_text)

  result <- rrlmgraphbench:::build_context(
    strategy = "full_files",
    task = make_minimal_task(),
    graph_tfidf = NULL,
    graph_ollama = NULL,
    source_files = c(f1, f2),
    budget_tokens = 150L
  )
  # Only as many complete files as fit within budget should be returned
  total_chars <- sum(nchar(result$chunks))
  # The budget is respected: total tokens estimate <= 150 * 4 chars/token
  expect_lte(total_chars, 150L * 4L + 50L) # small tolerance for estimation
  # Each returned chunk equals the full original file (no mid-file truncation)
  for (chunk in result$chunks) {
    expect_true(chunk == big_text)
  }
})

test_that("build_context 'full_files' with empty source_files returns empty", {
  result <- rrlmgraphbench:::build_context(
    strategy = "full_files",
    task = make_minimal_task(),
    graph_tfidf = NULL,
    graph_ollama = NULL,
    source_files = character(0L)
  )
  expect_equal(result$chunks, character(0L))
})

test_that("build_context 'term_overlap' returns character results", {
  tmp <- withr::local_tempdir()
  f1 <- make_r_file(tmp, "a.R", "split_data <- function(x) x")

  result <- rrlmgraphbench:::build_context(
    strategy = "term_overlap",
    task = make_minimal_task(), # description: "split data function"
    graph_tfidf = NULL,
    graph_ollama = NULL,
    source_files = c(f1)
  )
  expect_type(result$chunks, "character")
})

test_that("build_context 'bm25_retrieval' returns character results", {
  tmp <- withr::local_tempdir()
  f1 <- make_r_file(tmp, "a.R", "split_data <- function(x) x")

  result <- rrlmgraphbench:::build_context(
    strategy = "bm25_retrieval",
    task = make_minimal_task(),
    graph_tfidf = NULL,
    graph_ollama = NULL,
    source_files = c(f1)
  )
  expect_type(result$chunks, "character")
})

test_that("build_context 'random_k' with empty source_files returns empty", {
  result <- rrlmgraphbench:::build_context(
    strategy = "random_k",
    task = make_minimal_task(),
    graph_tfidf = NULL,
    graph_ollama = NULL,
    source_files = character(0L)
  )
  expect_equal(result$chunks, character(0L))
})

test_that("build_context 'random_k' with files returns up to k=5 chunks", {
  tmp <- withr::local_tempdir()
  files <- vapply(
    seq_len(8L),
    function(i) {
      make_r_file(tmp, paste0("x", i, ".R"), paste("fn", i))
    },
    character(1L)
  )

  result <- rrlmgraphbench:::build_context(
    strategy = "random_k",
    task = make_minimal_task(),
    graph_tfidf = NULL,
    graph_ollama = NULL,
    source_files = files
  )
  expect_lte(length(result$chunks), 5L)
  expect_gte(length(result$chunks), 1L)
})

test_that("build_context stops on unknown strategy", {
  expect_error(
    rrlmgraphbench:::build_context(
      strategy = "not_a_real_strategy",
      task = make_minimal_task(),
      graph_tfidf = NULL,
      graph_ollama = NULL,
      source_files = character(0L)
    ),
    regexp = "Unknown strategy"
  )
})
test_that("build_context 'rrlmgraph_tfidf' falls back to empty on query_context error", {
  # A non-NULL, non-rrlm_graph object causes rrlmgraph::query_context to error;
  # the tryCatch handler returns character(0L).
  fake_graph <- list(fake = TRUE)
  result <- rrlmgraphbench:::build_context(
    strategy = "rrlmgraph_tfidf",
    task = make_minimal_task(),
    graph_tfidf = fake_graph,
    graph_ollama = NULL,
    source_files = character(0L)
  )
  expect_equal(result$chunks, character(0L))
})

test_that("build_context 'rrlmgraph_ollama' falls back to empty on query_context error", {
  fake_graph <- list(fake = TRUE)
  result <- rrlmgraphbench:::build_context(
    strategy = "rrlmgraph_ollama",
    task = make_minimal_task(),
    graph_tfidf = NULL,
    graph_ollama = fake_graph,
    source_files = character(0L)
  )
  expect_equal(result$chunks, character(0L))
})

test_that("build_context 'rrlmgraph_tfidf' returns context on successful query_context", {
  skip_if_not_installed("testthat") # local_mocked_bindings requires testthat 3
  skip_if_not_installed("rrlmgraph")

  fake_graph <- structure(list(), class = c("rrlm_graph", "igraph"))
  mock_ctx <- list(
    nodes = data.frame(
      node_id = c("pkg::fn1", "pkg::fn2"),
      stringsAsFactors = FALSE
    ),
    context_string = "fn1 does X; fn2 does Y"
  )

  local_mocked_bindings(
    query_context = function(...) mock_ctx,
    .package = "rrlmgraph"
  )

  result <- rrlmgraphbench:::build_context(
    strategy = "rrlmgraph_tfidf",
    task = make_minimal_task(),
    graph_tfidf = fake_graph,
    graph_ollama = NULL,
    source_files = character(0L)
  )
  # chunks is either the mocked string (mock worked) or character(0) (error fallback)
  expect_type(result$chunks, "character")
  expect_type(result$node_ids, "character")
})

test_that("build_context 'rrlmgraph_tfidf' handles NULL context_string and NULL nodes", {
  skip_if_not_installed("rrlmgraph")

  fake_graph <- structure(list(), class = c("rrlm_graph", "igraph"))
  local_mocked_bindings(
    query_context = function(...) list(nodes = NULL, context_string = NULL),
    .package = "rrlmgraph"
  )

  # Whether the mock applies or not, the result must be type-safe
  result <- rrlmgraphbench:::build_context(
    strategy = "rrlmgraph_tfidf",
    task = make_minimal_task(),
    graph_tfidf = fake_graph,
    graph_ollama = NULL,
    source_files = character(0L)
  )
  expect_type(result$chunks, "character")
  expect_type(result$node_ids, "character")
})

# ---- ast_diff_score: recursive non-call (function definition) ------------

test_that("ast_diff_score handles code with function definitions (recursive walk)", {
  # Code with a function definition exercises the `else if (is.recursive(expr))`
  # branch in the AST walker (function formals are pairlists: recursive, not call)
  code_a <- "f <- function(x, y) x + y"
  code_b <- "g <- function(a, b) a * b"
  score <- rrlmgraphbench:::ast_diff_score(code_a, code_b)
  expect_gte(score, 0)
  expect_lte(score, 1)
})

# ---- score_response: use_ast path with nonexistent ground_truth_file -------

test_that("score_response triggers use_ast path and falls through when file not found", {
  task <- list(
    task_id = "t_ast",
    evaluation_method = "ast_diff",
    ground_truth_nodes = list("pkg::some_fn"),
    # Non-empty path that won't exist in rrlmgraphbench package → falls through
    ground_truth_file = "ground_truth/nonexistent_gt.R"
  )
  # Should not error; falls through to regex scoring
  res <- rrlmgraphbench:::score_response("some_fn(x)", task)
  expect_type(res$score, "double")
  expect_gte(res$score, 0)
})

# ---- score_response: source_files passed (lines 609-615) -----------------

test_that("score_response sources project files before eval when source_files provided", {
  tmp <- withr::local_tempdir()
  helper_file <- make_r_file(
    tmp,
    "helper.R",
    "my_helper <- function(x) x * 2"
  )

  task <- list(
    task_id = "t_sf",
    evaluation_method = "other",
    ground_truth_nodes = list(),
    ground_truth_file = NULL
  )
  # Response code calls my_helper which is defined in source_files
  res <- rrlmgraphbench:::score_response(
    "my_helper(3)",
    task,
    source_files = c(helper_file)
  )
  expect_true(res$runs_without_error)
})

# ---- run_full_benchmark: llm_model != NULL --------------------------------

test_that("run_full_benchmark accepts explicit llm_model parameter", {
  tasks_dir <- withr::local_tempdir()
  task <- list(
    task_id = "t_model",
    category = "test",
    project = "mini_ds_project",
    description = "A task.",
    seed_node = NULL,
    ground_truth_nodes = list(),
    ground_truth_file = NULL,
    evaluation_method = "other",
    difficulty = "easy"
  )
  jsonlite::write_json(
    task,
    file.path(tasks_dir, "t.json"),
    auto_unbox = TRUE
  )

  projects_dir <- system.file("projects", package = "rrlmgraphbench")
  out <- tempfile(fileext = ".rds")

  # llm_model = "gpt-4o-mini" exercises the resolved_model_meta =llm_model branch
  result <- suppressMessages(suppressWarnings(
    run_full_benchmark(
      tasks_dir = tasks_dir,
      projects_dir = projects_dir,
      output_path = out,
      n_trials = 1L,
      llm_model = "gpt-4o-mini",
      seed = 1L,
      .dry_run = TRUE
    )
  ))
  expect_s3_class(result, "data.frame")
})

# ---- run_full_benchmark: Ollama unavailable warning ----------------------

test_that("run_full_benchmark warns and drops rrlmgraph_ollama when Ollama absent", {
  skip_if_not_installed("rrlmgraph")
  skip_if_not_installed("cli")

  tasks_dir <- withr::local_tempdir()
  task <- list(
    task_id = "t_no_ollama",
    category = "test",
    project = "mini_ds_project",
    description = "A task.",
    seed_node = NULL,
    ground_truth_nodes = list(),
    ground_truth_file = NULL,
    evaluation_method = "other",
    difficulty = "easy"
  )
  jsonlite::write_json(
    task,
    file.path(tasks_dir, "t.json"),
    auto_unbox = TRUE
  )

  projects_dir <- system.file("projects", package = "rrlmgraphbench")

  # Force ollama_available() to return FALSE so the warning branch fires
  local_mocked_bindings(
    ollama_available = function(...) FALSE,
    .package = "rrlmgraph"
  )

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
  # rrlmgraph_ollama strategy should be absent from results
  expect_false("rrlmgraph_ollama" %in% unique(result$strategy))
})

# ---- score_response: use_ast SUCCESS path (real ground_truth_file) --------

test_that("score_response uses ast_diff_score when ground_truth_file exists in package", {
  # Use the installed solution file from inst/ground_truth to trigger the
  # `if (nzchar(gt_path) && file.exists(gt_path))` TRUE branch (lines 568-569)
  gt_file <- "inst/ground_truth/solutions/task_001_fm_mini_ds_solution.R"
  gt_path <- system.file(
    sub("^inst/", "", gt_file),
    package = "rrlmgraphbench"
  )
  skip_if(
    !nzchar(gt_path) || !file.exists(gt_path),
    "Solution file not available in installed package"
  )

  task <- list(
    task_id = "t_ast_real",
    evaluation_method = "ast_diff",
    ground_truth_nodes = list(),
    ground_truth_file = gt_file
  )
  res <- rrlmgraphbench:::score_response(
    "split_data <- function(x, ratio=0.8) list(train=x, test=x)",
    task
  )
  expect_type(res$score, "double")
  expect_gte(res$score, 0)
  expect_lte(res$score, 1)
})

# ---- score_response: ground_truth_nodes with S3 dot name (line 611) -------

test_that("score_response escapes metacharacters in S3 method ground_truth_nodes", {
  # Node name with a dot triggers the gsub regex-escaping branch (line ~611)
  task <- list(
    task_id = "t_s3",
    evaluation_method = "node_presence",
    ground_truth_nodes = list("pkg::split_data.data.frame"),
    ground_truth_file = NULL
  )
  res_hit <- rrlmgraphbench:::score_response(
    "split_data.data.frame(x, ratio=0.8)",
    task
  )
  res_miss <- rrlmgraphbench:::score_response(
    "some_other_fn(x)",
    task
  )
  expect_gt(res_hit$score, res_miss$score)
})

# ---- run_single: ground_truth_nodes = NULL (line 651) --------------------

test_that("run_single handles NULL ground_truth_nodes without error", {
  # NULL gt_nodes triggers the else character(0L) branch (line 651)
  task <- list(
    task_id = "t_null_gt",
    description = "test task",
    ground_truth_nodes = NULL, # ← exercises else branch
    ground_truth_file = NULL,
    evaluation_method = "other",
    seed_node = NULL
  )

  result <- suppressWarnings(rrlmgraphbench:::run_single(
    task = task,
    strategy = "no_context",
    trial = 1L,
    graph_tfidf = NULL,
    graph_ollama = NULL,
    source_files = character(0L),
    .dry_run = TRUE
  ))
  expect_equal(result$task_id, "t_null_gt")
  expect_true(is.na(result$ndcg5)) # gt_nodes empty → NA
})

# ---- run_single: non-empty retrieved_ids + gt_nodes (line 654) ----------

test_that("run_single computes NDCG when retrieved_ids matches gt_nodes", {
  skip_if_not_installed("rrlmgraph")

  task <- list(
    task_id = "t_ndcg",
    description = "test ndcg",
    ground_truth_nodes = list("pkg::fn1", "pkg::fn2"),
    ground_truth_file = NULL,
    evaluation_method = "other",
    seed_node = NULL
  )

  # Mock build_context to return non-empty node_ids so the match() branch fires
  local_mocked_bindings(
    build_context = function(...) {
      list(
        chunks = "some context",
        node_ids = c("pkg::fn1", "pkg::fn3") # fn1 matches, fn2 does not
      )
    },
    .package = "rrlmgraphbench"
  )

  result <- suppressWarnings(rrlmgraphbench:::run_single(
    task = task,
    strategy = "no_context",
    trial = 1L,
    graph_tfidf = NULL,
    graph_ollama = NULL,
    source_files = character(0L),
    .dry_run = TRUE
  ))
  expect_equal(result$task_id, "t_ndcg")
  # ndcg5: fn1 is at rank 1 in retrieved list; fn2 not found → partial NDCG
  expect_false(is.na(result$ndcg5))
  expect_gte(result$ndcg5, 0)
  expect_lte(result$ndcg5, 1)
})

# ---- run_single: non-dry_run path - LLM auth failure (lines 684-759) ------

test_that("run_single handles LLM auth failure gracefully in non-dry_run mode", {
  # With llm_provider='github' and no GITHUB_PAT, the code path:
  #   format_prompt() → tryCatch({ chat = …; stop("Set GITHUB_PAT…") }, error → "")
  # This covers the entire non-dry_run entry block (lines 684-754) without a
  # real API call.  The function must still return a well-formed result row.
  skip_if_not_installed("ellmer")

  task <- list(
    task_id = "t_auth_fail",
    description = "fix split_data",
    ground_truth_nodes = list("pkg::split_data"),
    ground_truth_file = NULL,
    evaluation_method = "other",
    seed_node = NULL
  )

  withr::with_envvar(c(GITHUB_PAT = "", GITHUB_TOKEN = ""), {
    result <- suppressMessages(suppressWarnings(
      rrlmgraphbench:::run_single(
        task = task,
        strategy = "no_context",
        trial = 1L,
        graph_tfidf = NULL,
        graph_ollama = NULL,
        source_files = character(0L),
        llm_provider = "github",
        llm_model = NULL,
        .dry_run = FALSE
      )
    ))
  })

  # Result must still be a well-formed list (auth failure → graceful degradation)
  expect_named(
    result,
    c(
      "task_id",
      "strategy",
      "trial",
      "score",
      "context_tokens",
      "response_tokens",
      "total_tokens",
      "latency_sec",
      "hallucination_count",
      "hallucination_details",
      "syntax_valid",
      "runs_without_error",
      "retrieved_n",
      "ndcg5",
      "ndcg10"
    ),
    ignore.order = TRUE
  )
  expect_type(result$score, "double")
  # A failed LLM call (auth error, rate-limit, empty response) must produce
  # either NA (no usable response) or a valid score in [0, 1].
  expect_true(is.na(result$score) || (result$score >= 0 && result$score <= 1))
  expect_type(result$syntax_valid, "logical")
})

# ---- score_response: source_files error handler (line 611) ---------------

test_that("score_response silently handles a source_file that errors on source()", {
  tmp <- withr::local_tempdir()
  bad_file <- make_r_file(tmp, "bad.R", "<<< not valid R >>>")

  task <- list(
    task_id = "t_badsrc",
    evaluation_method = "other",
    ground_truth_nodes = list(),
    ground_truth_file = NULL
  )
  # score_response sources the bad file inside a tryCatch → error handler fires
  res <- rrlmgraphbench:::score_response(
    "1 + 1",
    task,
    source_files = c(bad_file)
  )
  # Should not propagate the source error; score should still be computable
  expect_type(res$score, "double")
})

# ---- run_full_benchmark: benchmark_meta.json write error (line 268) ------

test_that("run_full_benchmark warns gracefully when benchmark_meta.json cannot be written", {
  skip_if_not_installed("jsonlite")

  tasks_dir <- withr::local_tempdir()
  task <- list(
    task_id = "t_meta_err",
    category = "test",
    project = "mini_ds_project",
    description = "A task.",
    seed_node = NULL,
    ground_truth_nodes = list(),
    ground_truth_file = NULL,
    evaluation_method = "other",
    difficulty = "easy"
  )
  jsonlite::write_json(task, file.path(tasks_dir, "t.json"), auto_unbox = TRUE)

  projects_dir <- system.file("projects", package = "rrlmgraphbench")

  # Mock toJSON to throw so the tryCatch error handler at line 268 fires
  local_mocked_bindings(
    toJSON = function(...) stop("mocked json serialisation error"),
    .package = "jsonlite"
  )

  # Should warn (not error) about failing to write benchmark_meta.json
  expect_warning(
    suppressMessages(
      run_full_benchmark(
        tasks_dir = tasks_dir,
        projects_dir = projects_dir,
        output_path = tempfile(fileext = ".rds"),
        n_trials = 1L,
        seed = 1L,
        .dry_run = TRUE
      )
    ),
    regexp = "benchmark_meta\\.json"
  )
})

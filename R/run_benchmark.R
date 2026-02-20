#' Run the full rrlmgraph benchmark
#'
#' Evaluates six retrieval strategies across every task in `tasks_dir`
#' using `n_trials` independent trials each, and persists the combined
#' results to `output_path`.
#'
#' ## Strategies
#' | Label | Description |
#' |---|---|
#' | `rrlmgraph_tfidf` | rrlmgraph with TF-IDF node embeddings |
#' | `rrlmgraph_ollama` | rrlmgraph with Ollama-backed embeddings |
#' | `full_files` | Dump every source file in full (baseline) |
#' | `bm25_retrieval` | BM25 keyword retrieval (no graph) |
#' | `no_context` | No context provided to the LLM |
#' | `random_k` | *k* randomly sampled code chunks |
#'
#' LLM calls are issued through `ellmer::parallel_chat()` for
#' concurrency.  A progress message is emitted after each task × strategy
#' combination together with a rolling time estimate.
#'
#' @param tasks_dir    Path to the directory containing task JSON files
#'   (default: `system.file("tasks", package = "rrlmgraphbench")`).
#' @param projects_dir Path to the directory containing benchmark project
#'   source trees (default: `system.file("projects", package = "rrlmgraphbench")`).
#' @param output_path  File path where the resulting `data.frame` is
#'   saved as an RDS file.  Parent directories are created if needed.
#' @param n_trials     Integer(1). Number of independent trials per
#'   task × strategy pair.  Defaults to `3L`.
#' @param seed         Integer(1). Random seed passed to [base::set.seed()]
#'   before any stochastic operations.  Defaults to `42L`.
#' @param .dry_run     Logical(1). When `TRUE` the LLM is not called;
#'   dummy scores of `0.5` are returned.  Useful for integration tests.
#'
#' @return A `data.frame` (saved to `output_path` and also returned
#'   invisibly) with one row per trial, containing columns:
#'   \describe{
#'     \item{`task_id`}{Character.}
#'     \item{`strategy`}{Character.}
#'     \item{`trial`}{Integer.}
#'     \item{`score`}{Numeric in \[0, 1\].}
#'     \item{`context_tokens`}{Integer.}
#'     \item{`response_tokens`}{Integer.}
#'     \item{`total_tokens`}{Integer.}
#'     \item{`latency_sec`}{Numeric.}
#'     \item{`hallucination_count`}{Integer.}
#'     \item{`hallucination_details`}{List column (character vectors).}
#'     \item{`syntax_valid`}{Logical.}
#'     \item{`runs_without_error`}{Logical.}
#'   }
#'
#' @examples
#' \dontrun{
#' results <- run_full_benchmark(
#'   output_path = "inst/results/benchmark_results.rds",
#'   n_trials    = 3L,
#'   seed        = 42L
#' )
#' head(results)
#' }
#'
#' @importFrom utils txtProgressBar setTxtProgressBar
#' @export
run_full_benchmark <- function(
  tasks_dir = system.file("tasks", package = "rrlmgraphbench"),
  projects_dir = system.file("projects", package = "rrlmgraphbench"),
  output_path,
  n_trials = 3L,
  seed = 42L,
  .dry_run = FALSE
) {
  set.seed(seed)

  strategies <- c(
    "rrlmgraph_tfidf",
    "rrlmgraph_ollama",
    "full_files",
    "bm25_retrieval",
    "no_context",
    "random_k"
  )

  # ---- Load task definitions ------------------------------------------
  task_files <- list.files(tasks_dir, pattern = "\\.json$", full.names = TRUE)
  if (!length(task_files)) {
    stop("No task JSON files found in: ", tasks_dir)
  }

  tasks <- lapply(task_files, function(fp) {
    jsonlite::fromJSON(fp, simplifyVector = TRUE)
  })
  task_ids <- vapply(tasks, `[[`, character(1L), "task_id")

  n_combos <- length(task_ids) * length(strategies) * n_trials
  message(sprintf(
    "[rrlmgraphbench] Starting benchmark: %d tasks × %d strategies × %d trials = %d runs",
    length(task_ids),
    length(strategies),
    n_trials,
    n_combos
  ))

  t0 <- proc.time()[["elapsed"]]
  results <- vector("list", n_combos)
  run_idx <- 0L

  for (task in tasks) {
    project_path <- file.path(projects_dir, task$project)
    graph_tfidf  <- tryCatch(
      rrlmgraph::rrlm_graph(project_path, embed_method = "tfidf"),
      error = function(e) { warning(e); NULL }
    )
    graph_ollama <- tryCatch(
      rrlmgraph::rrlm_graph(project_path, embed_method = "ollama"),
      error = function(e) { warning(e); NULL }
    )
    source_files <- list_r_files(project_path)

    for (strategy in strategies) {
      for (trial in seq_len(n_trials)) {
        run_idx <- run_idx + 1L

        result_row <- run_single(
          task         = task,
          strategy     = strategy,
          trial        = trial,
          graph_tfidf  = graph_tfidf,
          graph_ollama = graph_ollama,
          source_files = source_files,
          .dry_run     = .dry_run
        )
        results[[run_idx]] <- result_row

        elapsed    <- proc.time()[["elapsed"]] - t0
        per_run    <- elapsed / run_idx
        remaining  <- (n_combos - run_idx) * per_run
        message(sprintf(
          "[%d/%d] task=%s strategy=%-20s trial=%d | score=%.3f | est. %.0fs remaining",
          run_idx, n_combos,
          task$task_id, strategy, trial,
          result_row$score, remaining
        ))
      }
    }
  }

  all_results <- do.call(rbind, lapply(results, as.data.frame,
                                       stringsAsFactors = FALSE))
  rownames(all_results) <- NULL

  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(all_results, output_path)
  message("[rrlmgraphbench] Results saved to: ", output_path)

  invisible(all_results)
}

# ---- Internal helpers -----------------------------------------------

list_r_files <- function(project_path) {
  r_dir <- file.path(project_path, "R")
  if (dir.exists(r_dir)) {
    list.files(r_dir, pattern = "\\.R$", full.names = TRUE, recursive = TRUE)
  } else {
    list.files(project_path, pattern = "\\.R$", full.names = TRUE, recursive = TRUE)
  }
}

build_context <- function(strategy, task, graph_tfidf, graph_ollama,
                           source_files) {
  switch(strategy,
    rrlmgraph_tfidf = {
      if (is.null(graph_tfidf)) return(character(0L))
      tryCatch(
        rrlmgraph::query_context(graph_tfidf, task$description,
                                 seed_node = task$seed_node),
        error = function(e) character(0L)
      )
    },
    rrlmgraph_ollama = {
      if (is.null(graph_ollama)) return(character(0L))
      tryCatch(
        rrlmgraph::query_context(graph_ollama, task$description,
                                 seed_node = task$seed_node),
        error = function(e) character(0L)
      )
    },
    full_files = {
      vapply(source_files, readLines_safe, character(1L))
    },
    bm25_retrieval = {
      bm25_retrieve(task$description, source_files)
    },
    no_context = {
      character(0L)
    },
    random_k = {
      k <- min(5L, length(source_files))
      if (k == 0L) return(character(0L))
      vapply(sample(source_files, k), readLines_safe, character(1L))
    },
    stop("Unknown strategy: ", strategy)
  )
}

readLines_safe <- function(path) {
  tryCatch(
    paste(readLines(path, warn = FALSE), collapse = "\n"),
    error = function(e) ""
  )
}

bm25_retrieve <- function(query, files, k = 5L) {
  if (!length(files)) return(character(0L))
  query_terms <- tolower(strsplit(query, "\\W+")[[1L]])
  scores <- vapply(files, function(fp) {
    txt   <- tolower(readLines_safe(fp))
    words <- strsplit(txt, "\\W+")[[1L]]
    sum(query_terms %in% words)
  }, numeric(1L))
  top_k <- head(order(scores, decreasing = TRUE), k)
  vapply(files[top_k], readLines_safe, character(1L))
}

format_prompt <- function(task, context_chunks) {
  ctx_text <- paste(context_chunks, collapse = "\n\n---\n\n")
  if (nzchar(ctx_text)) {
    sprintf(
      "You are an expert R programmer.\n\nContext:\n%s\n\nTask: %s\n\nRespond with ONLY valid R code.",
      ctx_text, task$description
    )
  } else {
    sprintf(
      "You are an expert R programmer.\n\nTask: %s\n\nRespond with ONLY valid R code.",
      task$description
    )
  }
}

score_response <- function(response_code, task) {
  # Rubric: syntax (0.3) + ground truth nodes present (0.4) + runs (0.3)
  syntax_ok <- tryCatch({
    parse(text = response_code, keep.source = FALSE)
    TRUE
  }, error = function(e) FALSE)

  nodes_score <- 0
  if (length(task$ground_truth_nodes) > 0L) {
    hits        <- vapply(task$ground_truth_nodes,
                          function(n) grepl(n, response_code, fixed = TRUE),
                          logical(1L))
    nodes_score <- mean(hits)
  }

  runs_ok <- tryCatch({
    env <- new.env(parent = baseenv())
    eval(parse(text = response_code), envir = env)
    TRUE
  }, error = function(e) FALSE)

  total <- 0.3 * syntax_ok + 0.4 * nodes_score + 0.3 * runs_ok
  list(score = total, syntax_valid = syntax_ok, runs_without_error = runs_ok)
}

run_single <- function(task, strategy, trial, graph_tfidf, graph_ollama,
                       source_files, .dry_run) {
  ctx_chunks <- build_context(strategy, task, graph_tfidf, graph_ollama,
                               source_files)
  ctx_text   <- paste(ctx_chunks, collapse = "\n")

  context_tokens  <- nchar(ctx_text) %/% 4L  # rough token estimate
  response_code   <- ""
  response_tokens <- 0L
  latency_sec     <- 0
  hall_count      <- 0L
  hall_details    <- character(0L)
  syntax_valid    <- FALSE
  runs_ok         <- FALSE
  score           <- 0

  if (.dry_run) {
    score        <- 0.5
    syntax_valid <- TRUE
    runs_ok      <- TRUE
  } else {
    prompt <- format_prompt(task, ctx_chunks)
    t1 <- proc.time()[["elapsed"]]
    llm_result <- tryCatch(
      {
        chat <- ellmer::chat_openai(model = Sys.getenv("OPENAI_MODEL", "gpt-4o-mini"))
        chat$chat(prompt)
      },
      error = function(e) {
        warning("[run_single] LLM call failed: ", conditionMessage(e))
        ""
      }
    )
    latency_sec     <- proc.time()[["elapsed"]] - t1
    response_code   <- llm_result
    response_tokens <- nchar(response_code) %/% 4L

    rubric       <- score_response(response_code, task)
    score        <- rubric$score
    syntax_valid <- rubric$syntax_valid
    runs_ok      <- rubric$runs_without_error

    halls        <- count_hallucinations(response_code)
    hall_count   <- length(halls)
    hall_details <- if (hall_count > 0L) {
      vapply(halls, `[[`, character(1L), "detail")
    } else {
      character(0L)
    }
  }

  list(
    task_id              = task$task_id,
    strategy             = strategy,
    trial                = as.integer(trial),
    score                = score,
    context_tokens       = as.integer(context_tokens),
    response_tokens      = as.integer(response_tokens),
    total_tokens         = as.integer(context_tokens + response_tokens),
    latency_sec          = latency_sec,
    hallucination_count  = as.integer(hall_count),
    hallucination_details= paste(hall_details, collapse = "; "),
    syntax_valid         = syntax_valid,
    runs_without_error   = runs_ok
  )
}

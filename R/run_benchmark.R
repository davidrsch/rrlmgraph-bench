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
#' LLM calls are issued sequentially via \pkg{ellmer}.
#' A progress message is emitted after each task x strategy combination
#' together with a rolling time estimate.
#'
#' @section Authentication:
#' \describe{
#'   \item{`"github"` (default)}{Uses `GITHUB_PAT` / `GITHUB_TOKEN`.
#'     In GitHub Actions this is set automatically as
#'     `secrets.GITHUB_TOKEN` -- no extra secret needed.}
#'   \item{`"openai"`}{Requires `OPENAI_API_KEY`.}
#'   \item{`"anthropic"`}{Requires `ANTHROPIC_API_KEY`.}
#'   \item{`"ollama"`}{No key needed (local daemon).}
#' }
#'
#' @param tasks_dir    Path to the directory containing task JSON files
#'   (default: `system.file("tasks", package = "rrlmgraphbench")`).
#' @param projects_dir Path to the directory containing benchmark project
#'   source trees (default:
#'   `system.file("projects", package = "rrlmgraphbench")`).
#' @param output_path  File path where the resulting `data.frame` is
#'   saved as an RDS file.  Parent directories are created if needed.
#' @param n_trials     Integer(1). Number of independent trials per
#'   task x strategy pair.  Defaults to `3L`.
#' @param llm_provider Character(1). LLM provider passed to \pkg{ellmer}.
#'   One of `"github"` (default), `"openai"`, `"anthropic"`, `"ollama"`.
#' @param llm_model    Character(1) or `NULL`. Model name.  When `NULL`
#'   a sensible per-provider default is used: `"gpt-4o-mini"` for
#'   `"github"` and `"openai"`, `"claude-3-5-haiku-latest"` for
#'   `"anthropic"`, `"llama3.2"` for `"ollama"`.
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
#' # Uses GitHub Models (GITHUB_TOKEN auto-set in Actions -- no secret needed)
#' results <- run_full_benchmark(
#'   output_path = "inst/results/benchmark_results.rds",
#'   n_trials    = 3L
#' )
#' head(results)
#' }
#'
#' @importFrom utils txtProgressBar setTxtProgressBar head
#' @export
run_full_benchmark <- function(
  tasks_dir = system.file("tasks", package = "rrlmgraphbench"),
  projects_dir = system.file("projects", package = "rrlmgraphbench"),
  output_path,
  n_trials = 3L,
  llm_provider = c("github", "openai", "anthropic", "ollama"),
  llm_model = NULL,
  seed = 42L,
  .dry_run = FALSE
) {
  llm_provider <- match.arg(llm_provider)
  set.seed(seed)

  # Fail fast on rate-limit responses instead of waiting for Retry-After
  # (which can be days when the daily quota is exhausted).
  old_max_tries <- getOption("ellmer_max_tries", default = 3L)
  on.exit(options(ellmer_max_tries = old_max_tries), add = TRUE)
  options(ellmer_max_tries = 1L)

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
    paste0(
      "[rrlmgraphbench] Starting benchmark: ",
      "%d tasks \u00d7 %d strategies \u00d7 %d trials = %d runs"
    ),
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
    if (.dry_run) {
      graph_tfidf <- NULL
      graph_ollama <- NULL
      source_files <- character(0L)
    } else {
      graph_tfidf <- tryCatch(
        rrlmgraph::build_rrlm_graph(project_path, embed_method = "tfidf"),
        error = function(e) {
          warning(e)
          NULL
        }
      )
      graph_ollama <- tryCatch(
        rrlmgraph::build_rrlm_graph(project_path, embed_method = "ollama"),
        error = function(e) {
          warning(e)
          NULL
        }
      )
      source_files <- list_r_files(project_path)
    }

    for (strategy in strategies) {
      for (trial in seq_len(n_trials)) {
        run_idx <- run_idx + 1L

        result_row <- run_single(
          task = task,
          strategy = strategy,
          trial = trial,
          graph_tfidf = graph_tfidf,
          graph_ollama = graph_ollama,
          source_files = source_files,
          llm_provider = llm_provider,
          llm_model = llm_model,
          .dry_run = .dry_run
        )
        results[[run_idx]] <- result_row

        elapsed <- proc.time()[["elapsed"]] - t0
        per_run <- elapsed / run_idx
        remaining <- (n_combos - run_idx) * per_run
        message(sprintf(
          "[%d/%d] task=%s strategy=%-20s trial=%d | score=%.3f | est. %.0fs",
          run_idx,
          n_combos,
          task$task_id,
          strategy,
          trial,
          result_row$score,
          remaining
        ))
      }
    }
  }

  all_results <- do.call(
    rbind,
    lapply(results, as.data.frame, stringsAsFactors = FALSE)
  )
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
    list.files(
      project_path,
      pattern = "\\.R$",
      full.names = TRUE,
      recursive = TRUE
    )
  }
}

build_context <- function(
  strategy,
  task,
  graph_tfidf,
  graph_ollama,
  source_files
) {
  switch(
    strategy,
    rrlmgraph_tfidf = {
      if (is.null(graph_tfidf)) {
        return(character(0L))
      }
      tryCatch(
        {
          ctx <- rrlmgraph::query_context(
            graph_tfidf,
            task$description,
            seed_node = task$seed_node
          )
          if (is.null(ctx$context_string)) character(0L) else ctx$context_string
        },
        error = function(e) character(0L)
      )
    },
    rrlmgraph_ollama = {
      if (is.null(graph_ollama)) {
        return(character(0L))
      }
      tryCatch(
        {
          ctx <- rrlmgraph::query_context(
            graph_ollama,
            task$description,
            seed_node = task$seed_node
          )
          if (is.null(ctx$context_string)) character(0L) else ctx$context_string
        },
        error = function(e) character(0L)
      )
    },
    full_files = {
      vapply(source_files, read_lines_safe, character(1L))
    },
    bm25_retrieval = {
      bm25_retrieve(task$description, source_files)
    },
    no_context = {
      character(0L)
    },
    random_k = {
      k <- min(5L, length(source_files))
      if (k == 0L) {
        return(character(0L))
      }
      vapply(sample(source_files, k), read_lines_safe, character(1L))
    },
    stop("Unknown strategy: ", strategy)
  )
}

read_lines_safe <- function(path) {
  tryCatch(
    paste(readLines(path, warn = FALSE), collapse = "\n"),
    error = function(e) ""
  )
}

bm25_retrieve <- function(query, files, k = 5L) {
  if (!length(files)) {
    return(character(0L))
  }
  query_terms <- tolower(strsplit(query, "\\W+")[[1L]])
  scores <- vapply(
    files,
    function(fp) {
      txt <- tolower(read_lines_safe(fp))
      words <- strsplit(txt, "\\W+")[[1L]]
      sum(query_terms %in% words)
    },
    numeric(1L)
  )
  top_k <- head(order(scores, decreasing = TRUE), k)
  vapply(files[top_k], read_lines_safe, character(1L))
}

format_prompt <- function(task, context_chunks) {
  ctx_text <- paste(context_chunks, collapse = "\n\n---\n\n")
  if (nzchar(ctx_text)) {
    sprintf(
      paste0(
        "You are an expert R programmer.\n\n",
        "Context:\n%s\n\nTask: %s\n\n",
        "Respond with ONLY valid R code."
      ),
      ctx_text,
      task$description
    )
  } else {
    sprintf(
      paste0(
        "You are an expert R programmer.\n\n",
        "Task: %s\n\nRespond with ONLY valid R code."
      ),
      task$description
    )
  }
}

score_response <- function(response_code, task) {
  # Rubric: syntax (0.3) + ground truth nodes present (0.4) + runs (0.3)
  syntax_ok <- tryCatch(
    {
      parse(text = response_code, keep.source = FALSE)
      TRUE
    },
    error = function(e) FALSE
  )

  nodes_score <- 0
  if (length(task$ground_truth_nodes) > 0L) {
    hits <- vapply(
      task$ground_truth_nodes,
      function(n) {
        # ground_truth_nodes use "pkg::fn" rrlmgraph convention; strip the
        # namespace prefix before searching so bare function names in the
        # LLM response (e.g. "split_data.data.frame") still match.
        bare_n <- sub("^[^:]+::", "", n)
        grepl(bare_n, response_code, fixed = TRUE)
      },
      logical(1L)
    )
    nodes_score <- mean(hits)
  }

  runs_ok <- tryCatch(
    {
      env <- new.env(parent = baseenv())
      eval(parse(text = response_code), envir = env)
      TRUE
    },
    error = function(e) FALSE
  )

  total <- 0.3 * syntax_ok + 0.4 * nodes_score + 0.3 * runs_ok
  list(score = total, syntax_valid = syntax_ok, runs_without_error = runs_ok)
}

run_single <- function(
  task,
  strategy,
  trial,
  graph_tfidf,
  graph_ollama,
  source_files,
  llm_provider = "github",
  llm_model = NULL,
  .dry_run
) {
  ctx_chunks <- build_context(
    strategy,
    task,
    graph_tfidf,
    graph_ollama,
    source_files
  )
  ctx_text <- paste(ctx_chunks, collapse = "\n")

  context_tokens <- nchar(ctx_text) %/% 4L # rough token estimate
  response_code <- ""
  response_tokens <- 0L
  latency_sec <- 0
  hall_count <- 0L
  hall_details <- character(0L)
  syntax_valid <- FALSE
  runs_ok <- FALSE
  score <- 0

  if (.dry_run) {
    score <- 0.5
    syntax_valid <- TRUE
    runs_ok <- TRUE
  } else {
    prompt <- format_prompt(task, ctx_chunks)
    t1 <- proc.time()[["elapsed"]]
    # -- Resolve ellmer chat by provider ------------------------------------
    # NOTE: ellmer 0.4.0 broke chat_github() by switching from
    # chat_openai_compatible() to chat_openai() (Responses endpoint).
    # GitHub Models only implements /chat/completions, so we call
    # chat_openai_compatible() directly for the github provider.
    default_models <- c(
      github    = "gpt-4.1-mini",
      openai    = "gpt-4.1-mini",
      anthropic = "claude-3-5-haiku-latest",
      ollama    = "llama3.2"
    )
    resolved_model <- if (!is.null(llm_model)) llm_model else default_models[[llm_provider]]
    llm_result <- tryCatch(
      {
        chat <- if (llm_provider == "github") {
          # In CI GITHUB_PAT is set by the workflow env block.
          # For local use, GITHUB_TOKEN or GITHUB_PAT must be set.
          gh_pat <- Sys.getenv("GITHUB_PAT",
                      Sys.getenv("GITHUB_TOKEN", ""))
          if (!nzchar(gh_pat)) {
            stop("Set GITHUB_PAT or GITHUB_TOKEN to use llm_provider='github'")
          }
          cred_fn <- (function(k) function() k)(gh_pat)
          ellmer::chat_openai_compatible(
            base_url    = "https://models.github.ai/inference/",
            model       = resolved_model,
            credentials = cred_fn
          )
        } else {
          chat_fn_name <- switch(
            llm_provider,
            openai    = "chat_openai",
            anthropic = "chat_anthropic",
            ollama    = "chat_ollama"
          )
          chat_fn <- getExportedValue("ellmer", chat_fn_name)
          chat_fn(model = resolved_model)
        }
        chat$chat(prompt)
      },
      error = function(e) {
        message("[run_single] LLM call failed: ", conditionMessage(e))
        ""
      }
    )
    latency_sec <- proc.time()[["elapsed"]] - t1
    response_code <- llm_result
    response_tokens <- nchar(response_code) %/% 4L

    rubric <- score_response(response_code, task)
    score <- rubric$score
    syntax_valid <- rubric$syntax_valid
    runs_ok <- rubric$runs_without_error

    halls <- count_hallucinations(response_code) # nolint: object_usage_linter.
    hall_count <- length(halls)
    hall_details <- if (hall_count > 0L) {
      vapply(halls, `[[`, character(1L), "detail")
    } else {
      character(0L)
    }
  }

  list(
    task_id = task$task_id,
    strategy = strategy,
    trial = as.integer(trial),
    score = score,
    context_tokens = as.integer(context_tokens),
    response_tokens = as.integer(response_tokens),
    total_tokens = as.integer(context_tokens + response_tokens),
    latency_sec = latency_sec,
    hallucination_count = as.integer(hall_count),
    hallucination_details = paste(hall_details, collapse = "; "),
    syntax_valid = syntax_valid,
    runs_without_error = runs_ok
  )
}

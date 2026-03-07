#' Run the full rrlmgraph benchmark
#'
#' Evaluates retrieval strategies across every task in `tasks_dir`
#' using `n_trials` independent trials each, and persists the combined
#' results to `output_path`.  By default five strategies are run (150 total
#' LLM calls for 30 tasks × 1 trial), which fits within the GitHub Models
#' free-tier quota of ~150 requests / day.
#'
#' ## Strategies (all supported values for the `strategies` argument)
#' | Label | Description |
#' |---|---|
#' | `rrlmgraph_tfidf` | rrlmgraph with TF-IDF node embeddings |
#' | `rrlmgraph_ollama` | rrlmgraph with Ollama-backed embeddings |
#' | `rrlmgraph_mcp` | rrlmgraph via the MCP server (stdio JSON-RPC) |
#' | `full_files` | Dump every source file in full (baseline) |
#' | `term_overlap` | Simple term-presence keyword retrieval (no graph) |
#' | `bm25_retrieval` | True BM25 retrieval -- IDF-weighted, length-normalised |
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
#' @param rate_limit_delay Numeric(1). Seconds to wait between LLM API calls
#'   to avoid rate-limit errors.  Defaults to `6`.
#' @param strategies   Character vector. Subset of strategies to run.  Defaults
#'   to all non-Ollama, non-MCP strategies.  Useful for reducing the total
#'   number of LLM API calls when the provider enforces a daily request quota
#'   (e.g. GitHub Models free tier allows ~210 requests/day; with 30 tasks and
#'   all 7 strategies that is exactly 210 calls).  Ollama and MCP
#'   strategies are silently skipped when their prerequisites are unavailable.
#' @param resume       Logical(1). When `TRUE`, check for an existing
#'   partial checkpoint file (`output_path` with `_partial` suffix) and
#'   skip any (task, strategy, trial) combinations already recorded there.
#'   Useful when a previous run was interrupted by a daily rate-limit quota
#'   wall.  Defaults to `FALSE`.
#' @param mcp_server_dir Character(1) or `NULL`. Path to the rrlmgraph-mcp
#'   package directory containing a built `dist/index.js`.  When `NULL`
#'   (default), the environment variable `RRLMGRAPH_MCP_DIR` is consulted.
#'   Required when `"rrlmgraph_mcp"` is included in `strategies`; the strategy
#'   is silently skipped (with a warning) if no path is found or Node.js is
#'   not installed.
#' @param max_new_tasks Integer(1) or `NULL`. Maximum number of *new* tasks
#'   (tasks that have at least one unseen (strategy, trial) combination) to
#'   process in this run.  When `NULL` (default) all tasks are processed.
#'   Useful when the available API quota is known in advance: set
#'   `max_new_tasks = floor(remaining_requests / n_strategies)` and combine
#'   with `resume = TRUE` so tomorrow's run continues where today's left off.
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
#'     \item{`context_tokens`}{Integer. API-reported input token count when
#'       available; falls back to `tokenizers::count_words()` or `nchar/4`.}
#'     \item{`response_tokens`}{Integer. API-reported output token count;
#'       same fallback chain as `context_tokens`.}
#'     \item{`total_tokens`}{Integer.}
#'     \item{`latency_sec`}{Numeric.}
#'     \item{`hallucination_count`}{Integer.}
#'     \item{`hallucination_details`}{List column (character vectors).}
#'     \item{`syntax_valid`}{Logical.}
#'     \item{`runs_without_error`}{Logical.}
#'     \item{`retrieved_n`}{Integer. Nodes retrieved by rrlmgraph strategies;
#'       `0L` for non-graph strategies.}
#'     \item{`ndcg5`}{Numeric. NDCG\@5 against `ground_truth_nodes` for
#'       rrlmgraph strategies; `NA_real_` otherwise.}
#'     \item{`ndcg10`}{Numeric. NDCG\@10; same conditions as `ndcg5`.}
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
  rate_limit_delay = 6,
  strategies = c(
    "rrlmgraph_tfidf",
    "rrlmgraph_ollama",
    "full_files",
    "term_overlap",
    "bm25_retrieval",
    "no_context",
    "rrlmgraph_mcp"
  ),
  resume = FALSE,
  mcp_server_dir = NULL,
  max_new_tasks = NULL,
  .dry_run = FALSE
) {
  llm_provider <- match.arg(llm_provider)
  set.seed(seed)

  # Fail fast on rate-limit responses instead of waiting for Retry-After
  # (which can be days when the daily quota is exhausted).
  old_max_tries <- getOption("ellmer_max_tries", default = 3L)
  on.exit(options(ellmer_max_tries = old_max_tries), add = TRUE)
  options(ellmer_max_tries = 1L)

  # Validate strategies
  allowed_strategies <- c(
    "rrlmgraph_tfidf",
    "rrlmgraph_ollama",
    "rrlmgraph_mcp",
    "full_files",
    "term_overlap",
    "bm25_retrieval",
    "no_context",
    "random_k"
  )
  unknown <- setdiff(strategies, allowed_strategies)
  if (length(unknown)) {
    stop("Unknown strategies: ", paste(unknown, collapse = ", "))
  }

  # Skip Ollama-backed strategy when the local daemon is not running.
  # In CI the Ollama daemon is started by the workflow before this script runs;
  # the guard remains as a safety net in case setup failed.
  # readers of the published report. (see bench#18)
  if ("rrlmgraph_ollama" %in% strategies && !rrlmgraph::ollama_available()) {
    cli::cli_warn(c(
      "!" = "Ollama daemon unavailable -- skipping {.val rrlmgraph_ollama} strategy.",
      "i" = "Results will be collected for {length(strategies) - 1L} strategies."
    ))
    strategies <- setdiff(strategies, "rrlmgraph_ollama")
  }

  # ---- MCP server setup (rrlmgraph_mcp strategy, bench#30) ---------------
  # Resolve mcp_server_dir from parameter, then env var RRLMGRAPH_MCP_DIR.
  # A fresh server is started per task (not globally) so that each task gets
  # a SQLite export of *its own* graph.  We do a preflight check here to
  # drop the strategy early when Node.js or the built dist is missing.
  resolved_mcp_dir <- NULL
  if ("rrlmgraph_mcp" %in% strategies) {
    candidate_dir <- if (!is.null(mcp_server_dir) && nzchar(mcp_server_dir)) {
      mcp_server_dir
    } else {
      Sys.getenv("RRLMGRAPH_MCP_DIR", unset = "")
    }
    if (!nzchar(candidate_dir)) {
      cli::cli_warn(c(
        "!" = "No MCP server directory -- skipping {.val rrlmgraph_mcp} strategy.",
        "i" = "Set {.envvar RRLMGRAPH_MCP_DIR} or pass {.arg mcp_server_dir} to {.fn run_full_benchmark}."
      ))
      strategies <- setdiff(strategies, "rrlmgraph_mcp")
    } else if (!nzchar(Sys.which("node"))) {
      cli::cli_warn(c(
        "!" = "Node.js not found -- skipping {.val rrlmgraph_mcp} strategy.",
        "i" = "Install Node.js to enable the MCP strategy."
      ))
      strategies <- setdiff(strategies, "rrlmgraph_mcp")
    } else {
      index_js <- file.path(candidate_dir, "dist", "index.js")
      if (!file.exists(index_js)) {
        cli::cli_warn(c(
          "!" = "rrlmgraph-mcp dist not found at {.path {index_js}} -- skipping {.val rrlmgraph_mcp}.",
          "i" = "Run {.code npm run build} in the MCP directory."
        ))
        strategies <- setdiff(strategies, "rrlmgraph_mcp")
      } else {
        resolved_mcp_dir <- candidate_dir
        cli::cli_inform(c(
          "v" = "rrlmgraph-mcp: per-task server mode enabled ({.path {resolved_mcp_dir}})."
        ))
      }
    }
  }

  # ---- Load task definitions ------------------------------------------
  task_files <- list.files(tasks_dir, pattern = "\\.json$", full.names = TRUE)
  if (!length(task_files)) {
    stop("No task JSON files found in: ", tasks_dir)
  }

  tasks <- lapply(task_files, function(fp) {
    jsonlite::fromJSON(fp, simplifyVector = TRUE)
  })
  # Shuffle execution order so that quota exhaustion hits different tasks on
  # different runs, rather than always truncating the last task alphabetically.
  tasks <- tasks[sample(length(tasks))]
  task_ids <- vapply(tasks, `[[`, character(1L), "task_id")

  n_combos <- length(task_ids) * length(strategies) * n_trials

  # ---- Resume from partial checkpoint ----------------------------------
  # 30 tasks x 7 strategies x 1 trial = 210 calls = daily quota ceiling.
  # (rrlmgraph_ollama uses nomic-embed-text for embeddings only; LLM scoring
  #  still goes through the llm_provider.  Ollama auto-skips if daemon is down.)
  # Without resume a quota-exhausted run permanently loses the last N rows.
  partial_path <- sub("\\.rds$", "_partial.rds", output_path)
  completed_rows <- list()
  skip_keys <- character(0L)

  # Current package versions -- used for stamp comparison on resume
  cur_rrlmgraph_ver <- tryCatch(
    as.character(utils::packageVersion("rrlmgraph")),
    error = function(e) NA_character_
  )
  cur_bench_ver <- tryCatch(
    as.character(utils::packageVersion("rrlmgraphbench")),
    error = function(e) NA_character_
  )

  if (isTRUE(resume) && file.exists(partial_path)) {
    prev <- tryCatch(readRDS(partial_path), error = function(e) NULL)
    if (!is.null(prev) && nrow(prev) > 0L) {
      # ---- Version integrity check -----------------------------------------
      # If the partial was created with a different rrlmgraph/rrlmgraphbench
      # version, its rows may reflect pre-fix behaviour (e.g. ndcg always NA,
      # wrong scores).  Warn loudly so the user can delete the partial and
      # restart clean if needed.  We continue rather than abort so that
      # automated CI runs can still accumulate new rows and a human reviews.
      stamp <- attr(prev, ".bench_stamp")
      if (!is.null(stamp)) {
        if (
          !is.null(stamp$rrlmgraph_version) &&
            !is.na(cur_rrlmgraph_ver) &&
            stamp$rrlmgraph_version != cur_rrlmgraph_ver
        ) {
          cli::cli_warn(c(
            "!" = paste0(
              "Partial checkpoint was created with rrlmgraph ",
              stamp$rrlmgraph_version,
              " but current version is ",
              cur_rrlmgraph_ver,
              "."
            ),
            "i" = "Previous rows may reflect pre-fix behaviour. Delete {.path {partial_path}} to restart clean."
          ))
        }
        if (
          !is.null(stamp$rrlmgraphbench_version) &&
            !is.na(cur_bench_ver) &&
            stamp$rrlmgraphbench_version != cur_bench_ver
        ) {
          cli::cli_warn(c(
            "!" = paste0(
              "Partial checkpoint was created with rrlmgraphbench ",
              stamp$rrlmgraphbench_version,
              " but current version is ",
              cur_bench_ver,
              "."
            ),
            "i" = "Delete {.path {partial_path}} to restart clean if scoring logic changed."
          ))
        }
      }

      # Only treat non-NA rows as done; NA rows (rate-limit failures etc.)
      # are re-queued so the next run can fill them in automatically.
      non_na_mask <- !is.na(prev$score)
      prev_done <- prev[non_na_mask, , drop = FALSE]
      prev_retry <- prev[!non_na_mask, , drop = FALSE]
      n_retry <- nrow(prev_retry)

      skip_keys <- paste(
        prev_done$task_id,
        prev_done$strategy,
        as.integer(prev_done$trial),
        sep = "|"
      )
      completed_rows <- lapply(
        seq_len(nrow(prev_done)),
        function(i) prev_done[i, , drop = FALSE]
      )
      message(sprintf(
        "[rrlmgraphbench] Resume: %d completed row(s) loaded; %d new run(s) remaining%s.",
        length(skip_keys),
        n_combos - length(skip_keys),
        if (n_retry > 0L) {
          sprintf(" (%d NA row(s) will be retried)", n_retry)
        } else {
          ""
        }
      ))
    }
  }
  n_new <- n_combos - length(skip_keys)

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

  # Reset quota-exhaustion signal from any prior run in this R session, then
  # initialise the counters used by the max_new_tasks gate (bench#37).
  Sys.setenv(RRLMGRAPHBENCH_QUOTA_EXHAUSTED = "")
  quota_hit <- FALSE
  consecutive_na <- 0L
  new_tasks_started <- 0L

  t0 <- proc.time()[["elapsed"]]
  results <- list()
  run_idx <- 0L

  for (task in tasks) {
    # ---- Quota-aware task gating (bench#37) --------------------------------
    # Determine whether any (strategy, trial) combinations for this task still
    # need to be run.  If max_new_tasks is set (from a pre-run quota check) and
    # we have already started that many new tasks today, stop before the graph
    # build or MCP server start -- avoiding expensive wasted work.
    task_has_new_work <- any(vapply(
      strategies,
      function(s) {
        any(vapply(
          seq_len(n_trials),
          function(t) {
            !paste(task$task_id, s, as.integer(t), sep = "|") %in% skip_keys
          },
          logical(1L)
        ))
      },
      logical(1L)
    ))
    if (task_has_new_work) {
      if (!is.null(max_new_tasks) && new_tasks_started >= max_new_tasks) {
        message(sprintf(
          paste0(
            "[rrlmgraphbench] max_new_tasks=%d reached (%d/%d tasks processed)",
            " -- stopping to stay within API quota.",
            " Set resume=TRUE to continue in the next run."
          ),
          max_new_tasks,
          new_tasks_started,
          length(tasks)
        ))
        break
      }
      new_tasks_started <- new_tasks_started + 1L
    }

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

    # ---- Per-task MCP server (bench#30) ----------------------------------
    # Export this task's tfidf graph to a temp SQLite file and start a fresh
    # MCP server pointing to it.  The server is killed after all trials for
    # this task complete, and the temp file is deleted.
    task_mcp_state <- NULL
    mcp_tmp_db <- NULL
    if (
      "rrlmgraph_mcp" %in% strategies && !is.null(resolved_mcp_dir) && !.dry_run
    ) {
      if (!is.null(graph_tfidf)) {
        mcp_tmp_db <- tempfile(fileext = ".sqlite")
        export_ok <- tryCatch(
          {
            rrlmgraph::export_to_sqlite(graph_tfidf, mcp_tmp_db)
            TRUE
          },
          error = function(e) {
            cli::cli_warn(c(
              "!" = "export_to_sqlite failed for {task$task_id}: {conditionMessage(e)}",
              "i" = "rrlmgraph_mcp will yield empty context for this task."
            ))
            FALSE
          }
        )
        if (export_ok) {
          task_mcp_state <- mcp_start_server(
            mcp_dir = resolved_mcp_dir,
            project_path = project_path,
            db_path = mcp_tmp_db
          )
          if (is.null(task_mcp_state)) {
            cli::cli_warn(c(
              "!" = "MCP server failed to start for {task$task_id}.",
              "i" = "rrlmgraph_mcp will yield empty context for this task."
            ))
          }
        }
      }
    }

    for (strategy in strategies) {
      for (trial in seq_len(n_trials)) {
        combo_key <- paste(
          task$task_id,
          strategy,
          as.integer(trial),
          sep = "|"
        )
        if (combo_key %in% skip_keys) {
          next
        }
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
          rate_limit_delay = rate_limit_delay,
          mcp_state = task_mcp_state,
          .dry_run = .dry_run
        )
        results[[length(results) + 1L]] <- result_row

        elapsed <- proc.time()[["elapsed"]] - t0
        per_run <- elapsed / run_idx
        remaining <- (n_new - run_idx) * per_run
        message(sprintf(
          "[%d/%d new] task=%s strategy=%-20s trial=%d | score=%.3f | est. %.0fs",
          run_idx,
          n_new,
          task$task_id,
          strategy,
          trial,
          result_row$score,
          remaining
        ))

        # Track consecutive NA scores to detect quota exhaustion.
        # run_single returns NA on 429 after one 60-s retry; three
        # consecutive NAs means the daily quota is truly exhausted.
        if (is.na(result_row$score)) {
          consecutive_na <- consecutive_na + 1L
          if (consecutive_na >= 3L) {
            message(
              "[rrlmgraphbench] 3 consecutive NA scores -- ",
              "quota likely exhausted, stopping.  ",
              "Run with resume=TRUE to continue tomorrow."
            )
            Sys.setenv(RRLMGRAPHBENCH_QUOTA_EXHAUSTED = "true")
            quota_hit <- TRUE
            break # break trial loop
          }
        } else {
          consecutive_na <- 0L
        }
      }
      if (quota_hit) break # break strategy loop
    }

    # ---- Checkpoint save after each task block ----------------------------
    # Merges previously loaded rows (resume) with new rows so the partial
    # file always reflects full combined progress across all runs.
    partial_df <- do.call(
      rbind,
      c(
        completed_rows,
        lapply(results, as.data.frame, stringsAsFactors = FALSE)
      )
    )
    rownames(partial_df) <- NULL
    # Embed version stamp so that resume can detect stale checkpoints (#b30)
    attr(partial_df, ".bench_stamp") <- list(
      rrlmgraph_version = cur_rrlmgraph_ver,
      rrlmgraphbench_version = cur_bench_ver,
      created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    )
    tryCatch(
      saveRDS(partial_df, partial_path),
      error = function(e) {
        warning(
          "[rrlmgraphbench] Could not write partial checkpoint: ",
          e$message
        )
      }
    )

    # ---- Per-task MCP cleanup -------------------------------------------
    if (!is.null(task_mcp_state)) {
      tryCatch(task_mcp_state$proc$kill(), error = function(e) NULL)
      task_mcp_state <- NULL
    }
    if (!is.null(mcp_tmp_db)) {
      unlink(mcp_tmp_db)
      mcp_tmp_db <- NULL
    }
    if (quota_hit) break # break task loop -- partial checkpoint already saved above
  }

  all_results <- do.call(
    rbind,
    c(completed_rows, lapply(results, as.data.frame, stringsAsFactors = FALSE))
  )
  rownames(all_results) <- NULL

  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(all_results, output_path)
  message("[rrlmgraphbench] Results saved to: ", output_path)

  # ---- Write benchmark_meta.json provenance record (#24) ---------------
  default_models_meta <- c(
    github = "gpt-4.1-mini",
    openai = "gpt-4.1-mini",
    anthropic = "claude-3-5-haiku-latest",
    ollama = "llama3.2"
  )
  resolved_model_meta <- if (!is.null(llm_model)) {
    llm_model
  } else {
    default_models_meta[[llm_provider]]
  }
  meta <- list(
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    rrlmgraph_version = as.character(utils::packageVersion("rrlmgraph")),
    rrlmgraphbench_version = as.character(utils::packageVersion(
      "rrlmgraphbench"
    )),
    rrlmgraphbench_sha = tryCatch(
      system2(
        "git",
        c("rev-parse", "--short", "HEAD"),
        stdout = TRUE,
        stderr = FALSE
      )[1L],
      error = function(e) NA_character_
    ),
    n_tasks = length(task_ids),
    n_trials = n_trials,
    n_strategies = length(strategies),
    strategies = as.list(strategies),
    llm_provider = llm_provider,
    llm_model = resolved_model_meta
  )
  meta_path <- file.path(dirname(output_path), "benchmark_meta.json")
  tryCatch(
    {
      writeLines(
        jsonlite::toJSON(meta, auto_unbox = TRUE, pretty = TRUE),
        meta_path
      )
      message("[rrlmgraphbench] Benchmark metadata written to: ", meta_path)
    },
    error = function(e) {
      warning("Could not write benchmark_meta.json: ", conditionMessage(e))
    }
  )

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

# ---- Token estimation helper (mirrors rrlmgraph::.count_tokens) -------
#' @keywords internal
.bench_estimate_tokens <- function(text) {
  if (!nzchar(text)) {
    return(0L)
  }
  if (requireNamespace("tokenizers", quietly = TRUE)) {
    words <- tokenizers::tokenize_words(
      text,
      lowercase = FALSE,
      simplify = TRUE
    )
    as.integer(ceiling(length(words) * 1.3))
  } else {
    as.integer(ceiling(nchar(text) / 3.5))
  }
}

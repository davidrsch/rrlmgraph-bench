#' Run the full rrlmgraph benchmark
#'
#' Evaluates seven retrieval strategies across every task in `tasks_dir`
#' using `n_trials` independent trials each, and persists the combined
#' results to `output_path`.
#'
#' ## Strategies
#' | Label | Description |
#' |---|---|
#' | `rrlmgraph_tfidf` | rrlmgraph with TF-IDF node embeddings |
#' | `rrlmgraph_ollama` | rrlmgraph with Ollama-backed embeddings |
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
    "term_overlap",
    "bm25_retrieval",
    "no_context",
    "random_k"
  )

  # Skip Ollama-backed strategy when the local daemon is not running.
  # In CI Ollama is never available, so without this guard the
  # rrlmgraph_ollama results are identical to no_context and mislead
  # readers of the published report. (see bench#18)
  if (!rrlmgraph::ollama_available()) {
    cli::cli_warn(c(
      "!" = "Ollama daemon unavailable -- skipping {.val rrlmgraph_ollama} strategy.",
      "i" = "Results will be collected for {length(strategies) - 1L} strategies."
    ))
    strategies <- setdiff(strategies, "rrlmgraph_ollama")
  }

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
          rate_limit_delay = rate_limit_delay,
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

    # ---- Checkpoint save after each task block ----------------------------
    # Allows resuming a partial run if the process is interrupted (bench#35).
    partial_path <- sub("\\.rds$", "_partial.rds", output_path)
    partial_df <- do.call(
      rbind,
      lapply(results[seq_len(run_idx)], as.data.frame, stringsAsFactors = FALSE)
    )
    rownames(partial_df) <- NULL
    tryCatch(
      saveRDS(partial_df, partial_path),
      error = function(e) {
        warning(
          "[rrlmgraphbench] Could not write partial checkpoint: ",
          e$message
        )
      }
    )
  }

  all_results <- do.call(
    rbind,
    lapply(results, as.data.frame, stringsAsFactors = FALSE)
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

build_context <- function(
  strategy,
  task,
  graph_tfidf,
  graph_ollama,
  source_files,
  budget_tokens = 6000L
) {
  node_ids <- character(0L) # populated by <<- inside rrlmgraph branches

  chunks <- switch(
    strategy,
    rrlmgraph_tfidf = {
      if (is.null(graph_tfidf)) {
        character(0L)
      } else {
        tryCatch(
          {
            ctx <- rrlmgraph::query_context(
              graph_tfidf,
              task$description,
              seed_node = task$seed_node
            )
            node_ids <<- if (!is.null(ctx$nodes)) {
              ctx$nodes$node_id
            } else {
              character(0L)
            }
            if (is.null(ctx$context_string)) {
              character(0L)
            } else {
              ctx$context_string
            }
          },
          error = function(e) character(0L)
        )
      }
    },
    rrlmgraph_ollama = {
      if (is.null(graph_ollama)) {
        character(0L)
      } else {
        tryCatch(
          {
            ctx <- rrlmgraph::query_context(
              graph_ollama,
              task$description,
              seed_node = task$seed_node
            )
            node_ids <<- if (!is.null(ctx$nodes)) {
              ctx$nodes$node_id
            } else {
              character(0L)
            }
            if (is.null(ctx$context_string)) {
              character(0L)
            } else {
              ctx$context_string
            }
          },
          error = function(e) character(0L)
        )
      }
    },
    full_files = {
      # Admit complete files (largest first) until the token budget is
      # exhausted.  Never truncate mid-file: a partial file is syntactically
      # invalid R and makes this baseline unfairly weak on large projects.
      # Fixes: rrlmgraph-bench#33
      if (!length(source_files)) {
        character(0L)
      } else {
        file_texts <- vapply(source_files, read_lines_safe, character(1L))
        file_costs <- vapply(file_texts, .bench_estimate_tokens, integer(1L))
        # Sort by size descending so we fill the budget with fewer large files
        ord <- order(file_costs, decreasing = TRUE)
        admitted <- character(0L)
        tokens_used <- 0L
        for (i in ord) {
          cost <- file_costs[[i]]
          if (tokens_used + cost <= budget_tokens) {
            admitted <- c(admitted, file_texts[[i]])
            tokens_used <- tokens_used + cost
          }
          # Do not skip smaller files just because a large one didn't fit;
          # continue to fill remaining budget.
        }
        admitted
      }
    },
    term_overlap = {
      term_overlap_retrieve(task$description, source_files)
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
        character(0L)
      } else {
        vapply(sample(source_files, k), read_lines_safe, character(1L))
      }
    },
    stop("Unknown strategy: ", strategy)
  )

  list(chunks = chunks, node_ids = node_ids)
}

read_lines_safe <- function(path) {
  tryCatch(
    paste(readLines(path, warn = FALSE), collapse = "\n"),
    error = function(e) ""
  )
}

bm25_retrieve <- function(query, files, k = 5L, k1 = 1.5, b = 0.75) {
  # True BM25 (Best Match 25) -- Robertson & Zaragoza (2009) smooth variant.
  # IDF-weighted, length-normalised term frequency scoring; pure base R.
  if (!length(files)) {
    return(character(0L))
  }
  query_terms <- unique(tolower(strsplit(query, "\\W+")[[1L]]))
  query_terms <- query_terms[nzchar(query_terms)]
  if (!length(query_terms)) {
    return(term_overlap_retrieve(query, files, k))
  }

  doc_words <- lapply(files, function(fp) {
    w <- strsplit(tolower(read_lines_safe(fp)), "\\W+")[[1L]]
    w[nzchar(w)]
  })
  doc_lengths <- vapply(doc_words, length, integer(1L))
  avgdl <- mean(doc_lengths)
  if (avgdl == 0) {
    return(term_overlap_retrieve(query, files, k))
  }
  N <- length(files)

  tf_list <- lapply(doc_words, table)

  df_vec <- vapply(
    query_terms,
    function(tm) {
      sum(vapply(tf_list, function(tf) tm %in% names(tf), logical(1L)))
    },
    integer(1L)
  )

  idf_vec <- log((N - df_vec + 0.5) / (df_vec + 0.5) + 1)

  scores <- vapply(
    seq_along(files),
    function(i) {
      tf <- tf_list[[i]]
      dl <- doc_lengths[[i]]
      sc <- 0
      for (j in seq_along(query_terms)) {
        tm <- query_terms[[j]]
        tf_val <- if (tm %in% names(tf)) as.integer(tf[[tm]]) else 0L
        bm_tf <- (tf_val * (k1 + 1)) /
          (tf_val + k1 * (1 - b + b * dl / avgdl))
        sc <- sc + idf_vec[[j]] * bm_tf
      }
      sc
    },
    numeric(1L)
  )

  top_k <- head(order(scores, decreasing = TRUE), k)
  vapply(files[top_k], read_lines_safe, character(1L))
}
term_overlap_retrieve <- function(query, files, k = 5L) {
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

# ---- NDCG helper (#27) ----------------------------------------------
#' @keywords internal
.ndcg_at_k <- function(rank_vec, k) {
  # rank_vec: integer positions of GT nodes in retrieved list (NA = not retrieved)
  # Returns NDCG@k in [0, 1] or NA_real_ when no GT nodes are present.
  n_rel <- sum(!is.na(rank_vec))
  if (n_rel == 0L) {
    return(NA_real_)
  }
  hits <- rank_vec[!is.na(rank_vec) & rank_vec <= k]
  dcg <- sum(1 / log2(hits + 1))
  idcg <- sum(1 / log2(seq_len(min(n_rel, k)) + 1))
  if (idcg == 0) NA_real_ else dcg / idcg
}

# ---- AST-diff scorer (#28) ------------------------------------------
#' @keywords internal
ast_diff_score <- function(response_code, ground_truth_code) {
  # Returns a score in [0, 1] based on structural AST similarity.
  # Metric: 0.6 * call-name Jaccard + 0.4 * word-token Jaccard.
  extract_calls <- function(code) {
    ast <- tryCatch(
      parse(text = code, keep.source = FALSE),
      error = function(e) NULL
    )
    if (is.null(ast)) {
      return(character(0L))
    }
    calls <- character(0L)
    walk <- function(expr) {
      if (is.call(expr)) {
        fn <- tryCatch(as.character(expr[[1L]]), error = function(e) NULL)
        if (length(fn) == 1L && nzchar(fn)) {
          calls <<- c(calls, fn)
        }
        lapply(as.list(expr[-1L]), walk)
      } else if (is.recursive(expr)) {
        lapply(as.list(expr), walk)
      }
    }
    lapply(as.list(ast), walk)
    unique(calls)
  }

  jaccard <- function(a, b) {
    uni <- length(union(a, b))
    if (uni == 0L) 0 else length(intersect(a, b)) / uni
  }

  call_j <- jaccard(
    extract_calls(response_code),
    extract_calls(ground_truth_code)
  )

  word_tokens <- function(x) {
    w <- unique(strsplit(tolower(x), "\\W+")[[1L]])
    w[nzchar(w)]
  }
  tok_j <- jaccard(word_tokens(response_code), word_tokens(ground_truth_code))

  0.6 * call_j + 0.4 * tok_j
}
score_response <- function(response_code, task, source_files = NULL) {
  # Rubric: syntax (0.25) + node presence / AST-diff (0.45) + runs (0.30)
  # Rationale: syntax_ok is nearly subsumed by runs_ok (code that runs also
  # parses), so its weight is reduced in favour of the primary quality signal
  # (nodes_score). Weights sum to 1.0. See rrlmgraph-bench#32.
  syntax_ok <- tryCatch(
    {
      parse(text = response_code, keep.source = FALSE)
      TRUE
    },
    error = function(e) FALSE
  )

  nodes_score <- 0
  # Choose scoring method for node-presence component (#28).
  # Tasks with evaluation_method = "ast_diff" use structural AST similarity;
  # others use the regex word-boundary approach.
  use_ast <- isTRUE(identical(task$evaluation_method, "ast_diff")) &&
    !is.null(task$ground_truth_file) &&
    nzchar(as.character(task$ground_truth_file))

  if (use_ast) {
    gt_rel <- sub("^inst/", "", task$ground_truth_file)
    gt_path <- system.file(gt_rel, package = "rrlmgraphbench")
    if (nzchar(gt_path) && file.exists(gt_path)) {
      gt_code <- paste(readLines(gt_path, warn = FALSE), collapse = "\n")
      nodes_score <- ast_diff_score(response_code, gt_code)
    } else {
      use_ast <- FALSE # file not found -- fall through to regex
    }
  }

  if (!use_ast && length(task$ground_truth_nodes) > 0L) {
    hits <- vapply(
      task$ground_truth_nodes,
      function(n) {
        # ground_truth_nodes use "pkg::fn" rrlmgraph convention; strip the
        # namespace prefix before searching so bare function names in the
        # LLM response (e.g. "split_data.data.frame") still match.
        bare_n <- sub("^[^:]+::", "", n)
        # Use word-boundary regex to avoid false positives from partial
        # name matches (e.g. "split_data_old" matching "split_data").
        # Escape regex metacharacters in bare_n (e.g. "." in S3 methods).
        esc_n <- gsub(
          "([.+*?\\[\\^\\]$(){}=!<>|:\\-#])",
          "\\\\\\1",
          bare_n,
          perl = TRUE
        )
        pattern <- paste0("(?<![A-Za-z0-9._])", esc_n, "(?![A-Za-z0-9._])")
        grepl(pattern, response_code, perl = TRUE)
      },
      logical(1L)
    )
    nodes_score <- mean(hits)
  }

  runs_ok <- tryCatch(
    {
      # Evaluate in a child of globalenv() so that calls using installed
      # packages (via :: or library()) work.  Source project files first so
      # the LLM's use of project-internal functions can also be tested.
      # Previously used baseenv() which is missing almost every package and
      # caused runs_ok to be systematically FALSE for all realistic code.
      env <- new.env(parent = globalenv())
      if (!is.null(source_files) && length(source_files) > 0L) {
        for (sf in source_files) {
          tryCatch(source(sf, local = env, echo = FALSE), error = function(e) {
            NULL
          })
        }
      }
      eval(parse(text = response_code), envir = env)
      TRUE
    },
    error = function(e) FALSE
  )

  total <- 0.25 * syntax_ok + 0.45 * nodes_score + 0.30 * runs_ok
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
  rate_limit_delay = 6,
  .dry_run
) {
  ctx_result <- build_context(
    strategy,
    task,
    graph_tfidf,
    graph_ollama,
    source_files
  )
  ctx_chunks <- ctx_result$chunks
  retrieved_ids <- ctx_result$node_ids
  ctx_text <- paste(ctx_chunks, collapse = "\n")

  # NDCG pre-computation --------------------------------------------------
  gt_nodes <- if (!is.null(task$ground_truth_nodes)) {
    task$ground_truth_nodes
  } else {
    character(0L)
  }
  rank_vec <- if (length(retrieved_ids) && length(gt_nodes)) {
    match(gt_nodes, retrieved_ids)
  } else {
    rep(NA_integer_, length(gt_nodes))
  }
  ndcg5 <- .ndcg_at_k(rank_vec, 5L)
  ndcg10 <- .ndcg_at_k(rank_vec, 10L)

  # Token count defaults (nchar/4 heuristic -- overwritten below if API available)
  context_tokens <- nchar(ctx_text) %/% 4L
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
      github = "gpt-4.1-mini",
      openai = "gpt-4.1-mini",
      anthropic = "claude-3-5-haiku-latest",
      ollama = "llama3.2"
    )
    resolved_model <- if (!is.null(llm_model)) {
      llm_model
    } else {
      default_models[[llm_provider]]
    }
    llm_result <- tryCatch(
      {
        chat <- if (llm_provider == "github") {
          # In CI GITHUB_PAT is set by the workflow env block.
          # For local use, GITHUB_TOKEN or GITHUB_PAT must be set.
          gh_pat <- Sys.getenv("GITHUB_PAT", Sys.getenv("GITHUB_TOKEN", ""))
          if (!nzchar(gh_pat)) {
            stop("Set GITHUB_PAT or GITHUB_TOKEN to use llm_provider='github'")
          }
          cred_fn <- (function(k) function() k)(gh_pat)
          ellmer::chat_openai_compatible(
            base_url = "https://models.github.ai/inference/",
            model = resolved_model,
            credentials = cred_fn
          )
        } else {
          chat_fn_name <- switch(
            llm_provider,
            openai = "chat_openai",
            anthropic = "chat_anthropic",
            ollama = "chat_ollama"
          )
          chat_fn <- getExportedValue("ellmer", chat_fn_name)
          chat_fn(model = resolved_model)
        }
        chat$chat(prompt)
      },
      error = function(e) {
        msg <- conditionMessage(e)
        # 429 / rate-limit: wait 60s and retry once (bench#35)
        if (grepl("429|rate.limit|quota", msg, ignore.case = TRUE)) {
          message(
            "[run_single] Rate-limit hit (429) — waiting 60s before retry..."
          )
          Sys.sleep(60)
          tryCatch(
            {
              chat2 <- if (llm_provider == "github") {
                gh_pat2 <- Sys.getenv(
                  "GITHUB_PAT",
                  Sys.getenv("GITHUB_TOKEN", "")
                )
                cred_fn2 <- (function(k) function() k)(gh_pat2)
                ellmer::chat_openai_compatible(
                  base_url = "https://models.github.ai/inference/",
                  model = resolved_model,
                  credentials = cred_fn2
                )
              } else {
                chat_fn2 <- getExportedValue(
                  "ellmer",
                  switch(
                    llm_provider,
                    openai = "chat_openai",
                    anthropic = "chat_anthropic",
                    ollama = "chat_ollama"
                  )
                )
                chat_fn2(model = resolved_model)
              }
              chat2$chat(prompt)
            },
            error = function(e2) {
              message("[run_single] Retry failed: ", conditionMessage(e2))
              NA_character_
            }
          )
        } else {
          message("[run_single] LLM call failed: ", msg)
          ""
        }
      }
    )
    # Rate-limit polite delay between API calls (bench#35)
    if (!.dry_run && rate_limit_delay > 0) {
      Sys.sleep(rate_limit_delay)
    }
    latency_sec <- proc.time()[["elapsed"]] - t1
    response_code <- if (is.na(llm_result)) {
      # 429 retry exhausted — mark trial as failed
      score <- NA_real_
      llm_result
    } else {
      llm_result
    }

    # ---- Token counts: API-reported > tokenizers > nchar/4 (#26) ----------
    api_tokens <- tryCatch(
      vapply(chat$last_turn()@tokens, as.integer, integer(1L)),
      error = function(e) NULL
    )
    if (!is.null(api_tokens) && length(api_tokens) >= 2L) {
      context_tokens <- api_tokens[[1L]]
      response_tokens <- api_tokens[[2L]]
    } else if (requireNamespace("tokenizers", quietly = TRUE)) {
      count_tok <- function(x) {
        as.integer(length(tokenizers::tokenize_words(x)[[1L]]))
      }
      context_tokens <- count_tok(ctx_text)
      response_tokens <- count_tok(response_code)
    } else {
      response_tokens <- nchar(response_code) %/% 4L
    }

    rubric <- score_response(response_code, task, source_files = source_files)
    if (!is.na(response_code)) {
      score <- rubric$score
      syntax_valid <- rubric$syntax_valid
      runs_ok <- rubric$runs_without_error
    }

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
    runs_without_error = runs_ok,
    retrieved_n = as.integer(length(retrieved_ids)),
    ndcg5 = ndcg5,
    ndcg10 = ndcg10
  )
}

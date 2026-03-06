# ---- Single benchmark run executor -------------------------------------
# run_single() executes one (task, strategy, trial) combination:
#   1. Retrieve context via build_context()
#   2. Format a prompt and call the LLM via ellmer
#   3. Score the response via score_response()
# Returns a named list compatible with as.data.frame().

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
  mcp_state = NULL,
  .dry_run
) {
  ctx_result <- build_context(
    strategy,
    task,
    graph_tfidf,
    graph_ollama,
    source_files,
    mcp_state = mcp_state
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
          gh_pat <- Sys.getenv(
            "GITHUB_PAT",
            Sys.getenv("GITHUB_TOKEN", "")
          )
          if (!nzchar(gh_pat)) {
            stop(
              "Set GITHUB_PAT or GITHUB_TOKEN to use llm_provider='github'"
            )
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
        # Bypass API call when quota was already exhausted earlier in this run.
        if (Sys.getenv("RRLMGRAPHBENCH_QUOTA_EXHAUSTED") == "true") NA_character_
        else chat$chat(prompt)
      },
      error = function(e) {
        msg <- conditionMessage(e)
        # 429 / rate-limit: wait 60s and retry once (bench#35).
        # GitHub Models returns "Too many requests" plain-text on 429;
        # httr2 req_error() then throws a JSON-parse error whose message
        # still contains the original body text -- match it explicitly.
        is_rate_limit <- grepl(
          "429|rate.limit|quota|too many request",
          msg,
          ignore.case = TRUE
        )
        if (is_rate_limit) {
          # Signal quota exhaustion so the outer benchmark loop stops after
          # the current task block.  Do NOT sleep or retry: the daily quota
          # resets in ~24 h, so retrying is always futile and a 60 s sleep
          # per remaining call would block the runner for hours.
          Sys.setenv(RRLMGRAPHBENCH_QUOTA_EXHAUSTED = "true")
          message(
            "[run_single] Quota exhausted (429) -- aborting retries; ",
            "run will resume from checkpoint tomorrow."
          )
          NA_character_
        } else {
          message("[run_single] LLM call failed: ", msg)
          ""
        }
      }
    )
    # Rate-limit polite delay between API calls (bench#35).
    # Skip the delay when quota is exhausted -- no more real API calls will
    # be made, so sleeping would just burn CI minutes to no effect.
    if (
      !.dry_run &&
        rate_limit_delay > 0 &&
        Sys.getenv("RRLMGRAPHBENCH_QUOTA_EXHAUSTED") != "true"
    ) {
      Sys.sleep(rate_limit_delay)
    }
    latency_sec <- proc.time()[["elapsed"]] - t1
    response_code <- if (
      is.na(llm_result) ||
        !nzchar(trimws(as.character(llm_result)))
    ) {
      # NA  = 429 retry exhausted
      # "" = undetected error (e.g. JSON-parse failure hiding a rate-limit)
      # Either way there is no usable LLM response -- mark trial as failed.
      score <- NA_real_
      NA_character_
    } else {
      # Strip markdown code fences (```r ... ```) that LLMs add to their
      # responses even when asked for raw code.  Without this, parse() fails
      # on every response and syntax_valid is always FALSE (bench#36).
      strip_code_fences(as.character(llm_result))
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

    rubric <- score_response(
      response_code,
      task,
      source_files = source_files
    )
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

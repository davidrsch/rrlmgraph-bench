# ---- LLM output scoring helpers ----------------------------------------
# format_prompt()    -- assemble the prompt sent to the LLM
# .ndcg_at_k()       -- NDCG@k metric
# ast_diff_score()   -- structural AST similarity
# strip_code_fences() -- remove markdown ``` fences
# score_response()   -- combined rubric scorer (syntax + nodes + runs)

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
        fn <- tryCatch(as.character(expr[[1L]]), error = function(e) {
          NULL
        })
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

# Strip markdown code fences that LLMs add around their responses.
# Handles ```r, ```R, ``` and any other language tag.
# Returns the original string unchanged if no fences are detected.
strip_code_fences <- function(code) {
  if (
    !is.character(code) ||
      length(code) != 1L ||
      is.na(code) ||
      !nzchar(trimws(code))
  ) {
    return(code)
  }
  if (!grepl("```", code, fixed = TRUE)) {
    return(code)
  }
  # Match a fenced block: opening ``` with optional language tag, then
  # any content (including newlines), then closing ```.
  m <- regmatches(
    code,
    regexpr("(?s)```[A-Za-z0-9]*\\s*\n?(.*?)\n?\\s*```", code, perl = TRUE)
  )
  if (length(m) == 0L) {
    return(code)
  }
  # Remove the opening fence line and the closing fence
  stripped <- sub("^```[A-Za-z0-9]*\\s*\n?", "", m[[1L]], perl = TRUE)
  stripped <- sub("\n?\\s*```\\s*$", "", stripped, perl = TRUE)
  trimws(stripped, which = "right")
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
        pattern <- paste0(
          "(?<![A-Za-z0-9._])",
          esc_n,
          "(?![A-Za-z0-9._])"
        )
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
          tryCatch(
            source(sf, local = env, echo = FALSE),
            error = function(e) {
              NULL
            }
          )
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

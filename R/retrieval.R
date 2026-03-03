# ---- Context retrieval helpers -----------------------------------------
# build_context()        -- strategy dispatcher used by run_single()
# read_lines_safe()      -- safe file reader
# bm25_retrieve()        -- BM25 ranked retrieval
# term_overlap_retrieve() -- simple term-overlap baseline

build_context <- function(
  strategy,
  task,
  graph_tfidf,
  graph_ollama,
  source_files,
  budget_tokens = 6000L,
  mcp_state = NULL
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
              seed_node = task$seed_node,
              budget_tokens = budget_tokens
            )
            node_ids <- if (length(ctx$nodes) > 0L) {
              ctx$nodes
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
              seed_node = task$seed_node,
              budget_tokens = budget_tokens
            )
            node_ids <- if (length(ctx$nodes) > 0L) {
              ctx$nodes
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
        file_texts <- vapply(
          source_files,
          read_lines_safe,
          character(1L)
        )
        file_costs <- vapply(
          file_texts,
          .bench_estimate_tokens,
          integer(1L)
        )
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
    rrlmgraph_mcp = {
      if (is.null(mcp_state)) {
        character(0L)
      } else {
        tryCatch(
          {
            res <- mcp_query_context(
              query = task$description,
              seed_node = task$seed_node,
              budget_tokens = budget_tokens,
              mcp_state = mcp_state
            )
            node_ids <- res$node_ids
            res$chunks
          },
          error = function(e) character(0L)
        )
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
  n_docs <- length(files)

  tf_list <- lapply(doc_words, table)

  df_vec <- vapply(
    query_terms,
    function(tm) {
      sum(vapply(tf_list, function(tf) tm %in% names(tf), logical(1L)))
    },
    integer(1L)
  )

  idf_vec <- log((n_docs - df_vec + 0.5) / (df_vec + 0.5) + 1)

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

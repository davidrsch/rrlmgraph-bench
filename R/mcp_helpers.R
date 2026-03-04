# ---- MCP server helpers (rrlmgraph_mcp strategy, bench#30) ---------------
# Internal helpers for starting the rrlmgraph-mcp Node.js stdio server and
# exchanging JSON-RPC messages with it.  These functions are used solely by
# build_context() in run_benchmark.R via the mcp_state environment object
# returned by mcp_start_server().

#' Write a single JSON-RPC message as a newline-terminated line to the stdin
#' of an MCP server process started by \code{mcp_start_server()}.
#' @keywords internal
mcp_write_msg <- function(proc, msg) {
  line <- paste0(jsonlite::toJSON(msg, auto_unbox = TRUE), "\n")
  proc$write_input(line)
}

#' Poll the stdout of an MCP server process until a JSON-RPC response matching
#' \code{id} is received, or until \code{timeout_ms} milliseconds elapse.
#' Returns the parsed response list, or \code{NULL} on timeout.
#' @keywords internal
mcp_read_response <- function(proc, id, timeout_ms = 30000L) {
  t_limit <- proc.time()[["elapsed"]] + timeout_ms / 1000
  buffer <- ""
  while (proc.time()[["elapsed"]] < t_limit) {
    ready <- tryCatch(proc$poll_io(100L), error = function(e) {
      c(stdout = "eof")
    })
    if (ready[["stdout"]] %in% c("ready", "eof")) {
      chunk <- tryCatch(proc$read_output(), error = function(e) "")
      if (nzchar(chunk)) buffer <- paste0(buffer, chunk)
    }
    # Split buffer into complete newline-delimited lines
    lines <- strsplit(buffer, "\n", fixed = TRUE)[[1L]]
    n <- length(lines)
    if (endsWith(buffer, "\n")) {
      complete <- lines
      buffer <- ""
    } else {
      complete <- if (n > 1L) lines[-n] else character(0L)
      buffer <- if (n > 0L) lines[[n]] else ""
    }
    for (line in complete) {
      line <- trimws(line)
      if (!nzchar(line)) {
        next
      }
      parsed <- tryCatch(
        jsonlite::fromJSON(line, simplifyVector = FALSE),
        error = function(e) NULL
      )
      if (
        !is.null(parsed) &&
          !is.null(parsed[["id"]]) &&
          identical(as.integer(parsed[["id"]]), as.integer(id))
      ) {
        return(parsed)
      }
    }
    if (ready[["stdout"]] == "eof") break
  }
  NULL
}

#' Start the rrlmgraph-mcp Node.js server, perform the MCP initialize
#' handshake, and return a mutable state environment with \code{$proc} and
#' \code{$next_id}.  Returns \code{NULL} with a \code{cli_warn()} if
#' Node.js is absent, the \code{dist/index.js} file is missing, or the
#' initialization handshake times out.
#'
#' @param mcp_dir Path to the rrlmgraph-mcp checkout (must contain
#'   \code{dist/index.js}).
#' @param project_path Path to the R project root (passed as
#'   \code{--project-path}).
#' @param db_path Optional path to a pre-built \file{graph.sqlite}.  When
#'   supplied it is passed as \code{--db-path}, overriding the default
#'   \code{<project_path>/.rrlmgraph/graph.sqlite} lookup.  Use this to
#'   supply a temporary SQLite export created by
#'   \code{rrlmgraph::export_to_sqlite()} for per-task benchmarking.
#' @param timeout_ms Handshake timeout in milliseconds (default 10 000).
#' @keywords internal
mcp_start_server <- function(
  mcp_dir,
  project_path,
  db_path = NULL,
  timeout_ms = 10000L
) {
  node_path <- Sys.which("node")
  if (!nzchar(node_path)) {
    cli::cli_warn(c(
      "!" = "Node.js not found -- skipping {.val rrlmgraph_mcp} strategy.",
      "i" = "Install Node.js to enable the MCP strategy."
    ))
    return(NULL)
  }
  index_js <- file.path(mcp_dir, "dist", "index.js")
  if (!file.exists(index_js)) {
    cli::cli_warn(c(
      "!" = "rrlmgraph-mcp dist not found at {.path {index_js}} -- skipping {.val rrlmgraph_mcp}.",
      "i" = "Run {.code npm run build} in the MCP directory, or set {.envvar RRLMGRAPH_MCP_DIR}."
    ))
    return(NULL)
  }

  node_args <- c(index_js, "--project-path", project_path)
  if (!is.null(db_path) && nzchar(db_path)) {
    node_args <- c(node_args, "--db-path", db_path)
  }

  proc <- tryCatch(
    processx::process$new(
      command = node_path,
      args = node_args,
      stdin = "|",
      stdout = "|",
      stderr = "|"
    ),
    error = function(e) {
      cli::cli_warn(c(
        "!" = "Failed to start rrlmgraph-mcp: {conditionMessage(e)}",
        "i" = "Skipping {.val rrlmgraph_mcp} strategy."
      ))
      NULL
    }
  )
  if (is.null(proc)) {
    return(NULL)
  }

  state <- new.env(parent = emptyenv())
  state$proc <- proc
  state$next_id <- 1L

  # MCP initialize handshake
  init_req <- list(
    jsonrpc = "2.0",
    id = 0L,
    method = "initialize",
    params = list(
      protocolVersion = "2024-11-05",
      capabilities = list(),
      clientInfo = list(name = "rrlmgraphbench", version = "0.1.0")
    )
  )
  tryCatch(
    {
      mcp_write_msg(proc, init_req)
      resp <- mcp_read_response(proc, id = 0L, timeout_ms = timeout_ms)
      if (is.null(resp)) {
        stop("MCP initialize timed out")
      }
      # Send initialized notification (no id -- it is not a request)
      mcp_write_msg(
        proc,
        list(
          jsonrpc = "2.0",
          method = "notifications/initialized",
          params = list()
        )
      )
      state
    },
    error = function(e) {
      cli::cli_warn(c(
        "!" = "rrlmgraph-mcp initialization failed: {conditionMessage(e)}",
        "i" = "Skipping {.val rrlmgraph_mcp} strategy."
      ))
      tryCatch(proc$kill(), error = function(e2) NULL)
      NULL
    }
  )
}

#' Call the MCP \code{query_context} tool and return
#' \code{list(chunks, node_ids)}.  Returns an empty result on error or
#' timeout (with a \code{warning()}).
#' @keywords internal
mcp_query_context <- function(
  query,
  seed_node,
  budget_tokens,
  mcp_state,
  timeout_ms = 30000L
) {
  id <- mcp_state$next_id
  mcp_state$next_id <- id + 1L

  args <- list(
    query = query,
    budget_tokens = as.integer(budget_tokens)
  )
  if (!is.null(seed_node) && nzchar(as.character(seed_node))) {
    args$seed_node <- as.character(seed_node)
  }

  req <- list(
    jsonrpc = "2.0",
    id = id,
    method = "tools/call",
    params = list(name = "query_context", arguments = args)
  )

  tryCatch(
    {
      mcp_write_msg(mcp_state$proc, req)
      resp <- mcp_read_response(
        mcp_state$proc,
        id = id,
        timeout_ms = timeout_ms
      )
      if (is.null(resp)) {
        warning(
          "[rrlmgraphbench] mcp_query_context: response timed out"
        )
        return(list(chunks = character(0L), node_ids = character(0L)))
      }
      if (!is.null(resp[["error"]])) {
        warning(
          "[rrlmgraphbench] mcp_query_context error: ",
          resp[["error"]][["message"]]
        )
        return(list(chunks = character(0L), node_ids = character(0L)))
      }
      # Response result$content is a list of {type, text} items.
      # Item [1] = context_string; item [2] = meta footer (nodes/token count).
      content <- resp[["result"]][["content"]]
      if (is.null(content) || !length(content)) {
        return(list(chunks = character(0L), node_ids = character(0L)))
      }
      ctx_text <- tryCatch(content[[1L]][["text"]], error = function(e) {
        ""
      })
      if (is.null(ctx_text) || is.na(ctx_text)) {
        ctx_text <- ""
      }
      # The metaFooter reports the count but not individual node names, so
      # node_ids is left empty (NDCG will be NA for rrlmgraph_mcp rows).
      list(chunks = ctx_text, node_ids = character(0L))
    },
    error = function(e) {
      warning(
        "[rrlmgraphbench] mcp_query_context failed: ",
        conditionMessage(e)
      )
      list(chunks = character(0L), node_ids = character(0L))
    }
  )
}

#' Count hallucinations produced by an LLM in a generated code snippet
#'
#' Parses `code` using [base::parse()] and walks the resulting AST to
#' find:
#' \enumerate{
#'   \item **Invented functions** -- calls to names that appear neither in
#'     the rrlmgraph call-graph (`graph`) nor in the current R session via
#'     \code{getAnywhere()}.
#'   \item **Invalid arguments** -- named arguments that are not listed in
#'     [base::formals()] for the target function (only checked when the
#'     function can be resolved in session).
#'   \item **Wrong-package namespace calls** -- `pkg::fn()` references
#'     where `fn` does not actually export `fn`.
#' }
#' Non-standard-evaluation column references (bare names inside `dplyr`
#' verbs, `data.table` indexing, or formula RHS) are **not** flagged; the
#' detector only inspects calls whose first element is a symbol.
#'
#' @param code  Character(1).  R source code, as returned by the LLM.
#' @param graph An `rrlm_graph` object built over the target project, or
#'   `NULL` (default).  When provided, function names present as nodes in
#'   the graph are trusted even if not loadable in the current session.
#'
#' @return A named list; each element represents one detected
#'   hallucination with fields:
#'   \describe{
#'     \item{`type`}{Character. One of `"invented_function"`,
#'       `"invalid_argument"`, or `"wrong_namespace"`.}
#'     \item{`fn`}{Character. The function name involved.}
#'     \item{`detail`}{Character. Human-readable explanation.}
#'   }
#'   Returns an empty list when no hallucinations are found.
#'
#' @examples
#' code <- "result <- xyzzy_nonexistent_fn(mtcars, foo = 1)"
#' count_hallucinations(code)
#'
#' @importFrom utils getAnywhere
#' @export
count_hallucinations <- function(code, graph = NULL) {
  stopifnot(is.character(code), length(code) == 1L)

  # ---- 1. Parse -------------------------------------------------------
  parsed <- tryCatch(
    parse(text = code, keep.source = FALSE),
    error = function(e) {
      warning(
        "count_hallucinations: code failed to parse - ",
        conditionMessage(e)
      )
      return(NULL)
    }
  )
  if (is.null(parsed)) {
    return(list())
  }

  # ---- 2. Build trusted-name sets ------------------------------------
  graph_names <- character(0L)
  if (!is.null(graph)) {
    # rrlm_graph IS an igraph (class-prepended); accept plain igraph too.
    graph_names <- tryCatch(
      names(igraph::V(graph)),
      error = function(e) character(0L)
    )
  }

  nse_wrappers <- c(
    # dplyr / tidyr
    "mutate",
    "filter",
    "select",
    "summarise",
    "summarize",
    "group_by",
    "arrange",
    "rename",
    "transmute",
    "across",
    # data.table
    "\\[.data.table",
    # base
    "with",
    "within",
    "subset",
    "transform",
    # rlang / dplyr eval helpers
    "quo",
    "enquo",
    "expr",
    "sym"
  )

  hallucinations <- list()

  # ---- 3. Walk AST ----------------------------------------------------
  walk_node <- function(node) {
    if (!is.call(node)) {
      if (is.recursive(node)) {
        lapply(node, walk_node)
      }
      return(invisible(NULL))
    }

    fn_sym <- node[[1L]]
    fn_name <- if (is.symbol(fn_sym)) as.character(fn_sym) else NULL

    # --- 3a. Wrong namespace: pkg::fn() ---------------------------------
    if (
      is.call(fn_sym) &&
        length(fn_sym) == 3L &&
        (identical(fn_sym[[1L]], quote(`::`)) ||
          identical(fn_sym[[1L]], quote(`:::`)))
    ) {
      pkg <- as.character(fn_sym[[2L]])
      func <- as.character(fn_sym[[3L]])
      exports <- tryCatch(
        getNamespaceExports(pkg),
        error = function(e) character(0L)
      )
      if (length(exports) > 0L && !func %in% exports) {
        hallucinations[[length(hallucinations) + 1L]] <<- list(
          type = "wrong_namespace",
          fn = paste0(pkg, "::", func),
          detail = sprintf(
            "'%s' is not exported by package '%s'.",
            func,
            pkg
          )
        )
      }
    }

    # --- 3b. Invented function -----------------------------------------
    if (!is.null(fn_name) && fn_name != "") {
      # Skip NSE wrappers -- bare names inside them are column refs
      if (!fn_name %in% nse_wrappers) {
        in_session <- tryCatch(
          {
            res <- getAnywhere(fn_name)
            length(res$objs) > 0L
          },
          error = function(e) FALSE
        )
        in_graph <- fn_name %in% graph_names

        if (!in_session && !in_graph) {
          hallucinations[[length(hallucinations) + 1L]] <<- list(
            type = "invented_function",
            fn = fn_name,
            detail = sprintf(
              "'%s' could not be found in the R session or the project graph.",
              fn_name
            )
          )
        } else if (in_session) {
          # --- 3c. Invalid arguments ------------------------------------
          f_obj <- tryCatch(
            getAnywhere(fn_name)$objs[[1L]],
            error = function(e) NULL
          )
          if (is.function(f_obj)) {
            known_args <- names(formals(f_obj))
            has_dots <- "..." %in% known_args
            if (!has_dots && !is.null(known_args)) {
              call_args <- names(as.list(node)[-1L])
              call_args <- call_args[!is.na(call_args) & nzchar(call_args)]
              bad_args <- setdiff(call_args, known_args)
              for (ba in bad_args) {
                hallucinations[[length(hallucinations) + 1L]] <<- list(
                  type = "invalid_argument",
                  fn = fn_name,
                  detail = sprintf(
                    "Argument '%s' is not a formal parameter of '%s()'.",
                    ba,
                    fn_name
                  )
                )
              }
            }
          }
        }
      }
    }

    # Recurse into sub-expressions
    lapply(as.list(node)[-1L], walk_node)
    invisible(NULL)
  }

  lapply(as.list(parsed), walk_node)
  hallucinations
}

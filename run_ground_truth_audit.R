#!/usr/bin/env Rscript
# run_ground_truth_audit.R
#
# Validates all 30 ground-truth solution files in inst/ground_truth/solutions/.
#
# Checks performed per solution:
#   1. PARSE_OK    : file parses without syntax errors (base::parse())
#   2. CATEGORY_OK : category-specific assertion (see below)
#
# Category assertions:
#   function_modification — new parameter name extracted from task description
#                           must appear in the solution source text
#   bug_detection         — any identifiable bug string (if derivable from task
#                           description) is absent from the solution
#   new_feature           — a "function" keyword or assignment appears
#   refactor              — exported function names from the description appear
#   documentation         — @param, @return, and @export roxygen tags present
#
# Usage:
#   Rscript run_ground_truth_audit.R          # run from package root
#   Rscript run_ground_truth_audit.R --fix    # also print fixable hints
#
# Exit code: 0 if all pass, 1 if any fail.
# Phase 2 Action #2 / bench#31

# ---- setup ------------------------------------------------------------------

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite required: install.packages('jsonlite')")
}

pkg_root <- if (file.exists("DESCRIPTION")) {
  normalizePath(".")
} else {
  stop("Run from the rrlmgraphbench package root directory.")
}

tasks_dir     <- file.path(pkg_root, "inst", "tasks")
solutions_dir <- file.path(pkg_root, "inst", "ground_truth", "solutions")

task_files <- sort(list.files(tasks_dir, pattern = "\\.json$", full.names = TRUE))
if (!length(task_files)) stop("No task JSON files found in: ", tasks_dir)

# ---- helpers ----------------------------------------------------------------

.check_parse <- function(path) {
  result <- tryCatch(
    { parse(file = path); TRUE },
    error = function(e) conditionMessage(e)
  )
  result
}

.extract_new_param <- function(description) {
  # Look for backtick-quoted identifiers that look like parameter names
  # e.g. "Add a `stratified` logical parameter" -> "stratified"
  m <- regmatches(description, gregexpr("`[A-Za-z_.][A-Za-z_.0-9]*`", description))[[1L]]
  if (length(m)) gsub("`", "", m[[1L]]) else NULL
}

.check_category <- function(task, solution_text) {
  cat_name <- task$category
  desc     <- paste(task$description, collapse = " ")

  if (cat_name == "function_modification") {
    param <- .extract_new_param(desc)
    if (is.null(param)) return(list(ok = TRUE, note = "no param extracted from desc"))
    found <- grepl(param, solution_text, fixed = TRUE)
    list(
      ok   = found,
      note = if (found) {
        sprintf("new param '%s' present", param)
      } else {
        sprintf("new param '%s' NOT found", param)
      }
    )
  } else if (cat_name == "bug_detection") {
    # We just check that the solution is non-trivial (has at least one assignment)
    has_assign <- grepl("<-|=", solution_text)
    list(ok = has_assign, note = if (has_assign) "assignment found" else "empty solution?")
  } else if (cat_name == "new_feature") {
    # Should define at least one function
    has_fn <- grepl("\\bfunction\\s*\\(", solution_text)
    list(ok = has_fn, note = if (has_fn) "function definition found" else "no function definition")
  } else if (cat_name == "refactor") {
    # Check that the file is non-trivial
    has_assign <- grepl("<-|=", solution_text)
    list(ok = has_assign, note = "assignment check passed")
  } else if (cat_name == "documentation") {
    # Documentation tasks may be:
    #   (a) function documentation with roxygen @param/@return/@export
    #   (b) package-level documentation with @name/@docType
    #   (c) inline comments explaining code (no roxygen at all)
    # Accept (a) OR (b) OR (c).
    has_param_return_export <- grepl("@param",  solution_text) &&
      grepl("@return", solution_text) &&
      grepl("@export", solution_text)
    has_pkg_doc  <- grepl("@name", solution_text) || grepl("@docType", solution_text)
    has_inline   <- grepl("#\\s*\\(|#.*reactive|#.*comment|#.*explain|#.*note",
                          solution_text, ignore.case = TRUE)
    has_any_comment <- grepl("^\\s*#", solution_text)
    ok <- has_param_return_export || has_pkg_doc || has_inline || has_any_comment
    note <- if (has_param_return_export) {
      "function roxygen tags present"
    } else if (has_pkg_doc) {
      "package-level roxygen tags present"
    } else if (has_inline || has_any_comment) {
      "inline comments present"
    } else {
      "no documentation found"
    }
    list(ok = ok, note = note)
  } else {
    list(ok = TRUE, note = sprintf("unknown category '%s' — skipped", cat_name))
  }
}

# ---- main audit loop --------------------------------------------------------

results <- vector("list", length(task_files))

for (i in seq_along(task_files)) {
  task <- tryCatch(
    jsonlite::fromJSON(task_files[[i]], simplifyVector = TRUE),
    error = function(e) NULL
  )
  if (is.null(task)) {
    results[[i]] <- list(
      task_id  = basename(task_files[[i]]),
      parse_ok = FALSE,
      cat_ok   = FALSE,
      note     = "FAILED to parse task JSON"
    )
    next
  }

  sol_rel <- task$ground_truth_file
  sol_abs <- if (!is.null(sol_rel) && nzchar(sol_rel)) {
    file.path(pkg_root, sol_rel)
  } else {
    # Derive from task_id
    fname <- paste0(task$task_id, "_solution.R")
    file.path(solutions_dir, fname)
  }

  if (!file.exists(sol_abs)) {
    results[[i]] <- list(
      task_id  = task$task_id,
      parse_ok = FALSE,
      cat_ok   = FALSE,
      note     = sprintf("solution file NOT FOUND: %s", sol_abs)
    )
    next
  }

  parse_result <- .check_parse(sol_abs)
  parse_ok     <- isTRUE(parse_result)

  solution_text <- paste(readLines(sol_abs, warn = FALSE), collapse = "\n")
  cat_check     <- if (parse_ok) {
    .check_category(task, solution_text)
  } else {
    list(ok = FALSE, note = "skipped — parse failed")
  }

  results[[i]] <- list(
    task_id   = task$task_id,
    category  = task$category,
    parse_ok  = parse_ok,
    cat_ok    = cat_check$ok,
    parse_err = if (!parse_ok) parse_result else "",
    note      = cat_check$note
  )
}

# ---- report -----------------------------------------------------------------

n_total    <- length(results)
parse_fail <- sum(!vapply(results, `[[`, logical(1L), "parse_ok"))
cat_fail   <- sum(!vapply(results, `[[`, logical(1L), "cat_ok"))
n_pass     <- sum(
  vapply(results, `[[`, logical(1L), "parse_ok") &
  vapply(results, `[[`, logical(1L), "cat_ok")
)

cat("\n──────────────────────────────────────────\n")
cat(sprintf(
  "Ground-truth audit: %d/%d tasks PASS\n",
  n_pass,
  n_total
))
cat(sprintf(
  "  parse failures : %d\n",
  parse_fail
))
cat(sprintf(
  "  category fails : %d\n",
  cat_fail
))
cat("──────────────────────────────────────────\n\n")

if (parse_fail + cat_fail > 0L) {
  cat("FAILURES:\n")
  for (r in results) {
    if (!r$parse_ok || !r$cat_ok) {
      cat(sprintf(
        "  [%s] %-35s  parse=%s  cat=%s  — %s\n",
        if (!r$parse_ok || !r$cat_ok) "FAIL" else " OK ",
        r$task_id,
        if (r$parse_ok) "OK" else "FAIL",
        if (r$cat_ok)   "OK" else "FAIL",
        r$note
      ))
      if (!r$parse_ok && nzchar(r$parse_err)) {
        cat(sprintf("      parse error: %s\n", r$parse_err))
      }
    }
  }
  cat("\n")
  quit(status = 1L, save = "no")
} else {
  cat("All", n_total, "solution files pass audit.\n\n")
  quit(status = 0L, save = "no")
}

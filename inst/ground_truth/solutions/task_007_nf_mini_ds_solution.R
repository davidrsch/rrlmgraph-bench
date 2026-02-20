# Solution for task_007_nf_mini_ds
# Implement save_benchmark_results(results, path).
#
# Key decision: validate class first so callers get an informative error
# rather than a silent saveRDS of wrong data. Use message() (not cat())
# so the output can be suppressed with suppressMessages().

#' Save benchmark results to an RDS file
#'
#' Serialises a `"benchmark_result"` object to disk and prints a
#' confirmation message.
#'
#' @param results An object of class `"benchmark_result"` produced by
#'   [run_benchmark()].
#' @param path Character(1). Destination file path (typically with a
#'   `.rds` extension).
#' @return `path`, invisibly.
#' @seealso [run_benchmark()], [format_results()]
#' @export
save_benchmark_results <- function(results, path) {
  if (!inherits(results, "benchmark_result")) {
    stop("`results` must be an object of class 'benchmark_result'.")
  }
  saveRDS(results, file = path)
  message("Saved benchmark results to ", path)
  invisible(path)
}

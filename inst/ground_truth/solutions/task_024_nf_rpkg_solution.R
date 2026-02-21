# Solution for task_024_nf_rpkg
# Add print.ModelResult S3 method

#' @export
print.ModelResult <- function(x, ...) {
  cat("ModelResult\n")
  cat("Call:  ", deparse(x@call), "\n", sep = "")
  cat("Obs:   ", length(x@predictions), "\n", sep = "")
  cat("RMSE:  ", round(x@rmse, 4L), "\n", sep = "")
  invisible(x)
}

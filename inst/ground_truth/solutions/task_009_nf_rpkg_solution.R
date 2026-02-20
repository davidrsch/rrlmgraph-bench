# Solution for task_009_nf_rpkg
# Implement summarise_result() S4 generic + ModelResult method.
#
# Key decision: return a data.frame rather than printing, so the result
# can be captured programmatically. The generic is added to AllGenerics.R
# and the method to methods-ModelResult.R.

# --- In R/AllGenerics.R ---

#' Return a tidy data frame summary of a model result
#'
#' @param object A model result object.
#' @return A `data.frame` with columns `metric` (character) and
#'   `value` (numeric).
#' @export
setGeneric("summarise_result", function(object) {
  standardGeneric("summarise_result")
})

# --- In R/methods-ModelResult.R ---

#' @describeIn ModelResult Return a tidy data frame of metrics.
#' @export
setMethod("summarise_result", "ModelResult", function(object) {
  metric_names <- names(object@metrics)
  metric_values <- unname(object@metrics)

  # Append timestamp as a numeric (Unix epoch) for uniformity
  metric_names <- c(metric_names, "timestamp")
  metric_values <- c(metric_values, as.numeric(object@timestamp))

  data.frame(
    metric = metric_names,
    value = metric_values,
    stringsAsFactors = FALSE
  )
})

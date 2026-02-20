# R/AllGenerics.R — S4 generic function declarations

#' Compute evaluation metrics for a fitted model
#'
#' @param object A model result object.
#' @param newdata Optional new data for out-of-sample evaluation.
#' @param ... Additional arguments passed to methods.
#' @return A named numeric vector of evaluation metrics.
#' @export
setGeneric("evaluate", function(object, newdata = NULL, ...) {
  standardGeneric("evaluate")
})

#' Summarise a model result
#'
#' @param object A `ModelResult` object.
#' @return Returns `object` invisibly; prints a formatted summary.
#' @export
setGeneric("model_summary", function(object) {
  standardGeneric("model_summary")
})

#' Extract the fitted coefficients
#'
#' @param object A model result object.
#' @return A named numeric vector of coefficients.
#' @export
setGeneric("get_coefs", function(object) {
  standardGeneric("get_coefs")
})

#' Predict from a model result
#'
#' @param object  A `ModelResult` object.
#' @param newdata A data.frame of new observations.
#' @param ...     Additional arguments (e.g. `type` for GLM predictions).
#' @return A numeric vector of predictions.
#' @export
setGeneric("predict_new", function(object, newdata, ...) {
  standardGeneric("predict_new")
})

#' Plot a model result
#'
#' @param x   A `ModelResult` object.
#' @param y   Ignored; present for S3/S4 compatibility.
#' @param ... Additional graphical parameters.
#' @return Invisible `NULL`; plots as a side-effect.
#' @export
setGeneric("plot_result", function(x, y, ...) {
  standardGeneric("plot_result")
})

# R/methods-ModelResult.R — S4 methods for the ModelResult class

#' @describeIn ModelResult Show a concise one-line representation.
#' @export
setMethod("show", "ModelResult", function(object) {
  metrics_str <- if (length(object@metrics) > 0L) {
    paste(
      names(object@metrics),
      round(object@metrics, 4L),
      sep = "=",
      collapse = ", "
    )
  } else {
    "(no metrics)"
  }
  cat(
    sprintf(
      "<ModelResult>  n_pred=%d  %s  [%s]\n",
      length(object@predictions),
      metrics_str,
      format(object@timestamp, "%Y-%m-%d %H:%M")
    )
  )
  invisible(object)
})

#' @describeIn ModelResult Evaluate the model against new data or stored residuals.
#' @export
setMethod("evaluate", "ModelResult", function(object, newdata = NULL, ...) {
  if (!is.null(newdata)) {
    preds <- stats::predict(object@model, newdata = newdata)
    resids <- newdata[[all.vars(object@call$formula)[1L]]] - preds
  } else {
    preds <- object@predictions
    resids <- object@residuals
  }

  rmse <- compute_rmse_s4(preds, preds - resids)
  mae <- compute_mae(resids)
  r_squared <- compute_r_squared(resids, preds - resids)

  c(rmse = rmse, mae = mae, r_squared = r_squared)
})

#' @describeIn ModelResult Print a detailed model summary.
#' @export
setMethod("model_summary", "ModelResult", function(object) {
  cat("=== ModelResult Summary ===\n")
  cat("  Fit time  :", format(object@timestamp, "%Y-%m-%d %H:%M:%S"), "\n")
  cat("  N predict :", length(object@predictions), "\n")
  cat("  Metrics   :\n")
  for (nm in names(object@metrics)) {
    cat(sprintf("    %-12s %g\n", nm, object@metrics[[nm]]))
  }
  cat("  Model call:", deparse(object@call), "\n")
  invisible(object)
})

#' @describeIn ModelResult Extract fitted coefficients from the model slot.
#' @export
setMethod("get_coefs", "ModelResult", function(object) {
  tryCatch(
    stats::coef(object@model),
    error = function(e) {
      warning("Could not extract coefficients: ", e$message)
      numeric(0)
    }
  )
})

#' @describeIn ModelResult Predict from the stored fitted model on new data.
#' @export
setMethod("predict_new", "ModelResult", function(object, newdata, ...) {
  stats::predict(object@model, newdata = newdata, ...)
})

#' @describeIn ModelResult Plot residuals vs fitted values.
#' @export
setMethod("plot_result", "ModelResult", function(x, y, ...) {
  fitted_vals <- x@predictions
  resids <- x@residuals

  graphics_available <- requireNamespace("graphics", quietly = TRUE)
  if (!graphics_available) {
    message("graphics package needed for plotting.")
    return(invisible(NULL))
  }

  op <- graphics::par(mfrow = c(1L, 2L))
  on.exit(graphics::par(op))

  # Residuals vs Fitted
  plot(
    fitted_vals,
    resids,
    xlab = "Fitted values",
    ylab = "Residuals",
    main = "Residuals vs Fitted",
    pch = 16L,
    col = grDevices::adjustcolor("steelblue", alpha.f = 0.5),
    ...
  )
  graphics::abline(h = 0, lty = 2L, col = "red")

  # Q-Q plot of residuals
  stats::qqnorm(
    resids,
    main = "Normal Q-Q of Residuals",
    pch = 16L,
    col = grDevices::adjustcolor("steelblue", 0.5)
  )
  stats::qqline(resids, col = "red", lty = 2L)

  invisible(NULL)
})

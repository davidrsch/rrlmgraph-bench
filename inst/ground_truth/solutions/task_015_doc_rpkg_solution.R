# Solution for task_015_doc_rpkg
# Substantially improved Roxygen documentation for compare_models().
#
# Key decision: examples use mtcars (always available) and the package's
# own new_fit_config() / fit_model_s4() constructors for realism.

#' Compare multiple ModelResult objects
#'
#' Extracts the stored evaluation metrics from each [`ModelResult`][ModelResult-class]
#' and returns a tidy `data.frame` with one row per model and one column
#' per metric.
#'
#' The function accepts models either as individual positional arguments
#' or as a single list.  Model names default to `"model_1"`, `"model_2"`,
#' etc., but can be overridden via the `names` argument.
#'
#' @param ... One or more [`ModelResult`][ModelResult-class] objects, or
#'   a single list of `ModelResult` objects.  All elements must belong to
#'   the `ModelResult` S4 class.
#' @param names Character vector of model labels, in the same order as
#'   the supplied models.  Defaults to `paste0("model_", seq_along(models))`.
#'
#' @return A `data.frame` with:
#'   \describe{
#'     \item{`model`}{Character. The model label.}
#'     \item{`rmse`, `mae`, `r_squared`, ...}{Numeric. One column per
#'       metric present in `object@metrics`.}
#'   }
#'
#' @seealso [fit_model_s4()] to produce `ModelResult` objects;
#'   [cross_validate()] for cross-validated metric computation.
#'
#' @examples
#' config1 <- new_fit_config(mpg ~ wt,          method = "lm")
#' config2 <- new_fit_config(mpg ~ wt + cyl,    method = "lm")
#'
#' m1 <- fit_model_s4(mtcars, config1)
#' m2 <- fit_model_s4(mtcars, config2)
#'
#' compare_models(m1, m2, names = c("simple", "complex"))
#'
#' @export
compare_models <- function(..., names = NULL) {
  models <- c(list(...))
  # Flatten if a single list was passed
  if (
    length(models) == 1L &&
      is.list(models[[1L]]) &&
      !methods::is(models[[1L]], "ModelResult")
  ) {
    models <- models[[1L]]
  }
  if (is.null(names)) {
    names <- paste0("model_", seq_along(models))
  }
  rows <- lapply(models, function(m) as.list(m@metrics))
  df <- do.call(rbind, lapply(rows, as.data.frame))
  df <- cbind(model = names, df, stringsAsFactors = FALSE)
  rownames(df) <- NULL
  df
}

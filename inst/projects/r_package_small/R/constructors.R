# R/constructors.R — constructor functions for S4 classes

#' Create a new ModelResult object
#'
#' Convenience constructor for the [ModelResult-class] S4 class.
#' Validates inputs before instantiation.
#'
#' @param model       A fitted model object (e.g. from [stats::lm()]).
#' @param predictions Numeric vector of fitted values.
#' @param actuals     Numeric vector of observed values (same length as
#'   `predictions`).  Used to compute residuals and metrics automatically.
#' @param call        The original modelling call (default: `sys.call(-1L)`).
#' @return A [`ModelResult`][ModelResult-class] object.
#' @export
new_model_result <- function(model, predictions, actuals, call = NULL) {
  if (is.null(call)) {
    call <- sys.call(-1L)
  }
  if (!is.numeric(predictions)) {
    stop("`predictions` must be numeric.")
  }
  if (!is.numeric(actuals)) {
    stop("`actuals` must be numeric.")
  }
  if (length(predictions) != length(actuals)) {
    stop("`predictions` and `actuals` must have the same length.")
  }

  resids <- actuals - predictions
  metrics <- c(
    rmse = compute_rmse_s4(predictions, actuals),
    mae = compute_mae(resids),
    r_squared = compute_r_squared(resids, actuals)
  )

  methods::new(
    "ModelResult",
    model = model,
    predictions = predictions,
    residuals = resids,
    metrics = metrics,
    call = as.call(list(call)),
    timestamp = Sys.time()
  )
}

#' Create a new FitConfig object
#'
#' Convenience constructor for the [FitConfig-class] S4 class.
#'
#' @param formula  A [formula] object.
#' @param method   Character(1). One of `"lm"`, `"glm"`, `"ridge"`.
#'   Default `"lm"`.
#' @param cv_folds Integer(1). Cross-validation folds.  Default `5L`.
#' @param seed     Integer(1). Random seed.  Default `42L`.
#' @param scale    Logical(1). Scale numeric predictors?  Default `FALSE`.
#' @return A [`FitConfig`][FitConfig-class] object.
#' @export
new_fit_config <- function(
  formula,
  method = c("lm", "glm", "ridge"),
  cv_folds = 5L,
  seed = 42L,
  scale = FALSE
) {
  method <- match.arg(method)
  if (!inherits(formula, "formula")) {
    stop("`formula` must be a formula object.")
  }
  if (cv_folds < 2L) {
    stop("`cv_folds` must be at least 2.")
  }
  methods::new(
    "FitConfig",
    formula = formula,
    method = method,
    cv_folds = as.integer(cv_folds),
    seed = as.integer(seed),
    scale = as.logical(scale)
  )
}

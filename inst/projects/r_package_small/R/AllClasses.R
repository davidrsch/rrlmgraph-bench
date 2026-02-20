# R/AllClasses.R — S4 class definitions

#' S4 class representing a fitted model result
#'
#' Stores a fitted model object, its predictions, residuals, and
#' evaluation metrics in a single structured container.
#'
#' @slot model     Any fitted model object (e.g. from [stats::lm()]).
#' @slot predictions Numeric vector of predicted values.
#' @slot residuals  Numeric vector of residuals.
#' @slot metrics   Named numeric vector of evaluation metrics (e.g.
#'   `rmse`, `mae`, `r_squared`).
#' @slot call      The original call used to fit the model.
#' @slot timestamp POSIXct. When the fit was performed.
#'
#' @exportClass ModelResult
setClass(
  "ModelResult",
  representation(
    model = "ANY",
    predictions = "numeric",
    residuals = "numeric",
    metrics = "numeric",
    call = "call",
    timestamp = "POSIXct"
  ),
  prototype(
    predictions = numeric(0),
    residuals = numeric(0),
    metrics = numeric(0),
    timestamp = Sys.time()
  )
)

#' S4 class for model fitting configuration
#'
#' Bundles hyperparameters and pre-processing options for a fitting run.
#'
#' @slot formula   A [formula] object.
#' @slot method    Character(1). Fitting method; one of `"lm"`,
#'   `"glm"`, or `"ridge"`.
#' @slot cv_folds  Integer(1). Number of cross-validation folds.
#' @slot seed      Integer(1). Random seed.
#' @slot scale     Logical(1). Whether to standardise numeric predictors.
#'
#' @exportClass FitConfig
setClass(
  "FitConfig",
  representation(
    formula = "formula",
    method = "character",
    cv_folds = "integer",
    seed = "integer",
    scale = "logical"
  ),
  prototype(
    method = "lm",
    cv_folds = 5L,
    seed = 42L,
    scale = FALSE
  )
)

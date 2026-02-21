# Solution for task_030_doc_rpkg
# Package-level Roxygen2 help page for r_package_small

#' r_package_small: A minimal R package for model fitting and evaluation
#'
#' Provides a small but complete S4 modelling workflow: configuration objects
#' (\code{\link{FitConfig-class}}), model fitting (\code{\link{fit_model_s4}}),
#' evaluation (\code{\link{evaluate_model}}), and k-fold cross-validation
#' (\code{\link{cross_validate}}).  The package is designed as a benchmark
#' fixture for the \pkg{rrlmgraphbench} suite.
#'
#' @name r_package_small
#' @docType package
#' @seealso \code{\link{fit_model_s4}}, \code{\link{cross_validate}}
"_PACKAGE"

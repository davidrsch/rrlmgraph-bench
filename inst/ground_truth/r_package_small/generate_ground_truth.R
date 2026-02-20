# generate_ground_truth.R  —  r_package_small fixture
#
# Run from the rrlmgraph-bench repo root:
#   Rscript inst/ground_truth/r_package_small/generate_ground_truth.R
#
# Manually verified against inst/projects/r_package_small/R/*.R

out_dir <- file.path("inst", "ground_truth", "r_package_small")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ---- 1. function_signatures.rds ----------------------------------------

function_signatures <- c(
  # AllGenerics.R — S4 generics
  "AllGenerics::evaluate" = "evaluate(object, newdata, ...)",
  "AllGenerics::model_summary" = "model_summary(object)",
  "AllGenerics::get_coefs" = "get_coefs(object)",
  "AllGenerics::predict_new" = "predict_new(object, newdata, ...)",
  "AllGenerics::plot_result" = "plot_result(x, y, ...)",
  # constructors.R
  "constructors::new_model_result" = "new_model_result(model, predictions, actuals, call = NULL)",
  "constructors::new_fit_config" = "new_fit_config(formula, method = c('lm', 'glm', 'ridge'), cv_folds = 5L, seed = 42L, scale = FALSE)",
  # exported_fns.R
  "exported_fns::fit_model_s4" = "fit_model_s4(train, config)",
  "exported_fns::cross_validate" = "cross_validate(data, config)",
  "exported_fns::scale_predictors" = "scale_predictors(df, formula)",
  "exported_fns::compare_models" = "compare_models(..., names = NULL)",
  "exported_fns::print_metrics" = "print_metrics(result, digits = 4L)",
  # utils.R — internal helpers; included for graph coverage
  "utils::compute_rmse_s4" = "compute_rmse_s4(predicted, actual)",
  "utils::compute_mae" = "compute_mae(residuals)",
  "utils::compute_r_squared" = "compute_r_squared(residuals, actuals)"
)

saveRDS(
  function_signatures,
  file.path(out_dir, "function_signatures.rds")
)
message(
  "Wrote function_signatures.rds (",
  length(function_signatures),
  " entries)"
)

# ---- 2. call_edges.rds -------------------------------------------------

call_edges <- data.frame(
  from = c(
    # new_model_result → compute_rmse_s4, compute_mae, compute_r_squared, methods::new
    "constructors::new_model_result",
    "constructors::new_model_result",
    "constructors::new_model_result",
    "constructors::new_model_result",
    # new_fit_config → methods::new
    "constructors::new_fit_config",
    # fit_model_s4 → check_columns, scale_predictors, new_model_result,
    #               stats::lm / stats::glm, stats::fitted
    "exported_fns::fit_model_s4",
    "exported_fns::fit_model_s4",
    "exported_fns::fit_model_s4",
    "exported_fns::fit_model_s4",
    "exported_fns::fit_model_s4",
    # cross_validate → fit_model_s4, evaluate
    "exported_fns::cross_validate",
    "exported_fns::cross_validate",
    # compare_models → methods::is
    "exported_fns::compare_models",
    # evaluate/ModelResult → compute_rmse_s4, compute_mae, compute_r_squared
    "AllGenerics::evaluate",
    "AllGenerics::evaluate",
    "AllGenerics::evaluate",
    # get_coefs/ModelResult → stats::coef
    "AllGenerics::get_coefs",
    # predict_new/ModelResult → stats::predict
    "AllGenerics::predict_new",
    # compute_rmse_s4 → sqrt, mean
    "utils::compute_rmse_s4",
    "utils::compute_rmse_s4",
    # compute_mae → mean, abs
    "utils::compute_mae",
    "utils::compute_mae",
    # compute_r_squared → sum, mean
    "utils::compute_r_squared",
    "utils::compute_r_squared"
  ),
  to = c(
    "utils::compute_rmse_s4",
    "utils::compute_mae",
    "utils::compute_r_squared",
    "methods::new",
    "methods::new",
    "utils::check_columns",
    "exported_fns::scale_predictors",
    "constructors::new_model_result",
    "stats::lm",
    "stats::fitted",
    "exported_fns::fit_model_s4",
    "AllGenerics::evaluate",
    "methods::is",
    "utils::compute_rmse_s4",
    "utils::compute_mae",
    "utils::compute_r_squared",
    "stats::coef",
    "stats::predict",
    "base::sqrt",
    "base::mean",
    "base::mean",
    "base::abs",
    "base::sum",
    "base::mean"
  ),
  stringsAsFactors = FALSE
)

saveRDS(call_edges, file.path(out_dir, "call_edges.rds"))
message("Wrote call_edges.rds (", nrow(call_edges), " edges)")

# ---- 3. node_relevance_scores.rds --------------------------------------

all_nodes <- names(function_signatures)

tasks <- list(
  list(
    query = "How is a ModelResult constructed from raw model output?",
    scores = setNames(
      c(
        0L,
        0L,
        0L,
        0L,
        0L, # generics
        3L,
        1L, # constructors
        2L,
        0L,
        0L,
        0L,
        0L, # exported_fns
        2L,
        2L,
        2L
      ), # utils
      all_nodes
    )
  ),
  list(
    query = "Which functions compute error metrics (RMSE, MAE, R-squared)?",
    scores = setNames(
      c(2L, 0L, 0L, 0L, 0L, 1L, 0L, 0L, 0L, 0L, 0L, 0L, 3L, 3L, 3L),
      all_nodes
    )
  ),
  list(
    query = "How are models fitted and cross-validated?",
    scores = setNames(
      c(0L, 0L, 0L, 0L, 0L, 1L, 2L, 3L, 3L, 1L, 0L, 0L, 1L, 0L, 0L),
      all_nodes
    )
  ),
  list(
    query = "How are predictions extracted from a trained model?",
    scores = setNames(
      c(0L, 0L, 0L, 3L, 0L, 2L, 1L, 2L, 0L, 0L, 0L, 0L, 0L, 0L, 0L),
      all_nodes
    )
  ),
  list(
    query = "How are multiple fitted models compared side by side?",
    scores = setNames(
      c(0L, 1L, 1L, 0L, 0L, 0L, 0L, 0L, 0L, 0L, 3L, 2L, 0L, 0L, 0L),
      all_nodes
    )
  )
)

saveRDS(tasks, file.path(out_dir, "node_relevance_scores.rds"))
message("Wrote node_relevance_scores.rds (", length(tasks), " tasks)")

message("\nGround truth generation complete  [r_package_small]")
message("Total functions : ", length(function_signatures))
message("Total call edges: ", nrow(call_edges))
message("Total tasks     : ", length(tasks))

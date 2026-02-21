# Solution for task_021_bd_rpkg
# Fix S3 method dispatch by ensuring lm_result is first in class vector

fit_model_s4 <- function(train, config) {
  check_columns(train, all.vars(config@formula))
  if (config@scale) {
    train <- scale_predictors(train, config@formula)
  }
  set.seed(config@seed)
  fitted_model <- switch(
    config@method,
    lm  = stats::lm(config@formula, data = train),
    glm = stats::glm(config@formula, data = train)
  )
  # Fix: put lm_result FIRST so dispatch reaches our method before stats:::
  class(fitted_model) <- c("lm_result", setdiff(class(fitted_model), "lm_result"))
  preds   <- as.numeric(stats::fitted(fitted_model))
  actuals <- train[[all.vars(config@formula)[1L]]]
  new_model_result(fitted_model, preds, actuals, call = match.call())
}

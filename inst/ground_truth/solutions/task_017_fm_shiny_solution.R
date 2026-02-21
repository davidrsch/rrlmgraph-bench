# Solution for task_017_fm_shiny
# Extract reactive filter logic into standalone filter_data() in R/data.R

#' Filter survey data based on Shiny input
#'
#' @param df A data frame of survey data.
#' @param input A Shiny input list.
#' @return Filtered data frame.
#' @export
filter_data <- function(df, input) {
  if (!is.null(input$age_min) && !is.na(input$age_min)) {
    df <- df[df$age >= input$age_min, , drop = FALSE]
  }
  if (!is.null(input$age_max) && !is.na(input$age_max)) {
    df <- df[df$age <= input$age_max, , drop = FALSE]
  }
  if (!is.null(input$category) && nzchar(input$category)) {
    df <- df[df$category == input$category, , drop = FALSE]
  }
  df
}

# Updated server_logic uses filter_data() instead of inline logic
server_logic <- function(DATA_PATH = NULL) {
  if (is.null(DATA_PATH)) {
    DATA_PATH <- system.file("extdata", "survey.csv", package = "shinyAppMedium")
  }
  function(input, output, session) {
    base_data <- shiny::reactive({
      df <- load_survey_data(DATA_PATH)
      preprocess_data(df)
    })
    filtered_r <- shiny::reactive({
      filter_data(base_data(), input)
    })
    observe_reset(input, session)
  }
}

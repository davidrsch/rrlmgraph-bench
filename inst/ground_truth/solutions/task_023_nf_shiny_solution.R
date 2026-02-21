# Solution for task_023_nf_shiny
# Add downloadHandler for filtered data CSV export

server_logic <- function(DATA_PATH = NULL) {
  if (is.null(DATA_PATH)) {
    DATA_PATH <- system.file("extdata", "survey.csv", package = "shinyAppMedium")
  }
  function(input, output, session) {
    base_data <- shiny::reactive({
      df <- load_survey_data(DATA_PATH)
      preprocess_data(df)
    })
    filtered_r <- filterServer(
      "filter_mod",
      shiny::reactive({ update_filtered_data(base_data(), input) })
    )
    observe_reset(input, session)

    # Download handler for filtered data (#23)
    output$download_data <- shiny::downloadHandler(
      filename = function() "survey_filtered.csv",
      content  = function(file) {
        utils::write.csv(filtered_r(), file, row.names = FALSE)
      }
    )
  }
}

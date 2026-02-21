# Solution for task_029_doc_shiny
# Add inline comments explaining the reactive data flow in server_logic()

server_logic <- function(DATA_PATH = NULL) {
  if (is.null(DATA_PATH)) {
    DATA_PATH <- system.file("extdata", "survey.csv", package = "shinyAppMedium")
  }

  function(input, output, session) {

    # (1) base_data is a shiny::reactive() — not computed once at startup —
    # so that it is automatically re-evaluated if DATA_PATH changes or the
    # session is invalidated.  Caching is provided by Shiny's reactive graph.
    base_data <- shiny::reactive({
      df <- load_survey_data(DATA_PATH)
      preprocess_data(df)
    })

    # (2) filtered_r is a reactive expression so that any output that
    # depends on the filtered data is automatically re-rendered whenever
    # the filter inputs change, without requiring explicit observers.
    filtered_r <- filterServer(
      "filter_mod",
      shiny::reactive({
        update_filtered_data(base_data(), input)
      })
    )

    # (3) observe_reset() registers an observer that resets input controls
    # when the "Reset" button is clicked.  It must be called before the
    # output$ renderers so that the reset takes effect before any downstream
    # reactive recalculation is triggered.
    observe_reset(input, session)
  }
}

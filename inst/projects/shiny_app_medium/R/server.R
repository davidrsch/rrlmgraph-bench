# R/server.R — main server logic with reactives and observers

#' Build the Shiny server function
#'
#' Returns the server closure for the Survey Dashboard.  The server
#' manages reactive data, renders all outputs, and wires up the filter
#' module.
#'
#' @param DATA_PATH Character(1).  Path to the survey CSV file loaded on
#'   startup.  Defaults to a bundled synthetic dataset.
#' @return A function suitable for passing to [shiny::shinyApp()].
#' @export
server_logic <- function(DATA_PATH = NULL) {
  if (is.null(DATA_PATH)) {
    DATA_PATH <- system.file(
      "extdata",
      "survey.csv",
      package = "shinyAppMedium"
    )
  }

  function(input, output, session) {
    # ---- base data (loaded once) -----------------------------------
    base_data <- shiny::reactive({
      df <- load_survey_data(DATA_PATH)
      preprocess_data(df)
    })

    # ---- filter module --------------------------------------------
    filtered_r <- filterServer(
      "filter_mod",
      shiny::reactive({
        update_filtered_data(base_data(), input)
      })
    )

    # ---- reset observer -------------------------------------------
    observe_reset(input, session)

    # ---- outputs --------------------------------------------------
    output$kpi_cards <- shiny::renderUI(compute_kpi_cards(filtered_r()))
    output$hist_plot <- shiny::renderPlot(plot_histogram(filtered_r()))
    output$scatter_plot <- shiny::renderPlot(plot_scatter(filtered_r()))
    output$boxplot <- shiny::renderPlot(plot_boxplot(filtered_r()))
    output$time_series_plot <- shiny::renderPlot(plot_time_series(filtered_r()))
    output$summary_table <- shiny::renderTable(
      render_summary_table(filtered_r()),
      striped = TRUE,
      hover = TRUE
    )
    output$btn_download <- build_download_handler(filtered_r)
  }
}

#' Create a reset-filters observer
#'
#' Watches for clicks on `btn_reset` and resets the date-range,
#' group-select, and score-threshold inputs to their defaults.
#'
#' @param input  Shiny input list.
#' @param session Shiny session object.
#' @return The observer object (invisibly).
#' @export
observe_reset <- function(input, session) {
  shiny::observeEvent(input$btn_reset, {
    shiny::updateDateRangeInput(
      session,
      "date_range",
      start = Sys.Date() - 365L,
      end = Sys.Date()
    )
    shiny::updateSliderInput(session, "score_threshold", value = 0L)
  })
}

#' Apply sidebar filters to the base data frame
#'
#' Filters `df` by the date range, selected groups, and score threshold
#' stored in `input`.
#'
#' @param df     A pre-processed data frame from [preprocess_data()].
#' @param input  Shiny input list with `date_range`, `group_select`, and
#'   `score_threshold` elements.
#' @return A filtered data.frame.
#' @export
update_filtered_data <- function(df, input) {
  # Date range
  if (!is.null(input$date_range)) {
    df <- df[
      df$date >= input$date_range[1L] &
        df$date <= input$date_range[2L],
      ,
      drop = FALSE
    ]
  }

  # Group selection
  if (length(input$group_select) > 0L) {
    df <- df[df$group %in% input$group_select, , drop = FALSE]
  }

  # Score threshold
  if (!is.null(input$score_threshold) && input$score_threshold > 0L) {
    df <- df[df$score >= input$score_threshold, , drop = FALSE]
  }

  df
}

#' Render the summary statistics table
#'
#' Calls [compute_summary_stats()] and formats the result for
#' [shiny::renderTable()].
#'
#' @param df A filtered data.frame.
#' @return A data.frame suitable for table rendering.
#' @export
render_summary_table <- function(df) {
  stats_df <- compute_summary_stats(df)
  stats_df$mean_score <- round(stats_df$mean_score, 2L)
  stats_df$sd_score <- round(stats_df$sd_score, 2L)
  stats_df
}

#' Build the CSV download handler
#'
#' Returns a [shiny::downloadHandler()] that writes the currently
#' filtered data to a CSV file.
#'
#' @param data_r A reactive expression returning the filtered data frame.
#' @return A `shiny::downloadHandler`.
#' @export
build_download_handler <- function(data_r) {
  shiny::downloadHandler(
    filename = function() {
      paste0("survey_data_", format(Sys.Date(), "%Y%m%d"), ".csv")
    },
    content = function(file) {
      utils::write.csv(data_r(), file, row.names = FALSE)
    }
  )
}

#' Compute KPI card UI elements
#'
#' Builds a `shiny::tagList` with three KPI value boxes: total
#' responses, mean score, and number of groups.
#'
#' @param df A filtered data.frame.
#' @return A `shiny.tag` list of KPI cards.
#' @export
compute_kpi_cards <- function(df) {
  n_resp <- nrow(df)
  mean_sc <- if (n_resp > 0L) round(mean(df$score, na.rm = TRUE), 1L) else NA
  n_groups <- length(unique(df$group))

  make_kpi_card <- function(label, value, colour) {
    shiny::column(
      4L,
      shiny::tags$div(
        class = paste0("kpi-card kpi-", colour),
        shiny::tags$h3(value, style = "margin:0; font-size:2em;"),
        shiny::tags$p(label, style = "margin:0; color:#666;")
      )
    )
  }

  shiny::tagList(
    make_kpi_card("Responses", n_resp, "blue"),
    make_kpi_card("Mean Score", mean_sc, "green"),
    make_kpi_card("Groups", n_groups, "orange")
  )
}

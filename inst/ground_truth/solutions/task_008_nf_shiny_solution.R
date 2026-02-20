# Solution for task_008_nf_shiny
# Implement the missing build_download_handler(data_r).
#
# Key decision: use utils::write.csv with row.names = FALSE for
# clean CSV output. The filename includes Sys.Date() so downloaded
# files are unique per day. data_r is called as a reactive expression
# inside the content function.

#' Build a download handler for the filtered survey data
#'
#' Returns a [shiny::downloadHandler()] suitable for wiring to a
#' download button output (e.g. `output$btn_download`).
#'
#' @param data_r A reactive expression returning the current filtered
#'   data frame.
#' @return A `shiny::downloadHandler` object.
#' @export
build_download_handler <- function(data_r) {
  shiny::downloadHandler(
    filename = function() {
      paste0("survey_export_", Sys.Date(), ".csv")
    },
    content = function(con) {
      utils::write.csv(data_r(), con, row.names = FALSE)
    }
  )
}

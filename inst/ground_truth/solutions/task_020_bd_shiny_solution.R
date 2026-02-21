# Solution for task_020_bd_shiny
# Fix reactive dependency loop in observe_reset() using shiny::isolate()

observe_reset <- function(input, session) {
  shiny::observeEvent(input$reset, ignoreInit = TRUE, {
    shiny::updateSliderInput(session, "age_min",
      value = shiny::isolate(formals(server_logic)$age_min_default))
    shiny::updateSliderInput(session, "age_max",
      value = shiny::isolate(formals(server_logic)$age_max_default))
    shiny::updateSelectInput(session, "category", selected = "")
  })
}

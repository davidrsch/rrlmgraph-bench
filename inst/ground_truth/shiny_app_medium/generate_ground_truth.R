# generate_ground_truth.R  —  shiny_app_medium fixture
#
# Run from the rrlmgraph-bench repo root:
#   Rscript inst/ground_truth/shiny_app_medium/generate_ground_truth.R
#
# Manually verified against inst/projects/shiny_app_medium/R/*.R

out_dir <- file.path("inst", "ground_truth", "shiny_app_medium")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ---- 1. function_signatures.rds ----------------------------------------

function_signatures <- c(
  # data.R
  "data::load_survey_data" = "load_survey_data(path)",
  "data::validate_data" = "validate_data(df)",
  "data::preprocess_data" = "preprocess_data(df)",
  "data::compute_summary_stats" = "compute_summary_stats(df)",
  "data::cache_data" = "cache_data(data, key, env = NULL, refresh = FALSE)",
  # ui_components.R
  "ui_components::make_sidebar" = "make_sidebar(groups)",
  "ui_components::make_main_panel" = "make_main_panel()",
  "ui_components::make_title_bar" = "make_title_bar(title)",
  "ui_components::make_about_panel" = "make_about_panel()",
  # module_filter.R
  "module_filter::filterUI" = "filterUI(id)",
  "module_filter::filterServer" = "filterServer(id, data_r)",
  "module_filter::get_filter_choices" = "get_filter_choices(df)",
  # plots.R
  "plots::plot_histogram" = "plot_histogram(df, bins = 30L)",
  "plots::plot_scatter" = "plot_scatter(df)",
  "plots::plot_boxplot" = "plot_boxplot(df)",
  "plots::plot_time_series" = "plot_time_series(df)",
  "plots::theme_app" = "theme_app()",
  "plots::color_palette" = "color_palette(n)",
  # server.R
  "server::server_logic" = "server_logic(DATA_PATH)",
  "server::observe_reset" = "observe_reset(input, session)",
  "server::update_filtered_data" = "update_filtered_data(df, input)",
  "server::render_summary_table" = "render_summary_table(df)",
  "server::build_download_handler" = "build_download_handler(data_r)",
  "server::compute_kpi_cards" = "compute_kpi_cards(df)"
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
    # load_survey_data → validate_data, utils::read.csv
    "data::load_survey_data",
    "data::load_survey_data",
    # validate_data → stop
    "data::validate_data",
    # preprocess_data → validate_data, as.Date, is.na
    "data::preprocess_data",
    "data::preprocess_data",
    "data::preprocess_data",
    # compute_summary_stats → tapply, sd
    "data::compute_summary_stats",
    "data::compute_summary_stats",
    # cache_data (no user-fn calls)

    # make_sidebar → filterUI, shiny::sidebarPanel
    "ui_components::make_sidebar",
    "ui_components::make_sidebar",
    # make_main_panel → make_title_bar
    "ui_components::make_main_panel",

    # filterServer → shiny::moduleServer, update_filtered_data (via reactive)
    "module_filter::filterServer",

    # plot_histogram → theme_app, color_palette, ggplot2::ggplot
    "plots::plot_histogram",
    "plots::plot_histogram",
    "plots::plot_histogram",
    # plot_scatter → theme_app, color_palette, ggplot2::ggplot
    "plots::plot_scatter",
    "plots::plot_scatter",
    "plots::plot_scatter",
    # plot_boxplot → theme_app, color_palette, ggplot2::ggplot
    "plots::plot_boxplot",
    "plots::plot_boxplot",
    "plots::plot_boxplot",
    # plot_time_series → theme_app, color_palette, ggplot2::ggplot
    "plots::plot_time_series",
    "plots::plot_time_series",
    "plots::plot_time_series",

    # server_logic → load_survey_data, filterServer, render_summary_table,
    #                build_download_handler, compute_kpi_cards,
    #                plot_histogram, plot_scatter, plot_boxplot, plot_time_series,
    #                observe_reset, update_filtered_data
    "server::server_logic",
    "server::server_logic",
    "server::server_logic",
    "server::server_logic",
    "server::server_logic",
    "server::server_logic",
    "server::server_logic",
    "server::server_logic",
    "server::server_logic",
    "server::server_logic",
    "server::server_logic",
    # render_summary_table → compute_summary_stats, round
    "server::render_summary_table",
    "server::render_summary_table",
    # compute_kpi_cards (calls shiny::valueBox)
    "server::compute_kpi_cards"
  ),
  to = c(
    "data::validate_data",
    "utils::read.csv",
    "base::stop",
    "data::validate_data",
    "base::as.Date",
    "base::is.na",
    "base::tapply",
    "stats::sd",

    "module_filter::filterUI",
    "shiny::sidebarPanel",
    "ui_components::make_title_bar",

    "shiny::moduleServer",

    "plots::theme_app",
    "plots::color_palette",
    "ggplot2::ggplot",
    "plots::theme_app",
    "plots::color_palette",
    "ggplot2::ggplot",
    "plots::theme_app",
    "plots::color_palette",
    "ggplot2::ggplot",
    "plots::theme_app",
    "plots::color_palette",
    "ggplot2::ggplot",

    "data::load_survey_data",
    "module_filter::filterServer",
    "server::render_summary_table",
    "server::build_download_handler",
    "server::compute_kpi_cards",
    "plots::plot_histogram",
    "plots::plot_scatter",
    "plots::plot_boxplot",
    "plots::plot_time_series",
    "server::observe_reset",
    "server::update_filtered_data",
    "data::compute_summary_stats",
    "base::round",
    "shiny::valueBox"
  ),
  stringsAsFactors = FALSE
)

saveRDS(call_edges, file.path(out_dir, "call_edges.rds"))
message("Wrote call_edges.rds (", nrow(call_edges), " edges)")

# ---- 3. node_relevance_scores.rds --------------------------------------
# Scores 0-3: 0 irrelevant · 1 tangential · 2 relevant · 3 essential

all_nodes <- names(function_signatures)

tasks <- list(
  list(
    query = "How is survey data loaded and validated before processing?",
    scores = setNames(
      c(
        3L,
        3L,
        2L,
        1L,
        1L, # data.R
        0L,
        0L,
        0L,
        0L, # ui_components.R
        0L,
        0L,
        0L, # module_filter.R
        0L,
        0L,
        0L,
        0L,
        0L,
        0L, # plots.R
        1L,
        0L,
        1L,
        0L,
        0L,
        0L
      ), # server.R
      all_nodes
    )
  ),
  list(
    query = "Which functions produce ggplot2 visualisations?",
    scores = setNames(
      c(
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        3L,
        3L,
        3L,
        3L,
        2L,
        1L,
        1L,
        0L,
        0L,
        1L,
        0L,
        1L
      ),
      all_nodes
    )
  ),
  list(
    query = "How does the Shiny filter module work?",
    scores = setNames(
      c(
        0L,
        0L,
        1L,
        0L,
        0L,
        2L,
        0L,
        0L,
        0L,
        3L,
        3L,
        2L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        2L,
        0L,
        2L,
        0L,
        0L,
        0L
      ),
      all_nodes
    )
  ),
  list(
    query = "How are KPI cards and the summary table rendered in the server?",
    scores = setNames(
      c(
        0L,
        0L,
        0L,
        2L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        3L,
        0L,
        0L,
        3L,
        0L,
        3L
      ),
      all_nodes
    )
  ),
  list(
    query = "How is the download CSV handler built?",
    scores = setNames(
      c(
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        0L,
        1L,
        0L,
        1L,
        0L,
        3L,
        0L
      ),
      all_nodes
    )
  )
)

saveRDS(tasks, file.path(out_dir, "node_relevance_scores.rds"))
message("Wrote node_relevance_scores.rds (", length(tasks), " tasks)")

message("\nGround truth generation complete  [shiny_app_medium]")
message("Total functions : ", length(function_signatures))
message("Total call edges: ", nrow(call_edges))
message("Total tasks     : ", length(tasks))

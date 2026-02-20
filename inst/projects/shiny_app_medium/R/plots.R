# R/plots.R — ggplot2 visualisation helpers

#' Plot a histogram of scores
#'
#' Renders a ggplot2 histogram of the `score` column, coloured by
#' `group` and overlaid with a density curve.
#'
#' @param df  A data.frame with `score` and `group` columns.
#' @param bins Integer(1). Number of histogram bins.  Default `30L`.
#' @return A `ggplot` object.
#' @export
plot_histogram <- function(df, bins = 30L) {
  pal <- color_palette(length(unique(df$group)))
  ggplot2::ggplot(df, ggplot2::aes(x = score, fill = group)) +
    ggplot2::geom_histogram(bins = bins, alpha = 0.7, position = "identity") +
    ggplot2::geom_density(
      ggplot2::aes(y = ggplot2::after_stat(count) * (max(df$score) / 10)),
      colour = "black",
      alpha = 0.3
    ) +
    ggplot2::scale_fill_manual(values = pal) +
    ggplot2::labs(
      title = make_plot_title("Score Distribution"),
      x = "Score",
      y = "Count",
      fill = "Group"
    ) +
    theme_app()
}

#' Plot a scatter of score versus date
#'
#' Renders a ggplot2 scatter plot of `score` over `date`, coloured by
#' `group`, with a LOESS smoother per group.
#'
#' @param df A data.frame with `score`, `date`, and `group` columns.
#' @return A `ggplot` object.
#' @export
plot_scatter <- function(df) {
  pal <- color_palette(length(unique(df$group)))
  ggplot2::ggplot(df, ggplot2::aes(x = date, y = score, colour = group)) +
    ggplot2::geom_point(alpha = 0.5, size = 1.5) +
    ggplot2::geom_smooth(method = "loess", se = FALSE, linewidth = 1L) +
    ggplot2::scale_colour_manual(values = pal) +
    ggplot2::labs(
      title = make_plot_title("Score over Time"),
      x = "Date",
      y = "Score",
      colour = "Group"
    ) +
    theme_app()
}

#' Plot a box-plot of of scores by group
#'
#' Renders a ggplot2 box-plot comparing score distributions across groups,
#' with overlaid jitter points.
#'
#' @param df A data.frame with `score` and `group` columns.
#' @return A `ggplot` object.
#' @export
plot_boxplot <- function(df) {
  pal <- color_palette(length(unique(df$group)))
  ggplot2::ggplot(df, ggplot2::aes(x = group, y = score, fill = group)) +
    ggplot2::geom_boxplot(outlier.shape = NA, alpha = 0.6) +
    ggplot2::geom_jitter(width = 0.2, alpha = 0.3, size = 1L) +
    ggplot2::scale_fill_manual(values = pal) +
    ggplot2::labs(
      title = make_plot_title("Score by Group"),
      x = "Group",
      y = "Score"
    ) +
    theme_app() +
    ggplot2::theme(legend.position = "none")
}

#' Plot a weekly time-series of mean scores
#'
#' Aggregates `df` by the `week` column and plots a line chart of
#' mean score per week, with one line per group.
#'
#' @param df A data.frame with `score`, `week`, and `group` columns as
#'   returned by [preprocess_data()].
#' @return A `ggplot` object.
#' @export
plot_time_series <- function(df) {
  agg <- do.call(
    rbind,
    lapply(
      split(df, list(df$week, df$group), drop = TRUE),
      function(sub) {
        data.frame(
          week = sub$week[[1L]],
          group = sub$group[[1L]],
          mean_score = mean(sub$score, na.rm = TRUE),
          stringsAsFactors = FALSE
        )
      }
    )
  )
  agg <- agg[order(agg$week), , drop = FALSE]
  pal <- color_palette(length(unique(agg$group)))

  ggplot2::ggplot(
    agg,
    ggplot2::aes(x = week, y = mean_score, colour = group, group = group)
  ) +
    ggplot2::geom_line(linewidth = 1L) +
    ggplot2::geom_point(size = 2L) +
    ggplot2::scale_colour_manual(values = pal) +
    ggplot2::labs(
      title = make_plot_title("Weekly Mean Score"),
      x = "Week",
      y = "Mean Score",
      colour = "Group"
    ) +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1L)
    ) +
    theme_app()
}

#' Application ggplot2 theme
#'
#' Returns a minimal, clean ggplot2 theme consistent with the Survey
#' Dashboard style guide.
#'
#' @return A `ggplot2::theme` object.
#' @export
theme_app <- function() {
  ggplot2::theme_minimal(base_size = 13L) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 14L),
      legend.position = "bottom",
      panel.grid.minor = ggplot2::element_blank()
    )
}

#' Return a colour palette for n groups
#'
#' Uses a qualitative ColorBrewer-inspired palette, cycling if `n` exceeds
#' the number of built-in colours.
#'
#' @param n Integer(1). Number of distinct colours required.
#' @return A character vector of hex colour strings of length `n`.
#' @export
color_palette <- function(n) {
  base_colours <- c(
    "#4E79A7",
    "#F28E2B",
    "#E15759",
    "#76B7B2",
    "#59A14F",
    "#EDC948",
    "#B07AA1",
    "#FF9DA7",
    "#9C755F",
    "#BAB0AC"
  )
  if (n <= 0L) {
    return(character(0))
  }
  base_colours[((seq_len(n) - 1L) %% length(base_colours)) + 1L]
}

# ---- internal helper ------------------------------------------------

#' Build a formatted plot title with current date hint
#' @keywords internal
make_plot_title <- function(label) {
  paste0(label, "  [", format(Sys.Date(), "%b %Y"), "]")
}

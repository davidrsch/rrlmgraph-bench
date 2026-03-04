#' Compute benchmark statistics from a full results data frame
#'
#' Aggregates per-trial results produced by \code{run_full_benchmark()} into
#' a comprehensive report containing:
#' \itemize{
#'   \item Summary table (mean, SD, 95 \% CI, token counts,
#'         hallucination rate) per strategy.
#'   \item Token Efficiency Ratio (TER) relative to the `"full_files"`
#'         baseline.
#'   \item Pairwise two-sample Welch *t*-tests with Cohen's *d* and
#'         Bonferroni-corrected *p*-values.
#'   \item Mean Normalized Discounted Cumulative Gain (NDCG) where
#'         relevance ranks are available.
#' }
#'
#' When a strategy has fewer than 30 observations, normality is tested
#' with [stats::shapiro.test()].  If `p < 0.05`, bootstrap 95 \%
#' confidence intervals (5 000 resamples) are used instead of the
#' normal-approximation CI.
#'
#' @param all_results A `data.frame` produced by \code{run_full_benchmark()}.
#'   Required columns:
#'   \describe{
#'     \item{`strategy`}{Character. Strategy label.}
#'     \item{`score`}{Numeric in \[0, 1\]. Task score.}
#'     \item{`total_tokens`}{Integer. Total tokens consumed.}
#'     \item{`hallucination_count`}{Integer.}
#'   }
#'   Optional columns for NDCG: `rank`, `relevant`.
#'
#' @return A list with the following elements:
#'   \describe{
#'     \item{`summary`}{`data.frame` with one row per strategy.}
#'     \item{`ter`}{Named numeric vector. TER values; `NA` for the
#'       baseline strategy.}
#'     \item{`pairwise`}{`data.frame` of pairwise Welch t-test results.}
#'     \item{`ndcg`}{Named numeric or `NULL` if rank data absent.}
#'     \item{`wilcoxon`}{`data.frame` of one-sided paired Wilcoxon
#'       signed-rank tests, comparing each strategy against
#'       \code{"bm25_retrieval"} on a per-task basis (mean score
#'       across trials per task).  Columns: \code{strategy},
#'       \code{reference}, \code{V} (test statistic), \code{p_value},
#'       \code{n_pairs}, \code{wins}, \code{ties}, \code{losses}.
#'       \code{NULL} if \code{"bm25_retrieval"} is absent or
#'       \code{task_id} column is missing.}
#'   }
#'
#' @examples
#' \dontrun{
#' results <- run_full_benchmark("inst/tasks", "inst/projects",
#'                               tempfile(fileext = ".rds"))
#' stats   <- compute_benchmark_statistics(results)
#' stats$summary
#' }
#'
#' @importFrom stats sd qt t.test shapiro.test quantile setNames wilcox.test
#' @importFrom utils combn
#' @export
compute_benchmark_statistics <- function(all_results) {
  required_cols <- c("strategy", "score", "total_tokens", "hallucination_count")
  missing_cols <- setdiff(required_cols, names(all_results))
  if (length(missing_cols)) {
    stop(
      "all_results is missing columns: ",
      paste(missing_cols, collapse = ", ")
    )
  }

  # Detect degenerate case: only one trial per strategy.
  # t-tests, SDs, and CIs are undefined with n = 1.
  n_trials_detected <- if ("trial" %in% names(all_results)) {
    max(all_results$trial, na.rm = TRUE)
  } else {
    1L
  }
  if (n_trials_detected < 2L) {
    cli::cli_warn(c(
      "!" = "n_trials = 1: inferential statistics require >= 2 trials.",
      "i" = "Returning point estimates only (no CI, t-tests, or Cohen's d).",
      "i" = "Rerun with n_trials >= 3 for full statistical output."
    ))
  }

  baseline_strategy <- "full_files"
  strategies <- unique(all_results$strategy)

  # ---- 1. Summary table ----------------------------------------------
  summary_rows <- lapply(strategies, function(s) {
    sub_df <- all_results[all_results$strategy == s, , drop = FALSE]
    # Drop NA scores (e.g. rate-limit failures) before all statistics so
    # that a handful of missing rows don't cascade into NA CI / SD.
    scores <- as.numeric(na.omit(sub_df$score))
    n_total <- nrow(sub_df) # for reporting
    n <- length(scores) # effective observations
    if (n == 0L) {
      return(data.frame(
        strategy = s,
        n = n_total,
        mean_score = NA_real_,
        sd_score = NA_real_,
        ci_lo_95 = NA_real_,
        ci_hi_95 = NA_real_,
        mean_total_tokens = mean(sub_df$total_tokens, na.rm = TRUE),
        hallucination_rate = NA_real_,
        ci_method = "none",
        stringsAsFactors = FALSE
      ))
    }
    mu <- mean(scores)
    sigma <- sd(scores)

    # CI selection
    use_bootstrap <- FALSE
    if (n < 30L) {
      sw_p <- tryCatch(
        stats::shapiro.test(scores)$p.value,
        error = function(e) 1
      )
      use_bootstrap <- sw_p < 0.05
    }

    if (use_bootstrap) {
      boot_means <- replicate(5000L, mean(sample(scores, n, replace = TRUE)))
      ci_lo <- quantile(boot_means, 0.025)
      ci_hi <- quantile(boot_means, 0.975)
    } else {
      se <- sigma / sqrt(n)
      t_val <- qt(0.975, df = max(n - 1L, 1L))
      ci_lo <- mu - t_val * se
      ci_hi <- mu + t_val * se
    }

    mean_tokens <- mean(sub_df$total_tokens, na.rm = TRUE)
    hall_rate <- mean(sub_df$hallucination_count > 0L, na.rm = TRUE)

    data.frame(
      strategy = s,
      n = n_total,
      mean_score = mu,
      sd_score = sigma,
      ci_lo_95 = ci_lo,
      ci_hi_95 = ci_hi,
      mean_total_tokens = mean_tokens,
      hallucination_rate = hall_rate,
      ci_method = if (use_bootstrap) "bootstrap" else "t",
      stringsAsFactors = FALSE
    )
  })
  summary_df <- do.call(rbind, summary_rows)
  rownames(summary_df) <- NULL

  # ---- 2. Token Efficiency Ratio (TER) --------------------------------
  # TER_s = (mean_score_s / mean_tokens_s) / (mean_score_baseline / mean_tokens_baseline)
  ter <- setNames(rep(NA_real_, length(strategies)), strategies)
  baseline_row <- summary_df[
    summary_df$strategy == baseline_strategy,
    ,
    drop = FALSE
  ]

  if (nrow(baseline_row) > 0L && baseline_row$mean_total_tokens > 0L) {
    baseline_eff <- baseline_row$mean_score / baseline_row$mean_total_tokens
    for (s in strategies) {
      if (s == baseline_strategy) {
        next
      }
      row_s <- summary_df[summary_df$strategy == s, , drop = FALSE]
      if (row_s$mean_total_tokens > 0L) {
        eff_s <- row_s$mean_score / row_s$mean_total_tokens
        ter[s] <- eff_s / baseline_eff
      }
    }
  }

  # ---- 3. Pairwise tests + Cohen's d (Bonferroni) --------------------
  # Requires variance, so skip when n_trials < 2.
  if (n_trials_detected < 2L) {
    return(list(
      summary = summary_df,
      ter = ter,
      pairwise = NULL,
      ndcg = NULL
    ))
  }

  pairs <- combn(strategies, 2L, simplify = FALSE)
  pairwise_rows <- lapply(pairs, function(p) {
    s1 <- p[1L]
    s2 <- p[2L]
    x1 <- as.numeric(na.omit(all_results$score[all_results$strategy == s1]))
    x2 <- as.numeric(na.omit(all_results$score[all_results$strategy == s2]))
    tt <- tryCatch(
      stats::t.test(x1, x2),
      error = function(e) list(p.value = NA_real_, statistic = NA_real_)
    )
    pooled_sd <- sqrt((stats::var(x1) + stats::var(x2)) / 2)
    cohens_d <- if (!is.na(pooled_sd) && pooled_sd > 0) {
      (mean(x1) - mean(x2)) / pooled_sd
    } else {
      NA_real_
    }
    data.frame(
      strategy_1 = s1,
      strategy_2 = s2,
      p_value_raw = tt$p.value,
      statistic = tt$statistic,
      cohens_d = cohens_d,
      stringsAsFactors = FALSE
    )
  })
  pairwise_df <- do.call(rbind, pairwise_rows)
  if (!is.null(pairwise_df) && nrow(pairwise_df) > 0L) {
    pairwise_df$p_bonferroni <- pmin(
      pairwise_df$p_value_raw * nrow(pairwise_df),
      1
    )
    rownames(pairwise_df) <- NULL
  }

  # ---- 4. Mean NDCG per strategy (#27) -------------------------------
  # Prefer pre-computed ndcg5 / ndcg10 columns (from run_single) over the
  # legacy rank/relevant columns so that new and old result files both work.
  ndcg <- NULL
  if (all(c("ndcg5", "ndcg10") %in% names(all_results))) {
    ndcg5_mean <- tapply(
      all_results$ndcg5,
      all_results$strategy,
      mean,
      na.rm = TRUE
    )
    ndcg10_mean <- tapply(
      all_results$ndcg10,
      all_results$strategy,
      mean,
      na.rm = TRUE
    )
    ndcg <- list(
      ndcg5 = ndcg5_mean[strategies],
      ndcg10 = ndcg10_mean[strategies]
    )
  } else if (all(c("rank", "relevant") %in% names(all_results))) {
    ndcg <- vapply(
      strategies,
      function(s) {
        sub_df <- all_results[all_results$strategy == s, , drop = FALSE]
        if (!nrow(sub_df)) {
          return(NA_real_)
        }
        # Per-query NDCG; assume each row is one retrieved result
        # Group by task_id if available, otherwise treat all as one query
        compute_ndcg <- function(ranks, rels) {
          dcg <- sum(as.numeric(rels) / log2(ranks + 1L), na.rm = TRUE)
          ideal_rels <- sort(as.numeric(rels), decreasing = TRUE)
          idcg <- sum(
            ideal_rels / log2(seq_along(ideal_rels) + 1L),
            na.rm = TRUE
          )
          if (idcg == 0) NA_real_ else dcg / idcg
        }
        if ("task_id" %in% names(sub_df)) {
          per_task <- tapply(
            seq_len(nrow(sub_df)),
            sub_df$task_id,
            FUN = function(idx) {
              compute_ndcg(sub_df$rank[idx], sub_df$relevant[idx])
            }
          )
          mean(per_task, na.rm = TRUE)
        } else {
          compute_ndcg(sub_df$rank, sub_df$relevant)
        }
      },
      FUN.VALUE = numeric(1L)
    )
  }

  # ---- 5. Paired Wilcoxon signed-rank test vs bm25_retrieval (bench#38) --
  # For each strategy, compare per-task mean score against bm25_retrieval
  # using a one-sided paired Wilcoxon signed-rank test (alternative = "greater").
  # Scores are averaged across trials per task to obtain one value per task
  # per strategy.  Only tasks present in both strategies are paired.
  wilcoxon_df <- NULL
  wilcoxon_ref <- "bm25_retrieval"
  if (
    wilcoxon_ref %in%
      strategies &&
      "task_id" %in% names(all_results) &&
      n_trials_detected >= 1L
  ) {
    ref_task_means <- tapply(
      as.numeric(all_results$score[all_results$strategy == wilcoxon_ref]),
      all_results$task_id[all_results$strategy == wilcoxon_ref],
      mean,
      na.rm = TRUE
    )
    wilcoxon_rows <- lapply(setdiff(strategies, wilcoxon_ref), function(s) {
      s_scores <- all_results[all_results$strategy == s, , drop = FALSE]
      s_task_means <- tapply(
        as.numeric(s_scores$score),
        s_scores$task_id,
        mean,
        na.rm = TRUE
      )
      common_tasks <- intersect(names(s_task_means), names(ref_task_means))
      n_pairs <- length(common_tasks)
      if (n_pairs < 2L) {
        return(data.frame(
          strategy = s,
          reference = wilcoxon_ref,
          V = NA_real_,
          p_value = NA_real_,
          n_pairs = n_pairs,
          wins = NA_integer_,
          ties = NA_integer_,
          losses = NA_integer_,
          stringsAsFactors = FALSE
        ))
      }
      x <- as.numeric(s_task_means[common_tasks])
      y <- as.numeric(ref_task_means[common_tasks])
      diff_vec <- x - y
      wins <- sum(diff_vec > 0, na.rm = TRUE)
      ties <- sum(diff_vec == 0, na.rm = TRUE)
      losses <- sum(diff_vec < 0, na.rm = TRUE)
      wt <- tryCatch(
        stats::wilcox.test(x, y, paired = TRUE, alternative = "greater"),
        error = function(e) list(statistic = NA_real_, p.value = NA_real_)
      )
      data.frame(
        strategy = s,
        reference = wilcoxon_ref,
        V = as.numeric(wt$statistic),
        p_value = wt$p.value,
        n_pairs = n_pairs,
        wins = wins,
        ties = ties,
        losses = losses,
        stringsAsFactors = FALSE
      )
    })
    wilcoxon_df <- if (length(wilcoxon_rows) > 0L) {
      do.call(rbind, wilcoxon_rows)
    } else {
      NULL
    }
    if (!is.null(wilcoxon_df)) {
      rownames(wilcoxon_df) <- NULL
    }
  }

  list(
    summary = summary_df,
    ter = ter,
    pairwise = pairwise_df,
    ndcg = ndcg,
    wilcoxon = wilcoxon_df
  )
}

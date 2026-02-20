#' Compute benchmark statistics from a full results data frame
#'
#' Aggregates per-trial results produced by [run_full_benchmark()] into
#' a comprehensive report containing:
#' \itemize{
#'   \item Summary table (mean, SD, 95 \% CI, token counts,
#'         hallucination rate) per strategy.
#'   \item Token Efficiency Ratio (TER) relative to the `"full_files"`
#'         baseline.
#'   \item Pairwise two-sample Welch *t*-tests with Cohen's *d* and
#'         Bonferroni-corrected *p*-values.
#'   \item Mean Normalised Discounted Cumulative Gain (NDCG) where
#'         relevance ranks are available.
#' }
#'
#' When a strategy has fewer than 30 observations, normality is tested
#' with [stats::shapiro.test()].  If `p < 0.05`, bootstrap 95 \%
#' confidence intervals (5 000 resamples) are used instead of the
#' normal-approximation CI.
#'
#' @param all_results A `data.frame` produced by [run_full_benchmark()].
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
#'     \item{`pairwise`}{`data.frame` of pairwise test results.}
#'     \item{`ndcg`}{Named numeric or `NULL` if rank data absent.}
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
#' @importFrom stats sd qt t.test shapiro.test
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

  baseline_strategy <- "full_files"
  strategies <- unique(all_results$strategy)

  # ---- 1. Summary table ----------------------------------------------
  summary_rows <- lapply(strategies, function(s) {
    sub_df <- all_results[all_results$strategy == s, , drop = FALSE]
    scores <- sub_df$score
    n <- length(scores)
    mu <- mean(scores, na.rm = TRUE)
    sigma <- sd(scores, na.rm = TRUE)

    # CI selection
    use_bootstrap <- FALSE
    if (n < 30) {
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
      n = n,
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
  pairs <- combn(strategies, 2L, simplify = FALSE)
  pairwise_rows <- lapply(pairs, function(p) {
    s1 <- p[1L]
    s2 <- p[2L]
    x1 <- all_results$score[all_results$strategy == s1]
    x2 <- all_results$score[all_results$strategy == s2]
    tt <- tryCatch(
      stats::t.test(x1, x2),
      error = function(e) list(p.value = NA_real_, statistic = NA_real_)
    )
    pooled_sd <- sqrt((stats::var(x1) + stats::var(x2)) / 2)
    cohens_d <- if (pooled_sd > 0) {
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

  # ---- 4. Mean NDCG per strategy -------------------------------------
  ndcg <- NULL
  if (all(c("rank", "relevant") %in% names(all_results))) {
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

  list(
    summary = summary_df,
    ter = ter,
    pairwise = pairwise_df,
    ndcg = ndcg
  )
}

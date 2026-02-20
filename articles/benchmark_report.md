# rrlmgraph Benchmark Report

## Overview

This vignette presents a reproducible benchmark comparing six retrieval
strategies for providing R coding context to an LLM:

| Strategy           | Description                                      |
|--------------------|--------------------------------------------------|
| `rrlmgraph_tfidf`  | rrlmgraph graph traversal with TF-IDF embeddings |
| `rrlmgraph_ollama` | rrlmgraph graph traversal with Ollama embeddings |
| `full_files`       | Entire source files dumped verbatim (baseline)   |
| `bm25_retrieval`   | BM25 keyword retrieval (no graph)                |
| `no_context`       | No context supplied                              |
| `random_k`         | Five randomly sampled code chunks                |

Results are loaded from a precomputed RDS file to allow the vignette to
knit without an active LLM API key.

------------------------------------------------------------------------

## Load precomputed results

``` r
results_path <- system.file(
  "results", "benchmark_results.rds",
  package = "rrlmgraphbench"
)

if (file.exists(results_path)) {
  all_results <- readRDS(results_path)
} else {
  message("Pre-computed results not found. Running a dry-run benchmark.")
  all_results <- run_full_benchmark(
    output_path = tempfile(fileext = ".rds"),
    n_trials    = 1L,
    .dry_run    = TRUE
  )
}
#> Pre-computed results not found. Running a dry-run benchmark.
#> [rrlmgraphbench] Starting benchmark: 15 tasks × 6 strategies × 1 trials = 90 runs
#> [1/90] task=task_001_fm_mini_ds strategy=rrlmgraph_tfidf      trial=1 | score=0.500 | est. 3s
#> [2/90] task=task_001_fm_mini_ds strategy=rrlmgraph_ollama     trial=1 | score=0.500 | est. 2s
#> [3/90] task=task_001_fm_mini_ds strategy=full_files           trial=1 | score=0.500 | est. 1s
#> [4/90] task=task_001_fm_mini_ds strategy=bm25_retrieval       trial=1 | score=0.500 | est. 1s
#> [5/90] task=task_001_fm_mini_ds strategy=no_context           trial=1 | score=0.500 | est. 1s
#> [6/90] task=task_001_fm_mini_ds strategy=random_k             trial=1 | score=0.500 | est. 1s
#> [7/90] task=task_002_fm_shiny strategy=rrlmgraph_tfidf      trial=1 | score=0.500 | est. 0s
#> [8/90] task=task_002_fm_shiny strategy=rrlmgraph_ollama     trial=1 | score=0.500 | est. 0s
#> [9/90] task=task_002_fm_shiny strategy=full_files           trial=1 | score=0.500 | est. 0s
#> [10/90] task=task_002_fm_shiny strategy=bm25_retrieval       trial=1 | score=0.500 | est. 0s
#> [11/90] task=task_002_fm_shiny strategy=no_context           trial=1 | score=0.500 | est. 0s
#> [12/90] task=task_002_fm_shiny strategy=random_k             trial=1 | score=0.500 | est. 0s
#> [13/90] task=task_003_fm_rpkg strategy=rrlmgraph_tfidf      trial=1 | score=0.500 | est. 0s
#> [14/90] task=task_003_fm_rpkg strategy=rrlmgraph_ollama     trial=1 | score=0.500 | est. 0s
#> [15/90] task=task_003_fm_rpkg strategy=full_files           trial=1 | score=0.500 | est. 0s
#> [16/90] task=task_003_fm_rpkg strategy=bm25_retrieval       trial=1 | score=0.500 | est. 0s
#> [17/90] task=task_003_fm_rpkg strategy=no_context           trial=1 | score=0.500 | est. 0s
#> [18/90] task=task_003_fm_rpkg strategy=random_k             trial=1 | score=0.500 | est. 0s
#> [19/90] task=task_004_bd_mini_ds strategy=rrlmgraph_tfidf      trial=1 | score=0.500 | est. 0s
#> [20/90] task=task_004_bd_mini_ds strategy=rrlmgraph_ollama     trial=1 | score=0.500 | est. 0s
#> [21/90] task=task_004_bd_mini_ds strategy=full_files           trial=1 | score=0.500 | est. 0s
#> [22/90] task=task_004_bd_mini_ds strategy=bm25_retrieval       trial=1 | score=0.500 | est. 0s
#> [23/90] task=task_004_bd_mini_ds strategy=no_context           trial=1 | score=0.500 | est. 0s
#> [24/90] task=task_004_bd_mini_ds strategy=random_k             trial=1 | score=0.500 | est. 0s
#> [25/90] task=task_005_bd_shiny strategy=rrlmgraph_tfidf      trial=1 | score=0.500 | est. 0s
#> [26/90] task=task_005_bd_shiny strategy=rrlmgraph_ollama     trial=1 | score=0.500 | est. 0s
#> [27/90] task=task_005_bd_shiny strategy=full_files           trial=1 | score=0.500 | est. 0s
#> [28/90] task=task_005_bd_shiny strategy=bm25_retrieval       trial=1 | score=0.500 | est. 0s
#> [29/90] task=task_005_bd_shiny strategy=no_context           trial=1 | score=0.500 | est. 0s
#> [30/90] task=task_005_bd_shiny strategy=random_k             trial=1 | score=0.500 | est. 0s
#> [31/90] task=task_006_bd_rpkg strategy=rrlmgraph_tfidf      trial=1 | score=0.500 | est. 0s
#> [32/90] task=task_006_bd_rpkg strategy=rrlmgraph_ollama     trial=1 | score=0.500 | est. 0s
#> [33/90] task=task_006_bd_rpkg strategy=full_files           trial=1 | score=0.500 | est. 0s
#> [34/90] task=task_006_bd_rpkg strategy=bm25_retrieval       trial=1 | score=0.500 | est. 0s
#> [35/90] task=task_006_bd_rpkg strategy=no_context           trial=1 | score=0.500 | est. 0s
#> [36/90] task=task_006_bd_rpkg strategy=random_k             trial=1 | score=0.500 | est. 0s
#> [37/90] task=task_007_nf_mini_ds strategy=rrlmgraph_tfidf      trial=1 | score=0.500 | est. 0s
#> [38/90] task=task_007_nf_mini_ds strategy=rrlmgraph_ollama     trial=1 | score=0.500 | est. 0s
#> [39/90] task=task_007_nf_mini_ds strategy=full_files           trial=1 | score=0.500 | est. 0s
#> [40/90] task=task_007_nf_mini_ds strategy=bm25_retrieval       trial=1 | score=0.500 | est. 0s
#> [41/90] task=task_007_nf_mini_ds strategy=no_context           trial=1 | score=0.500 | est. 0s
#> [42/90] task=task_007_nf_mini_ds strategy=random_k             trial=1 | score=0.500 | est. 0s
#> [43/90] task=task_008_nf_shiny strategy=rrlmgraph_tfidf      trial=1 | score=0.500 | est. 0s
#> [44/90] task=task_008_nf_shiny strategy=rrlmgraph_ollama     trial=1 | score=0.500 | est. 0s
#> [45/90] task=task_008_nf_shiny strategy=full_files           trial=1 | score=0.500 | est. 0s
#> [46/90] task=task_008_nf_shiny strategy=bm25_retrieval       trial=1 | score=0.500 | est. 0s
#> [47/90] task=task_008_nf_shiny strategy=no_context           trial=1 | score=0.500 | est. 0s
#> [48/90] task=task_008_nf_shiny strategy=random_k             trial=1 | score=0.500 | est. 0s
#> [49/90] task=task_009_nf_rpkg strategy=rrlmgraph_tfidf      trial=1 | score=0.500 | est. 0s
#> [50/90] task=task_009_nf_rpkg strategy=rrlmgraph_ollama     trial=1 | score=0.500 | est. 0s
#> [51/90] task=task_009_nf_rpkg strategy=full_files           trial=1 | score=0.500 | est. 0s
#> [52/90] task=task_009_nf_rpkg strategy=bm25_retrieval       trial=1 | score=0.500 | est. 0s
#> [53/90] task=task_009_nf_rpkg strategy=no_context           trial=1 | score=0.500 | est. 0s
#> [54/90] task=task_009_nf_rpkg strategy=random_k             trial=1 | score=0.500 | est. 0s
#> [55/90] task=task_010_rf_mini_ds strategy=rrlmgraph_tfidf      trial=1 | score=0.500 | est. 0s
#> [56/90] task=task_010_rf_mini_ds strategy=rrlmgraph_ollama     trial=1 | score=0.500 | est. 0s
#> [57/90] task=task_010_rf_mini_ds strategy=full_files           trial=1 | score=0.500 | est. 0s
#> [58/90] task=task_010_rf_mini_ds strategy=bm25_retrieval       trial=1 | score=0.500 | est. 0s
#> [59/90] task=task_010_rf_mini_ds strategy=no_context           trial=1 | score=0.500 | est. 0s
#> [60/90] task=task_010_rf_mini_ds strategy=random_k             trial=1 | score=0.500 | est. 0s
#> [61/90] task=task_011_rf_shiny strategy=rrlmgraph_tfidf      trial=1 | score=0.500 | est. 0s
#> [62/90] task=task_011_rf_shiny strategy=rrlmgraph_ollama     trial=1 | score=0.500 | est. 0s
#> [63/90] task=task_011_rf_shiny strategy=full_files           trial=1 | score=0.500 | est. 0s
#> [64/90] task=task_011_rf_shiny strategy=bm25_retrieval       trial=1 | score=0.500 | est. 0s
#> [65/90] task=task_011_rf_shiny strategy=no_context           trial=1 | score=0.500 | est. 0s
#> [66/90] task=task_011_rf_shiny strategy=random_k             trial=1 | score=0.500 | est. 0s
#> [67/90] task=task_012_rf_rpkg strategy=rrlmgraph_tfidf      trial=1 | score=0.500 | est. 0s
#> [68/90] task=task_012_rf_rpkg strategy=rrlmgraph_ollama     trial=1 | score=0.500 | est. 0s
#> [69/90] task=task_012_rf_rpkg strategy=full_files           trial=1 | score=0.500 | est. 0s
#> [70/90] task=task_012_rf_rpkg strategy=bm25_retrieval       trial=1 | score=0.500 | est. 0s
#> [71/90] task=task_012_rf_rpkg strategy=no_context           trial=1 | score=0.500 | est. 0s
#> [72/90] task=task_012_rf_rpkg strategy=random_k             trial=1 | score=0.500 | est. 0s
#> [73/90] task=task_013_doc_mini_ds strategy=rrlmgraph_tfidf      trial=1 | score=0.500 | est. 0s
#> [74/90] task=task_013_doc_mini_ds strategy=rrlmgraph_ollama     trial=1 | score=0.500 | est. 0s
#> [75/90] task=task_013_doc_mini_ds strategy=full_files           trial=1 | score=0.500 | est. 0s
#> [76/90] task=task_013_doc_mini_ds strategy=bm25_retrieval       trial=1 | score=0.500 | est. 0s
#> [77/90] task=task_013_doc_mini_ds strategy=no_context           trial=1 | score=0.500 | est. 0s
#> [78/90] task=task_013_doc_mini_ds strategy=random_k             trial=1 | score=0.500 | est. 0s
#> [79/90] task=task_014_doc_shiny strategy=rrlmgraph_tfidf      trial=1 | score=0.500 | est. 0s
#> [80/90] task=task_014_doc_shiny strategy=rrlmgraph_ollama     trial=1 | score=0.500 | est. 0s
#> [81/90] task=task_014_doc_shiny strategy=full_files           trial=1 | score=0.500 | est. 0s
#> [82/90] task=task_014_doc_shiny strategy=bm25_retrieval       trial=1 | score=0.500 | est. 0s
#> [83/90] task=task_014_doc_shiny strategy=no_context           trial=1 | score=0.500 | est. 0s
#> [84/90] task=task_014_doc_shiny strategy=random_k             trial=1 | score=0.500 | est. 0s
#> [85/90] task=task_015_doc_rpkg strategy=rrlmgraph_tfidf      trial=1 | score=0.500 | est. 0s
#> [86/90] task=task_015_doc_rpkg strategy=rrlmgraph_ollama     trial=1 | score=0.500 | est. 0s
#> [87/90] task=task_015_doc_rpkg strategy=full_files           trial=1 | score=0.500 | est. 0s
#> [88/90] task=task_015_doc_rpkg strategy=bm25_retrieval       trial=1 | score=0.500 | est. 0s
#> [89/90] task=task_015_doc_rpkg strategy=no_context           trial=1 | score=0.500 | est. 0s
#> [90/90] task=task_015_doc_rpkg strategy=random_k             trial=1 | score=0.500 | est. 0s
#> [rrlmgraphbench] Results saved to: /tmp/Rtmpi4SYBz/file1d6f7ec0b4bb.rds
str(all_results, max.level = 1)
#> 'data.frame':    90 obs. of  12 variables:
#>  $ task_id              : chr  "task_001_fm_mini_ds" "task_001_fm_mini_ds" "task_001_fm_mini_ds" "task_001_fm_mini_ds" ...
#>  $ strategy             : chr  "rrlmgraph_tfidf" "rrlmgraph_ollama" "full_files" "bm25_retrieval" ...
#>  $ trial                : int  1 1 1 1 1 1 1 1 1 1 ...
#>  $ score                : num  0.5 0.5 0.5 0.5 0.5 0.5 0.5 0.5 0.5 0.5 ...
#>  $ context_tokens       : int  0 0 0 0 0 0 0 0 0 0 ...
#>  $ response_tokens      : int  0 0 0 0 0 0 0 0 0 0 ...
#>  $ total_tokens         : int  0 0 0 0 0 0 0 0 0 0 ...
#>  $ latency_sec          : num  0 0 0 0 0 0 0 0 0 0 ...
#>  $ hallucination_count  : int  0 0 0 0 0 0 0 0 0 0 ...
#>  $ hallucination_details: chr  "" "" "" "" ...
#>  $ syntax_valid         : logi  TRUE TRUE TRUE TRUE TRUE TRUE ...
#>  $ runs_without_error   : logi  TRUE TRUE TRUE TRUE TRUE TRUE ...
```

------------------------------------------------------------------------

## Summary statistics

``` r
stats <- compute_benchmark_statistics(all_results)
knitr::kable(
  stats$summary[, c(
    "strategy", "n", "mean_score", "sd_score",
    "ci_lo_95", "ci_hi_95", "mean_total_tokens", "hallucination_rate"
  )],
  digits = 3,
  caption = "Mean score, 95 % CI, token usage, and hallucination rate per strategy."
)
```

| strategy         |   n | mean_score | sd_score | ci_lo_95 | ci_hi_95 | mean_total_tokens | hallucination_rate |
|:-----------------|----:|-----------:|---------:|---------:|---------:|------------------:|-------------------:|
| rrlmgraph_tfidf  |  15 |        0.5 |        0 |      0.5 |      0.5 |                 0 |                  0 |
| rrlmgraph_ollama |  15 |        0.5 |        0 |      0.5 |      0.5 |                 0 |                  0 |
| full_files       |  15 |        0.5 |        0 |      0.5 |      0.5 |                 0 |                  0 |
| bm25_retrieval   |  15 |        0.5 |        0 |      0.5 |      0.5 |                 0 |                  0 |
| no_context       |  15 |        0.5 |        0 |      0.5 |      0.5 |                 0 |                  0 |
| random_k         |  15 |        0.5 |        0 |      0.5 |      0.5 |                 0 |                  0 |

Mean score, 95 % CI, token usage, and hallucination rate per strategy.

------------------------------------------------------------------------

## Score distribution

``` r
# Base-R dot chart sorted by mean score
summary_df <- stats$summary
summary_df <- summary_df[order(summary_df$mean_score, decreasing = TRUE), ]

dotchart(
  summary_df$mean_score,
  labels = summary_df$strategy,
  xlab   = "Mean score (0–1)",
  main   = "Strategy performance",
  pch    = 19,
  col    = "steelblue"
)
segments(
  x0   = summary_df$ci_lo_95,
  x1   = summary_df$ci_hi_95,
  y0   = seq_len(nrow(summary_df)),
  lwd  = 2,
  col  = "steelblue"
)
```

![](benchmark_report_files/figure-html/score-plot-1.png)

------------------------------------------------------------------------

## Token Efficiency Ratio (TER)

TER measures score-per-token relative to the `full_files` baseline. A
TER \> 1 means the strategy achieves a higher score per token consumed.

``` r
ter_df <- data.frame(
  strategy = names(stats$ter),
  TER      = round(stats$ter, 3)
)
ter_df <- ter_df[!is.na(ter_df$TER), ]
ter_df <- ter_df[order(ter_df$TER, decreasing = TRUE), ]
knitr::kable(ter_df,
  row.names = FALSE,
  caption = "Token Efficiency Ratio relative to full_files baseline."
)
```

| strategy | TER |
|----------|-----|

Token Efficiency Ratio relative to full_files baseline.

------------------------------------------------------------------------

## Hallucination analysis

``` r
hall_df <- stats$summary[, c("strategy", "hallucination_rate")]
hall_df$hallucination_rate <- round(hall_df$hallucination_rate, 3)
hall_df <- hall_df[order(hall_df$hallucination_rate), ]
knitr::kable(hall_df,
  row.names = FALSE,
  caption = "Fraction of responses containing at least one hallucination."
)
```

| strategy         | hallucination_rate |
|:-----------------|-------------------:|
| rrlmgraph_tfidf  |                  0 |
| rrlmgraph_ollama |                  0 |
| full_files       |                  0 |
| bm25_retrieval   |                  0 |
| no_context       |                  0 |
| random_k         |                  0 |

Fraction of responses containing at least one hallucination.

Hallucination type breakdown (where available):

``` r
if ("hallucination_details" %in% names(all_results)) {
  details_flat <- unlist(strsplit(
    all_results$hallucination_details[nzchar(all_results$hallucination_details)],
    "; "
  ))
  if (length(details_flat) > 0) {
    type_pattern <- regmatches(
      details_flat,
      regexpr("invented_function|invalid_argument|wrong_namespace", details_flat)
    )
    type_counts <- sort(table(type_pattern), decreasing = TRUE)
    barplot(
      type_counts,
      main = "Hallucination types",
      ylab = "Count",
      col = c("tomato", "goldenrod", "steelblue"),
      names.arg = c("invented\nfunction", "invalid\nargument", "wrong\nnamespace")[
        match(names(type_counts), c("invented_function", "invalid_argument", "wrong_namespace"))
      ]
    )
  } else {
    message("No hallucinations detected in the loaded results.")
  }
}
#> No hallucinations detected in the loaded results.
```

------------------------------------------------------------------------

## Pairwise statistical tests

Welch *t*-tests with Bonferroni correction and Cohen’s *d*.

``` r
pw <- stats$pairwise
if (!is.null(pw) && nrow(pw) > 0) {
  pw$sig <- ifelse(pw$p_bonferroni < 0.001, "***",
    ifelse(pw$p_bonferroni < 0.01, "**",
      ifelse(pw$p_bonferroni < 0.05, "*", "")
    )
  )
  knitr::kable(
    pw[, c(
      "strategy_1", "strategy_2", "statistic",
      "p_value_raw", "p_bonferroni", "cohens_d", "sig"
    )],
    digits = 4,
    caption = "Pairwise Welch t-tests. * p<0.05; ** p<0.01; *** p<0.001 (Bonferroni)."
  )
}
```

| strategy_1       | strategy_2       | statistic | p_value_raw | p_bonferroni | cohens_d | sig |
|:-----------------|:-----------------|----------:|------------:|-------------:|---------:|:----|
| rrlmgraph_tfidf  | rrlmgraph_ollama |        NA |          NA |           NA |       NA | NA  |
| rrlmgraph_tfidf  | full_files       |        NA |          NA |           NA |       NA | NA  |
| rrlmgraph_tfidf  | bm25_retrieval   |        NA |          NA |           NA |       NA | NA  |
| rrlmgraph_tfidf  | no_context       |        NA |          NA |           NA |       NA | NA  |
| rrlmgraph_tfidf  | random_k         |        NA |          NA |           NA |       NA | NA  |
| rrlmgraph_ollama | full_files       |        NA |          NA |           NA |       NA | NA  |
| rrlmgraph_ollama | bm25_retrieval   |        NA |          NA |           NA |       NA | NA  |
| rrlmgraph_ollama | no_context       |        NA |          NA |           NA |       NA | NA  |
| rrlmgraph_ollama | random_k         |        NA |          NA |           NA |       NA | NA  |
| full_files       | bm25_retrieval   |        NA |          NA |           NA |       NA | NA  |
| full_files       | no_context       |        NA |          NA |           NA |       NA | NA  |
| full_files       | random_k         |        NA |          NA |           NA |       NA | NA  |
| bm25_retrieval   | no_context       |        NA |          NA |           NA |       NA | NA  |
| bm25_retrieval   | random_k         |        NA |          NA |           NA |       NA | NA  |
| no_context       | random_k         |        NA |          NA |           NA |       NA | NA  |

Pairwise Welch t-tests. \* p\<0.05; \*\* p\<0.01; \*\*\* p\<0.001
(Bonferroni).

------------------------------------------------------------------------

## Per-project breakdown

``` r
if ("task_id" %in% names(all_results)) {
  # Infer project from task_id (e.g. task_001_fm_mini_ds → mini_ds)
  all_results$project <- sub(
    ".*_(mini_ds|shiny|rpkg).*", "\\1",
    all_results$task_id
  )
  proj_summary <- aggregate(
    score ~ strategy + project,
    data = all_results,
    FUN  = mean
  )
  proj_wide <- reshape(
    proj_summary,
    idvar = "strategy",
    timevar = "project",
    direction = "wide"
  )
  names(proj_wide) <- gsub("score\\.", "", names(proj_wide))
  knitr::kable(
    proj_wide,
    digits  = 3,
    caption = "Mean score disaggregated by fixture project."
  )
}
```

| strategy         | mini_ds | rpkg | shiny |
|:-----------------|--------:|-----:|------:|
| bm25_retrieval   |     0.5 |  0.5 |   0.5 |
| full_files       |     0.5 |  0.5 |   0.5 |
| no_context       |     0.5 |  0.5 |   0.5 |
| random_k         |     0.5 |  0.5 |   0.5 |
| rrlmgraph_ollama |     0.5 |  0.5 |   0.5 |
| rrlmgraph_tfidf  |     0.5 |  0.5 |   0.5 |

Mean score disaggregated by fixture project.

------------------------------------------------------------------------

## Recursive-improvement trajectory

If multi-trial results are available, this plot shows whether score
improves across successive trials (a proxy for benefit from context).

``` r
if ("trial" %in% names(all_results)) {
  trial_means <- aggregate(score ~ strategy + trial,
    data = all_results, FUN = mean
  )
  strategies <- unique(trial_means$strategy)
  cols <- rainbow(length(strategies))
  plot(
    range(trial_means$trial), c(0, 1),
    type = "n",
    xlab = "Trial", ylab = "Mean score",
    main = "Score by trial"
  )
  for (i in seq_along(strategies)) {
    sub <- trial_means[trial_means$strategy == strategies[i], ]
    lines(sub$trial, sub$score, col = cols[i], lwd = 2, type = "b", pch = 19)
  }
  legend("bottomright", legend = strategies, col = cols, lwd = 2, cex = 0.8)
}
```

![](benchmark_report_files/figure-html/improvement-plot-1.png)

------------------------------------------------------------------------

## Session info

``` r
sessionInfo()
#> R version 4.5.2 (2025-10-31)
#> Platform: x86_64-pc-linux-gnu
#> Running under: Ubuntu 24.04.3 LTS
#> 
#> Matrix products: default
#> BLAS:   /usr/lib/x86_64-linux-gnu/openblas-pthread/libblas.so.3 
#> LAPACK: /usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblasp-r0.3.26.so;  LAPACK version 3.12.0
#> 
#> locale:
#>  [1] LC_CTYPE=C.UTF-8       LC_NUMERIC=C           LC_TIME=C.UTF-8       
#>  [4] LC_COLLATE=C.UTF-8     LC_MONETARY=C.UTF-8    LC_MESSAGES=C.UTF-8   
#>  [7] LC_PAPER=C.UTF-8       LC_NAME=C              LC_ADDRESS=C          
#> [10] LC_TELEPHONE=C         LC_MEASUREMENT=C.UTF-8 LC_IDENTIFICATION=C   
#> 
#> time zone: UTC
#> tzcode source: system (glibc)
#> 
#> attached base packages:
#> [1] stats     graphics  grDevices utils     datasets  methods   base     
#> 
#> other attached packages:
#> [1] rrlmgraphbench_0.1.0
#> 
#> loaded via a namespace (and not attached):
#>  [1] digest_0.6.39     desc_1.4.3        R6_2.6.1          fastmap_1.2.0    
#>  [5] xfun_0.56         cachem_1.1.0      knitr_1.51        htmltools_0.5.9  
#>  [9] rmarkdown_2.30    lifecycle_1.0.5   cli_3.6.5         sass_0.4.10      
#> [13] pkgdown_2.2.0     textshaping_1.0.4 jquerylib_0.1.4   systemfonts_1.3.1
#> [17] compiler_4.5.2    tools_4.5.2       ragg_1.5.0        bslib_0.10.0     
#> [21] evaluate_1.0.5    yaml_2.3.12       otel_0.2.0        jsonlite_2.0.0   
#> [25] rlang_1.1.7       fs_1.6.6          htmlwidgets_1.6.4
```

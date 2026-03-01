# rrlmgraph Benchmark Report

## What this benchmark measures

This vignette evaluates how well different **context-retrieval
strategies** help an LLM answer R coding tasks. The benchmark asks:

> *Given a natural-language task description and an R project, which
> retrieval strategy gives an LLM the context it needs to produce
> correct, runnable R code?*

Each strategy is judged by how often the LLM response:

1.  **Parses** as valid R syntax (`syntax_valid`)
2.  **Runs** without error when `eval(parse(...))` is called
    (`runs_without_error`)
3.  **Mentions the right functions** – the fraction of ground-truth node
    names found in the generated code (`nodes_score`)

These three components are combined into a single **composite score**
between 0 and 1:

    score = 0.25 * syntax_valid
          + 0.25 * runs_without_error
          + 0.50 * nodes_score

A score of **1.0** means the response parsed, ran, and referenced every
expected function/object. A score of **0** means it failed on all three.

------------------------------------------------------------------------

## Retrieval strategies compared

| Strategy           | How context is retrieved                                                             | Token cost                |
|--------------------|--------------------------------------------------------------------------------------|---------------------------|
| `rrlmgraph_tfidf`  | Graph traversal: PageRank hubs + TF-IDF similarity to query                          | Low – only relevant nodes |
| `rrlmgraph_ollama` | Graph traversal: PageRank hubs + Ollama vector similarity                            | Low – only relevant nodes |
| `full_files`       | Every source file in the project dumped verbatim (**upper baseline**)                | Very high                 |
| `term_overlap`     | Files ranked by word overlap with the task description (no graph)                    | Medium                    |
| `no_context`       | No code context sent – LLM must answer from training data alone (**lower baseline**) | Zero                      |
| `random_k`         | Five randomly sampled code chunks (random baseline)                                  | Low                       |

The two **baselines** to beat are:

- `no_context` – if a strategy cannot beat this, it is useless.
- `full_files` – if a strategy beats this at lower token cost, graph
  retrieval is providing genuine value.

Results are loaded from `inst/results/benchmark_results.rds`. They are
regenerated automatically every Monday (and on demand) by the
`run-benchmark` CI workflow using GitHub Models (`gpt-4o-mini`).

------------------------------------------------------------------------

## Results

``` r
results_path <- system.file(
  "results", "benchmark_results.rds",
  package = "rrlmgraphbench"
)
results_available <- file.exists(results_path)
if (!results_available) {
  message(
    "benchmark_results.rds not found.\n",
    "Trigger the run-benchmark GitHub Actions workflow to generate results,\n",
    "or run run_full_benchmark() locally with .dry_run = TRUE for a quick test."
  )
} else {
  all_results <- readRDS(results_path)
  knitr::kable(
    head(all_results[, c(
      "task_id", "strategy", "trial", "score",
      "syntax_valid", "runs_without_error", "total_tokens"
    )], 6),
    caption = paste0(
      "First 6 rows of raw results. 'score' is the composite 0-1 metric. ",
      "'syntax_valid' and 'runs_without_error' are 0/1 indicators. ",
      "'total_tokens' is the sum of input + output tokens billed."
    )
  )
}
```

| task_id             | strategy        | trial |     score | syntax_valid | runs_without_error | total_tokens |
|:--------------------|:----------------|------:|----------:|:-------------|:-------------------|-------------:|
| task_001_fm_mini_ds | rrlmgraph_tfidf |     1 | 0.0509434 | FALSE        | FALSE              |          568 |
| task_001_fm_mini_ds | full_files      |     1 | 0.0646154 | FALSE        | FALSE              |         1902 |
| task_001_fm_mini_ds | term_overlap    |     1 | 0.0663934 | FALSE        | FALSE              |          491 |
| task_001_fm_mini_ds | bm25_retrieval  |     1 | 0.0744828 | FALSE        | FALSE              |         1931 |
| task_001_fm_mini_ds | no_context      |     1 | 0.0538318 | FALSE        | FALSE              |          308 |
| task_001_fm_mini_ds | random_k        |     1 | 0.0787500 | FALSE        | FALSE              |         1879 |

First 6 rows of raw results. ‘score’ is the composite 0-1 metric.
‘syntax_valid’ and ‘runs_without_error’ are 0/1 indicators.
‘total_tokens’ is the sum of input + output tokens billed.

------------------------------------------------------------------------

## Summary statistics

Each metric below is averaged across all tasks and trials for a given
strategy.

| Column                  | Meaning                                                                       |
|-------------------------|-------------------------------------------------------------------------------|
| `n`                     | Total trials (tasks x trials per task)                                        |
| `mean_score`            | Average composite score (0-1); higher is better                               |
| `sd_score`              | Standard deviation of per-trial scores                                        |
| `ci_lo_95` / `ci_hi_95` | 95% confidence interval for the mean score                                    |
| `mean_total_tokens`     | Average tokens consumed per trial (input + output)                            |
| `hallucination_rate`    | Fraction of trials where at least one invented function/argument was detected |

``` r
if (results_available) {
  stats <- compute_benchmark_statistics(all_results)
  knitr::kable(
    stats$summary[, c(
      "strategy", "n", "mean_score", "sd_score",
      "ci_lo_95", "ci_hi_95", "mean_total_tokens", "hallucination_rate"
    )],
    digits = 3,
    caption = "Summary: mean score, 95% CI, token usage, and hallucination rate per strategy."
  )
}
#> Warning: ! n_trials = 1: inferential statistics require >= 2 trials.
#> ℹ Returning point estimates only (no CI, t-tests, or Cohen's d).
#> ℹ Rerun with n_trials >= 3 for full statistical output.
```

| strategy        |   n | mean_score | sd_score | ci_lo_95 | ci_hi_95 | mean_total_tokens | hallucination_rate |
|:----------------|----:|-----------:|---------:|---------:|---------:|------------------:|-------------------:|
| rrlmgraph_tfidf |  30 |      0.063 |    0.015 |    0.057 |    0.069 |           634.267 |                  0 |
| full_files      |  30 |      0.069 |    0.020 |    0.062 |    0.077 |          1220.500 |                  0 |
| term_overlap    |  30 |      0.065 |    0.021 |    0.057 |    0.073 |          2150.600 |                  0 |
| bm25_retrieval  |  30 |      0.065 |    0.021 |    0.057 |    0.073 |          2036.533 |                  0 |
| no_context      |  30 |      0.046 |    0.020 |    0.039 |    0.054 |           210.867 |                  0 |
| random_k        |  30 |      0.066 |    0.025 |    0.057 |    0.075 |          2569.400 |                  0 |

Summary: mean score, 95% CI, token usage, and hallucination rate per
strategy.

------------------------------------------------------------------------

## Score distribution (with confidence intervals)

The dot chart below shows each strategy’s mean score. Horizontal bars
are 95% confidence intervals. Strategies are sorted best-to-worst. A
strategy is significantly better than another only if the confidence
intervals do not overlap.

``` r
if (results_available) {
  summary_df <- stats$summary
  summary_df <- summary_df[order(summary_df$mean_score, decreasing = FALSE), ]
  n_s <- nrow(summary_df)
  dotchart(
    summary_df$mean_score,
    labels = summary_df$strategy,
    xlab   = "Mean composite score (0 = worst, 1 = best)",
    main   = "Strategy performance with 95% CI",
    pch    = 19,
    col    = "steelblue",
    xlim   = c(0, 1)
  )
  segments(
    x0  = summary_df$ci_lo_95,
    x1  = summary_df$ci_hi_95,
    y0  = seq_len(n_s),
    lwd = 2,
    col = "steelblue"
  )
  abline(
    v = summary_df$mean_score[summary_df$strategy == "no_context"],
    lty = 2, col = "tomato", lwd = 1
  )
  abline(
    v = summary_df$mean_score[summary_df$strategy == "full_files"],
    lty = 2, col = "darkgreen", lwd = 1
  )
  legend("bottomright",
    legend = c("no_context baseline", "full_files baseline"),
    col = c("tomato", "darkgreen"),
    lty = 2, lwd = 1, cex = 0.8
  )
}
```

![](benchmark_report_files/figure-html/score-plot-1.png)

------------------------------------------------------------------------

## Token Efficiency Ratio (TER)

**TER** = (strategy mean score / strategy mean tokens) / (full_files
mean score / full_files mean tokens).

A **TER \> 1** means the strategy delivers *more score per token* than
dumping the entire project. This is the key metric for assessing whether
graph-based retrieval is worth deploying in production over the
brute-force `full_files` approach.

``` r
if (results_available) {
  ter_df <- data.frame(
    strategy = names(stats$ter),
    TER = round(stats$ter, 3),
    interpretation = ifelse(
      is.na(stats$ter), "N/A (baseline)",
      ifelse(stats$ter > 1,
        "More efficient than full_files",
        "Less efficient than full_files"
      )
    )
  )
  ter_df <- ter_df[order(ter_df$TER, decreasing = TRUE, na.last = TRUE), ]
  knitr::kable(ter_df,
    row.names = FALSE,
    caption = paste0(
      "Token Efficiency Ratio (TER) vs full_files baseline. ",
      "TER > 1: strategy achieves higher score-per-token than full_files. ",
      "TER < 1: strategy is less efficient."
    )
  )
}
```

| strategy        |   TER | interpretation                 |
|:----------------|------:|:-------------------------------|
| no_context      | 3.871 | More efficient than full_files |
| rrlmgraph_tfidf | 1.749 | More efficient than full_files |
| bm25_retrieval  | 0.559 | Less efficient than full_files |
| term_overlap    | 0.532 | Less efficient than full_files |
| random_k        | 0.453 | Less efficient than full_files |
| full_files      |    NA | N/A (baseline)                 |

Token Efficiency Ratio (TER) vs full_files baseline. TER \> 1: strategy
achieves higher score-per-token than full_files. TER \< 1: strategy is
less efficient.

------------------------------------------------------------------------

## Hallucination analysis

A **hallucination** is any invented function name, invalid argument, or
wrong package namespace in the LLM response. Hallucinations make
generated code fail silently or with confusing errors.

``` r
if (results_available) {
  hall_df <- stats$summary[, c("strategy", "hallucination_rate")]
  hall_df$hallucination_rate <- round(hall_df$hallucination_rate, 3)
  hall_df <- hall_df[order(hall_df$hallucination_rate), ]
  hall_df$verdict <- ifelse(
    hall_df$hallucination_rate == 0, "None detected",
    ifelse(hall_df$hallucination_rate < 0.1, "Low (< 10%)",
      ifelse(hall_df$hallucination_rate < 0.25, "Moderate (10-25%)", "High (> 25%)")
    )
  )
  knitr::kable(hall_df,
    row.names = FALSE,
    caption = paste0(
      "Hallucination rate per strategy. ",
      "Defined as: fraction of trials with >= 1 invented function, ",
      "invalid argument, or wrong namespace."
    )
  )
}
```

| strategy        | hallucination_rate | verdict       |
|:----------------|-------------------:|:--------------|
| rrlmgraph_tfidf |                  0 | None detected |
| full_files      |                  0 | None detected |
| term_overlap    |                  0 | None detected |
| bm25_retrieval  |                  0 | None detected |
| no_context      |                  0 | None detected |
| random_k        |                  0 | None detected |

Hallucination rate per strategy. Defined as: fraction of trials with \>=
1 invented function, invalid argument, or wrong namespace.

Hallucination type breakdown (where available):

``` r
if (results_available && "hallucination_details" %in% names(all_results)) {
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
      main = "Hallucination types across all strategies",
      ylab = "Count of occurrences",
      xlab = "Type",
      col = c("tomato", "goldenrod", "steelblue"),
      names.arg = c(
        "Invented\nfunction\n(e.g. foo::bar\nthat doesn't exist)",
        "Invalid\nargument\n(e.g. wrong\nparam name)",
        "Wrong\nnamespace\n(e.g. pkg1::fn\ninstead of pkg2::fn)"
      )[match(
        names(type_counts),
        c("invented_function", "invalid_argument", "wrong_namespace")
      )]
    )
  } else {
    message("No hallucinations detected in the loaded results.")
  }
}
#> No hallucinations detected in the loaded results.
```

------------------------------------------------------------------------

## Pairwise statistical tests

Each pair of strategies is compared using a Welch *t*-test (robust to
unequal variance). P-values are Bonferroni-corrected for multiple
comparisons. **Cohen’s *d*** measures practical effect size: \|d\| \<
0.2 = negligible, 0.2-0.5 = small, 0.5-0.8 = medium, \> 0.8 = large.

``` r
if (results_available) {
  pw <- stats$pairwise
  if (!is.null(pw) && nrow(pw) > 0) {
    pw$sig <- ifelse(pw$p_bonferroni < 0.001, "***",
      ifelse(pw$p_bonferroni < 0.01, "**",
        ifelse(pw$p_bonferroni < 0.05, "*", "ns")
      )
    )
    pw$effect <- ifelse(abs(pw$cohens_d) < 0.2, "negligible",
      ifelse(abs(pw$cohens_d) < 0.5, "small",
        ifelse(abs(pw$cohens_d) < 0.8, "medium", "large")
      )
    )
    knitr::kable(
      pw[, c(
        "strategy_1", "strategy_2", "statistic",
        "p_value_raw", "p_bonferroni", "cohens_d", "sig", "effect"
      )],
      digits = 4,
      caption = paste0(
        "Pairwise Welch t-tests (Bonferroni-corrected). ",
        "sig: ns = not significant, * p<0.05, ** p<0.01, *** p<0.001. ",
        "effect: Cohen's d magnitude."
      )
    )
  } else {
    message("Pairwise tests require n_trials >= 2 per strategy.")
  }
}
#> Pairwise tests require n_trials >= 2 per strategy.
```

------------------------------------------------------------------------

## Per-project breakdown

The benchmark uses three fixture R projects of different types. Breaking
down scores by project shows whether a strategy is robust across project
types or only works for specific ones.

| Project   | Type                | Description                                       |
|-----------|---------------------|---------------------------------------------------|
| `mini_ds` | Data science script | Small data-wrangling project with dplyr / ggplot2 |
| `shiny`   | Shiny application   | Reactive UI with server logic and modules         |
| `rpkg`    | R package           | Package with documented functions and tests       |

``` r
if (results_available && "task_id" %in% names(all_results)) {
  m <- regmatches(
    all_results$task_id,
    regexpr("mini_ds|shiny|rpkg", all_results$task_id)
  )
  all_results$project <- ifelse(
    grepl("mini_ds|shiny|rpkg", all_results$task_id), m, NA_character_
  )
  proj_summary <- aggregate(score ~ strategy + project, data = all_results, FUN = mean)
  proj_wide <- reshape(proj_summary,
    idvar = "strategy",
    timevar = "project", direction = "wide"
  )
  names(proj_wide) <- gsub("score\\.", "", names(proj_wide))
  knitr::kable(
    proj_wide,
    digits = 3,
    caption = paste0(
      "Mean score per strategy per project type. ",
      "A strategy with large differences across projects is not robust."
    )
  )
}
```

| strategy        | mini_ds |  rpkg | shiny |
|:----------------|--------:|------:|------:|
| bm25_retrieval  |   0.076 | 0.063 | 0.055 |
| full_files      |   0.074 | 0.065 | 0.069 |
| no_context      |   0.060 | 0.040 | 0.039 |
| random_k        |   0.079 | 0.061 | 0.058 |
| rrlmgraph_tfidf |   0.063 | 0.063 | 0.063 |
| term_overlap    |   0.076 | 0.065 | 0.054 |

Mean score per strategy per project type. A strategy with large
differences across projects is not robust.

------------------------------------------------------------------------

## Score trajectory across trials

Each task is run `n_trials` times independently. If scores improve
across trials it suggests the LLM benefits from the specific context
being fed (learning effect within context window). Flat lines indicate
consistent performance; downward trends indicate instability.

``` r
if (results_available && "trial" %in% names(all_results)) {
  trial_means <- aggregate(score ~ strategy + trial, data = all_results, FUN = mean)
  strategies <- unique(trial_means$strategy)
  cols <- rainbow(length(strategies))
  plot(range(trial_means$trial), c(0, 1),
    type = "n",
    xlab = "Trial number (independent run)",
    ylab = "Mean composite score (0-1)",
    main = "Score across independent trials -- stability check"
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
#> [1] rrlmgraphbench_0.1.1
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

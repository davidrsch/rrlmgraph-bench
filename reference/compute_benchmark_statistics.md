# Compute benchmark statistics from a full results data frame

Aggregates per-trial results produced by
[`run_full_benchmark()`](https://davidrsch.github.io/rrlmgraph-bench/reference/run_full_benchmark.md)
into a comprehensive report containing:

- Summary table (mean, SD, 95 \\ hallucination rate) per strategy.

- Token Efficiency Ratio (TER) relative to the `"full_files"` baseline.

- Pairwise two-sample Welch *t*-tests with Cohen's *d* and
  Bonferroni-corrected *p*-values.

- Mean Normalized Discounted Cumulative Gain (NDCG) where relevance
  ranks are available.

## Usage

``` r
compute_benchmark_statistics(all_results)
```

## Arguments

- all_results:

  A `data.frame` produced by
  [`run_full_benchmark()`](https://davidrsch.github.io/rrlmgraph-bench/reference/run_full_benchmark.md).
  Required columns:

  `strategy`

  :   Character. Strategy label.

  `score`

  :   Numeric in \[0, 1\]. Task score.

  `total_tokens`

  :   Integer. Total tokens consumed.

  `hallucination_count`

  :   Integer.

  Optional columns for NDCG: `rank`, `relevant`.

## Value

A list with the following elements:

- `summary`:

  `data.frame` with one row per strategy.

- `ter`:

  Named numeric vector. TER values; `NA` for the baseline strategy.

- `pairwise`:

  `data.frame` of pairwise test results.

- `ndcg`:

  Named numeric or `NULL` if rank data absent.

## Details

When a strategy has fewer than 30 observations, normality is tested with
[`stats::shapiro.test()`](https://rdrr.io/r/stats/shapiro.test.html). If
`p < 0.05`, bootstrap 95 \\ confidence intervals (5 000 resamples) are
used instead of the normal-approximation CI.

## Examples

``` r
if (FALSE) { # \dontrun{
results <- run_full_benchmark("inst/tasks", "inst/projects",
                              tempfile(fileext = ".rds"))
stats   <- compute_benchmark_statistics(results)
stats$summary
} # }
```

# rrlmgraphbench <img src="man/figures/logo.svg" align="right" height="139" alt="rrlmgraphbench logo" />

<!-- badges: start -->

[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/davidrsch/rrlmgraph-bench/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/davidrsch/rrlmgraph-bench/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/davidrsch/rrlmgraph-bench/graph/badge.svg)](https://app.codecov.io/gh/davidrsch/rrlmgraph-bench)

<!-- badges: end -->

The goal of `rrlmgraphbench` is to provide an objective, reproducible
benchmark that measures whether `rrlmgraph` context retrieval actually helps
LLMs solve real R coding tasks — and by how much, compared to simpler
baselines. It runs a standard set of coding tasks against six retrieval
strategies, scores each LLM response, and reports mean score, 95 % confidence
intervals, token efficiency, and hallucination rates per strategy. Results
are regenerated automatically every Monday and committed back to the
repository so the GitHub Pages site always shows live data.

## Retrieval strategies compared

| Strategy           | Description                                      |
| ------------------ | ------------------------------------------------ |
| `rrlmgraph_tfidf`  | rrlmgraph graph traversal with TF-IDF embeddings |
| `rrlmgraph_ollama` | rrlmgraph graph traversal with Ollama embeddings |
| `full_files`       | Entire source files dumped verbatim (baseline)   |
| `bm25_retrieval`   | BM25 keyword retrieval, no graph                 |
| `no_context`       | No context supplied                              |
| `random_k`         | Five randomly sampled code chunks                |

## Installation

You can install the development version of `rrlmgraphbench` from GitHub with:

```r
# install.packages("pak")
pak::pak("davidrsch/rrlmgraph-bench")
```

## Example

### Example 1: Run the full benchmark

`run_full_benchmark()` evaluates all six strategies across every task in the
built-in task suite using an LLM of your choice. The `"github"` provider uses
`GITHUB_PAT` (automatically set in GitHub Actions) — no extra secret needed.

```r
library(rrlmgraphbench)

# Full run: GitHub Models, 3 trials per task x strategy pair.
results <- run_full_benchmark(
  output_path  = "results/benchmark_results.rds",
  n_trials     = 3L,
  llm_provider = "github",
  llm_model    = "gpt-4.1-mini"
)
#> ── rrlmgraphbench ──────────────────────────────────────────────────────────────
#> ℹ Tasks   : 15  (5 × fix_method, 5 × new_feature, 5 × bug_diagnosis)
#> ℹ Strategies: 6
#> ℹ Trials  : 3  per strategy × task
#> ───────────────────────────────────────────────────────────────────────────────
#> ✔ [1/90]  rrlmgraph_tfidf  ×  task_001_fm_mini_ds  trial 1  (score 0.8, 1 234 tok, 2.3 s)
#> ✔ [2/90]  rrlmgraph_tfidf  ×  task_001_fm_mini_ds  trial 2  (score 0.8, 1 198 tok, 2.1 s)
#> ...
#> ✔ [90/90] random_k  ×  task_015_doc_rpkg  trial 3  (score 0.4,  892 tok, 1.8 s)
#> ✔ Results saved to results/benchmark_results.rds  (90 rows × 16 cols)

# Quick integration check without calling an LLM (returns dummy 0.5 scores).
dry <- run_full_benchmark(
  output_path = tempfile(fileext = ".rds"),
  .dry_run    = TRUE
)
nrow(dry)
#> [1] 90
```

### Example 2: Compute and inspect benchmark statistics

`compute_benchmark_statistics()` aggregates per-trial scores into a summary
table with 95 % confidence intervals, Token Efficiency Ratio (TER), and
pairwise Welch _t_-tests with Bonferroni correction and Cohen's _d_.

```r
stats <- compute_benchmark_statistics(results)

# Per-strategy summary (ordered by mean score).
stats$summary[order(-stats$summary$mean_score),
              c("strategy", "n", "mean_score", "ci_lo_95", "ci_hi_95",
                "mean_total_tokens", "hallucination_rate")]
#>          strategy  n mean_score ci_lo_95 ci_hi_95 mean_total_tokens hallucination_rate
#>  rrlmgraph_tfidf 45      0.743    0.702    0.784             3 821               0.044
#> rrlmgraph_ollama 45      0.729    0.687    0.771            4 103               0.067
#>    bm25_retrieval 45      0.651    0.608    0.694             6 440               0.111
#>        full_files 45      0.638    0.594    0.682            18 274               0.156
#>          random_k 45      0.547    0.502    0.592             2 108               0.133
#>        no_context 45      0.423    0.378    0.468               187               0.200

# Token Efficiency Ratio: score per token relative to full_files.
# TER > 1 means better score at lower token cost.
stats$ter
#>  rrlmgraph_tfidf rrlmgraph_ollama   bm25_retrieval         random_k       no_context
#>            3.544            2.953            0.977            2.517               NA
```

For pairwise statistical significance:

```r
pw <- stats$pairwise
pw[pw$p_bonferroni < 0.05,
   c("strategy_1", "strategy_2", "cohens_d", "p_bonferroni", "sig")]
#>         strategy_1    strategy_2 cohens_d p_bonferroni sig
#>  rrlmgraph_tfidf    no_context    1.821       <0.001  ***
#> rrlmgraph_ollama    no_context    1.643       <0.001  ***
#>  rrlmgraph_tfidf    full_files    0.423        0.031    *
```

### Example 3: Detect hallucinations in LLM responses

`count_hallucinations()` inspects generated R code for invented function names,
invalid argument names, and wrong-namespace calls. The benchmark calls this
automatically; you can also use it to audit any LLM-generated snippet.

```r
# Invented function and wrong package namespace in the same snippet.
code <- '
  df <- dplyr::filtrate(mtcars, cyl == 6)   # "filtrate" does not exist in dplyr
  result <- xgboost::xgb_train(df)          # "xgb_train" is not exported by xgboost
'

count_hallucinations(code)
#> [[1]]
#> [[1]]$type
#> [1] "wrong_namespace"
#> [[1]]$fn
#> [1] "dplyr::filtrate"
#> [[1]]$detail
#> [1] "'filtrate' is not exported by the 'dplyr' package"
#>
#> [[2]]
#> [[2]]$type
#> [1] "wrong_namespace"
#> [[2]]$fn
#> [1] "xgboost::xgb_train"
#> [[2]]$detail
#> [1] "'xgb_train' is not exported by the 'xgboost' package"

# Pass a graph to also trust project-internal functions.
g <- rrlmgraph::build_rrlm_graph("path/to/mypkg")
count_hallucinations(code, graph = g)
```

## Learn more

- [Benchmark Report](articles/benchmark_report.html) — live results from the latest automated run
- [Reference](reference/index.html) — full function documentation
- [rrlmgraph](https://github.com/davidrsch/rrlmgraph) — the package being benchmarked

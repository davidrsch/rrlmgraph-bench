# Changelog

## rrlmgraphbench 0.1.1

#### Bug fixes

- `run_single()`: LLM responses are now stripped of markdown code fences
  (```` ```r ... ``` ````) before scoring. Without this fix
  `parse(text = response_code)` failed on every GPT-4.1-mini response,
  causing `syntax_valid = FALSE` and `runs_without_error = FALSE` for
  all 146 non-NA benchmark rows; scores were consequently ~0.06 instead
  of the true ~0.3+ range. Adds a new internal helper
  `strip_code_fences()`. (bench#36)

#### Improvements

- [`run_full_benchmark()`](https://davidrsch.github.io/rrlmgraph-bench/reference/run_full_benchmark.md):
  new `strategies` parameter (character vector, defaults to five
  strategies: `rrlmgraph_tfidf`, `full_files`, `term_overlap`,
  `bm25_retrieval`, `no_context`). The previous hardcoded list of six
  non-Ollama strategies produced 180 LLM calls per benchmark run,
  exhausting the GitHub Models free-tier quota (~150 req/day) and
  leaving tasks 026-030 as `NA` in every CI run. The new default of five
  strategies yields exactly 150 calls (30 tasks × 5), staying within the
  free-tier limit. Callers can override `strategies` to run any subset,
  including `"random_k"` when a higher quota is available.

## rrlmgraphbench 0.1.0

First release.

#### Bug fixes

- `run-benchmark.yml` CI workflow: added `models: read` permission so
  that `GITHUB_TOKEN` can call the GitHub Models inference API. Without
  it every
  [`ellmer::chat_github()`](https://ellmer.tidyverse.org/reference/chat_github.html)
  call returned an empty string and all scores were a degenerate `0.6`
  ([\#2](https://github.com/davidrsch/rrlmgraph-bench/issues/2)).
- Removed `[skip ci]` from the auto-commit message so that `pkgdown`
  rebuilds the benchmark report vignette after every results update.
- LLM call failures in `run_single()` now emit a
  [`message()`](https://rdrr.io/r/base/message.html) (was
  [`warning()`](https://rdrr.io/r/base/warning.html)) so they are
  visible in CI logs.

#### Original first-release notes

- Task corpus: 15 coding tasks across three fixture projects (mini
  data-science script, medium Shiny app, small R package), covering
  function-modification, bug-diagnosis, new-feature, refactoring, and
  documentation categories.
- Ground-truth solutions committed under `inst/ground_truth/solutions/`.
- [`run_full_benchmark()`](https://davidrsch.github.io/rrlmgraph-bench/reference/run_full_benchmark.md)
  — evaluate six retrieval strategies against every task.
- [`compute_benchmark_statistics()`](https://davidrsch.github.io/rrlmgraph-bench/reference/compute_benchmark_statistics.md)
  — summary table, TER, pairwise Welch *t*-tests, Cohen’s *d*,
  Bonferroni correction, NDCG.
- [`count_hallucinations()`](https://davidrsch.github.io/rrlmgraph-bench/reference/count_hallucinations.md)
  — detect invented functions, invalid arguments, and wrong-namespace
  references in LLM-generated R code.
- Vignette: `benchmark_report` — reproducible benchmark report using
  precomputed results.

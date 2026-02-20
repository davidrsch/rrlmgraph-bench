# Changelog

## rrlmgraphbench 0.1.0

First release.

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

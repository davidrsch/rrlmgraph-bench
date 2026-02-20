# rrlmgraphbench 0.1.0

First release.

* Task corpus: 15 coding tasks across three fixture projects (mini data-science
  script, medium Shiny app, small R package), covering function-modification,
  bug-diagnosis, new-feature, refactoring, and documentation categories.
* Ground-truth solutions committed under `inst/ground_truth/solutions/`.
* `run_full_benchmark()` — evaluate six retrieval strategies against every task.
* `compute_benchmark_statistics()` — summary table, TER, pairwise Welch
  *t*-tests, Cohen's *d*, Bonferroni correction, NDCG.
* `count_hallucinations()` — detect invented functions, invalid arguments,
  and wrong-namespace references in LLM-generated R code.
* Vignette: `benchmark_report` — reproducible benchmark report using
  precomputed results.

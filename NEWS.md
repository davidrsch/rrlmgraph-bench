# rrlmgraphbench 0.1.0

First release.

### Bug fixes

* `run-benchmark.yml` CI workflow: added `models: read` permission so that
  `GITHUB_TOKEN` can call the GitHub Models inference API.  Without it
  every `ellmer::chat_github()` call returned an empty string and all scores
  were a degenerate `0.6` (#2).
* Removed `[skip ci]` from the auto-commit message so that `pkgdown` rebuilds
  the benchmark report vignette after every results update.
* LLM call failures in `run_single()` now emit a `message()` (was `warning()`)
  so they are visible in CI logs.

### Original first-release notes

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

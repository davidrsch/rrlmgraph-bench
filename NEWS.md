# rrlmgraphbench (development version)

### CI / workflow

- `run-benchmark.yml` now runs **daily** (was weekly) with a version-bump gate:
  - A cheap `check-version` job fetches the remote rrlmgraph `DESCRIPTION`
    and compares the `Version:` field to `inst/last-benchmarked-rrlmgraph-version.txt`.
  - On scheduled runs, the heavy `benchmark` job is skipped (and all its
    ~8 min of Node / Ollama / R setup) when the version has not changed.
  - Manual `workflow_dispatch` always bypasses the gate. A `force_run`
    boolean input is also provided for explicit overrides.
  - If the remote version cannot be fetched (network failure), the gate
    **defaults to running** (fail-open) so a version bump is never silently missed.
  - The version stamp file is written **after** a successful benchmark run only.
    A failed run does not advance the stamp, so the next scheduled run retries.
  - Benchmark commit messages now include the rrlmgraph version for traceability
    (e.g. `chore: update benchmark results [rrlmgraph 0.1.2]`).

### Bug fixes

- `mcp_read_response()`: fixed two bugs that silently disabled the
  `rrlmgraph_mcp` strategy in every benchmark run:
  1. `processx::process$poll_io()` returns keys `"output"` and `"error"`
     on all platforms, but the code was testing `ready[["stdout"]]`,
     throwing `"subscript out of bounds"` in R and causing the outer
     `tryCatch` in `mcp_start_server()` to return `NULL`, which made
     `build_context()` return empty context for every MCP task.
  2. The `initialize` JSON-RPC request sent `"capabilities":[]` (an
     empty JSON **array**) instead of `"capabilities":{}` (an empty
     **object**). The Zod schema in the MCP SDK rejects arrays, so the server
     returned a `-32603` error before the fix was applied. The same fix
     is applied to the `notifications/initialized` `params` field.
     Together these two bugs caused `rrlmgraph_mcp` scores to equal
     `no_context` (mean ~0.689) in the n=2 benchmark results. (bench#30)

- `run_full_benchmark()`: the `rrlmgraph_mcp` strategy now starts a fresh
  MCP server **per task** rather than one global server per run. The
  previous design called `mcp_start_server()` with `projects_dir` (the
  parent of all task project directories) as `project_path`, but
  `better-sqlite3` could not create `graph.sqlite` there on read-only CI
  paths, causing a silent crash before the JSON-RPC initialize handshake
  completed. Each task now: (1) exports its TF-IDF graph to a temporary
  SQLite file via `rrlmgraph::export_to_sqlite()`, (2) starts an MCP
  server with the correct per-task `--project-path` and `--db-path`, and
  (3) kills the server and deletes the temp file after all trials complete.
  Fixes the `rrlmgraph_mcp` strategy being silently dropped from all CI
  benchmark runs. (bench#30)

- `run_full_benchmark()` workflow: bumped `n_trials` from 1 to 2 so the
  paired Wilcoxon test has 60 task-pairs instead of 30, making it possible
  to reach statistical significance (p < 0.05).

### Improvements

- `mcp_start_server()`: added `db_path` parameter. When supplied,
  `--db-path <db_path>` is passed to the Node.js process, allowing the
  caller to point the MCP server at an existing SQLite export rather than
  the default `<project_path>/.rrlmgraph/graph.sqlite` location.

# rrlmgraphbench 0.1.1

### Bug fixes

- `run_single()`: LLM responses are now stripped of markdown code fences
  (` ```r ... ``` `) before scoring. Without this fix `parse(text =
response_code)` failed on every GPT-4.1-mini response, causing
  `syntax_valid = FALSE` and `runs_without_error = FALSE` for all 146
  non-NA benchmark rows; scores were consequently ~0.06 instead of the
  true ~0.3+ range. Adds a new internal helper `strip_code_fences()`.
  (bench#36)

### Improvements

- `run_full_benchmark()`: new `strategies` parameter (character vector,
  defaults to five strategies: `rrlmgraph_tfidf`, `full_files`,
  `term_overlap`, `bm25_retrieval`, `no_context`). The previous hardcoded
  list of six non-Ollama strategies produced 180 LLM calls per benchmark
  run, exhausting the GitHub Models free-tier quota (~150 req/day) and
  leaving tasks 026-030 as `NA` in every CI run. The new default of five
  strategies yields exactly 150 calls (30 tasks × 5), staying within the
  free-tier limit. Callers can override `strategies` to run any subset,
  including `"random_k"` when a higher quota is available.

# rrlmgraphbench 0.1.0

First release.

### Bug fixes

- `run-benchmark.yml` CI workflow: added `models: read` permission so that
  `GITHUB_TOKEN` can call the GitHub Models inference API. Without it
  every `ellmer::chat_github()` call returned an empty string and all scores
  were a degenerate `0.6` (#2).
- Removed `[skip ci]` from the auto-commit message so that `pkgdown` rebuilds
  the benchmark report vignette after every results update.
- LLM call failures in `run_single()` now emit a `message()` (was `warning()`)
  so they are visible in CI logs.

### Original first-release notes

- Task corpus: 15 coding tasks across three fixture projects (mini data-science
  script, medium Shiny app, small R package), covering function-modification,
  bug-diagnosis, new-feature, refactoring, and documentation categories.
- Ground-truth solutions committed under `inst/ground_truth/solutions/`.
- `run_full_benchmark()` — evaluate six retrieval strategies against every task.
- `compute_benchmark_statistics()` — summary table, TER, pairwise Welch
  _t_-tests, Cohen's _d_, Bonferroni correction, NDCG.
- `count_hallucinations()` — detect invented functions, invalid arguments,
  and wrong-namespace references in LLM-generated R code.
- Vignette: `benchmark_report` — reproducible benchmark report using
  precomputed results.

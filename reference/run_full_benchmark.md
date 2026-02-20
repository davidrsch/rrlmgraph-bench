# Run the full rrlmgraph benchmark

Evaluates six retrieval strategies across every task in `tasks_dir`
using `n_trials` independent trials each, and persists the combined
results to `output_path`.

## Usage

``` r
run_full_benchmark(
  tasks_dir = system.file("tasks", package = "rrlmgraphbench"),
  projects_dir = system.file("projects", package = "rrlmgraphbench"),
  output_path,
  n_trials = 3L,
  seed = 42L,
  .dry_run = FALSE
)
```

## Arguments

- tasks_dir:

  Path to the directory containing task JSON files (default:
  `system.file("tasks", package = "rrlmgraphbench")`).

- projects_dir:

  Path to the directory containing benchmark project source trees
  (default: `system.file("projects", package = "rrlmgraphbench")`).

- output_path:

  File path where the resulting `data.frame` is saved as an RDS file.
  Parent directories are created if needed.

- n_trials:

  Integer(1). Number of independent trials per task x strategy pair.
  Defaults to `3L`.

- seed:

  Integer(1). Random seed passed to
  [`base::set.seed()`](https://rdrr.io/r/base/Random.html) before any
  stochastic operations. Defaults to `42L`.

- .dry_run:

  Logical(1). When `TRUE` the LLM is not called; dummy scores of `0.5`
  are returned. Useful for integration tests.

## Value

A `data.frame` (saved to `output_path` and also returned invisibly) with
one row per trial, containing columns:

- `task_id`:

  Character.

- `strategy`:

  Character.

- `trial`:

  Integer.

- `score`:

  Numeric in \[0, 1\].

- `context_tokens`:

  Integer.

- `response_tokens`:

  Integer.

- `total_tokens`:

  Integer.

- `latency_sec`:

  Numeric.

- `hallucination_count`:

  Integer.

- `hallucination_details`:

  List column (character vectors).

- `syntax_valid`:

  Logical.

- `runs_without_error`:

  Logical.

## Details

### Strategies

|                    |                                           |
|--------------------|-------------------------------------------|
| Label              | Description                               |
| `rrlmgraph_tfidf`  | rrlmgraph with TF-IDF node embeddings     |
| `rrlmgraph_ollama` | rrlmgraph with Ollama-backed embeddings   |
| `full_files`       | Dump every source file in full (baseline) |
| `bm25_retrieval`   | BM25 keyword retrieval (no graph)         |
| `no_context`       | No context provided to the LLM            |
| `random_k`         | *k* randomly sampled code chunks          |

LLM calls are issued through
[`ellmer::parallel_chat()`](https://ellmer.tidyverse.org/reference/parallel_chat.html)
for concurrency. A progress message is emitted after each task x
strategy combination together with a rolling time estimate.

## Examples

``` r
if (FALSE) { # \dontrun{
results <- run_full_benchmark(
  output_path = "inst/results/benchmark_results.rds",
  n_trials    = 3L,
  seed        = 42L
)
head(results)
} # }
```

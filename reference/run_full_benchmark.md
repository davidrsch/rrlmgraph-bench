# Run the full rrlmgraph benchmark

Evaluates seven retrieval strategies across every task in `tasks_dir`
using `n_trials` independent trials each, and persists the combined
results to `output_path`.

## Usage

``` r
run_full_benchmark(
  tasks_dir = system.file("tasks", package = "rrlmgraphbench"),
  projects_dir = system.file("projects", package = "rrlmgraphbench"),
  output_path,
  n_trials = 3L,
  llm_provider = c("github", "openai", "anthropic", "ollama"),
  llm_model = NULL,
  seed = 42L,
  rate_limit_delay = 6,
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

- llm_provider:

  Character(1). LLM provider passed to ellmer. One of `"github"`
  (default), `"openai"`, `"anthropic"`, `"ollama"`.

- llm_model:

  Character(1) or `NULL`. Model name. When `NULL` a sensible
  per-provider default is used: `"gpt-4o-mini"` for `"github"` and
  `"openai"`, `"claude-3-5-haiku-latest"` for `"anthropic"`,
  `"llama3.2"` for `"ollama"`.

- seed:

  Integer(1). Random seed passed to
  [`base::set.seed()`](https://rdrr.io/r/base/Random.html) before any
  stochastic operations. Defaults to `42L`.

- rate_limit_delay:

  Numeric(1). Seconds to wait between LLM API calls to avoid rate-limit
  errors. Defaults to `6`.

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

  Integer. API-reported input token count when available; falls back to
  [`tokenizers::count_words()`](https://docs.ropensci.org/tokenizers/reference/word-counting.html)
  or `nchar/4`.

- `response_tokens`:

  Integer. API-reported output token count; same fallback chain as
  `context_tokens`.

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

- `retrieved_n`:

  Integer. Nodes retrieved by rrlmgraph strategies; `0L` for non-graph
  strategies.

- `ndcg5`:

  Numeric. NDCG\\5 against `ground_truth_nodes` for rrlmgraph
  strategies; `NA_real_` otherwise.

- `ndcg10`:

  Numeric. NDCG\\10; same conditions as `ndcg5`.

## Details

### Strategies

|                    |                                                       |
|--------------------|-------------------------------------------------------|
| Label              | Description                                           |
| `rrlmgraph_tfidf`  | rrlmgraph with TF-IDF node embeddings                 |
| `rrlmgraph_ollama` | rrlmgraph with Ollama-backed embeddings               |
| `full_files`       | Dump every source file in full (baseline)             |
| `term_overlap`     | Simple term-presence keyword retrieval (no graph)     |
| `bm25_retrieval`   | True BM25 retrieval – IDF-weighted, length-normalised |
| `no_context`       | No context provided to the LLM                        |
| `random_k`         | *k* randomly sampled code chunks                      |

LLM calls are issued sequentially via ellmer. A progress message is
emitted after each task x strategy combination together with a rolling
time estimate.

## Authentication

- `"github"` (default):

  Uses `GITHUB_PAT` / `GITHUB_TOKEN`. In GitHub Actions this is set
  automatically as `secrets.GITHUB_TOKEN` – no extra secret needed.

- `"openai"`:

  Requires `OPENAI_API_KEY`.

- `"anthropic"`:

  Requires `ANTHROPIC_API_KEY`.

- `"ollama"`:

  No key needed (local daemon).

## Examples

``` r
if (FALSE) { # \dontrun{
# Uses GitHub Models (GITHUB_TOKEN auto-set in Actions -- no secret needed)
results <- run_full_benchmark(
  output_path = "inst/results/benchmark_results.rds",
  n_trials    = 3L
)
head(results)
} # }
```

# rrlmgraphbench <img src="man/figures/logo.svg" align="right" height="139" alt="rrlmgraphbench logo" />

> Benchmark suite for evaluating `rrlmgraph` retrieval strategies against
> real R coding tasks.

## Overview

`rrlmgraphbench` provides a reproducible benchmark that compares six
context-retrieval strategies across 15 coding tasks spanning three fixture
project types. It measures context quality through LLM-graded task scores,
token efficiency, and hallucination rates.

## Retrieval strategies compared

| Strategy           | Description                                   |
| ------------------ | --------------------------------------------- |
| `rrlmgraph_tfidf`  | rrlmgraph graph traversal + TF-IDF embeddings |
| `rrlmgraph_ollama` | rrlmgraph graph traversal + Ollama embeddings |
| `full_files`       | Entire source files verbatim (baseline)       |
| `bm25_retrieval`   | BM25 keyword retrieval (no graph)             |
| `no_context`       | No context supplied                           |
| `random_k`         | Five randomly sampled code chunks             |

## Installation

```r
# install.packages("pak")
pak::pak("davidrsch/rrlmgraph-bench")
```

## Learn more

See the [Benchmark Report](articles/benchmark_report.html) vignette for
a full reproducible analysis, and the [Reference](reference/index.html) for
function documentation.

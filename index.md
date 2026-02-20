# rrlmgraphbench

> Benchmark suite for evaluating `rrlmgraph` retrieval strategies
> against real R coding tasks.

## Overview

`rrlmgraphbench` provides a reproducible benchmark that compares six
context-retrieval strategies across 15 coding tasks spanning three
fixture project types. It measures context quality through LLM-graded
task scores, token efficiency, and hallucination rates.

## Retrieval strategies compared

| Strategy           | Description                                   |
|--------------------|-----------------------------------------------|
| `rrlmgraph_tfidf`  | rrlmgraph graph traversal + TF-IDF embeddings |
| `rrlmgraph_ollama` | rrlmgraph graph traversal + Ollama embeddings |
| `full_files`       | Entire source files verbatim (baseline)       |
| `bm25_retrieval`   | BM25 keyword retrieval (no graph)             |
| `no_context`       | No context supplied                           |
| `random_k`         | Five randomly sampled code chunks             |

## Installation

``` r
# install.packages("pak")
pak::pak("davidrsch/rrlmgraph-bench")
```

## Learn more

See the [Benchmark
Report](https://davidrsch.github.io/rrlmgraph-bench/articles/benchmark_report.md)
vignette for a full reproducible analysis, and the
[Reference](https://davidrsch.github.io/rrlmgraph-bench/reference/index.md)
for function documentation.

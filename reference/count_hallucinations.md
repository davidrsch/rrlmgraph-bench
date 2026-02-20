# Count hallucinations produced by an LLM in a generated code snippet

Parses `code` using [`base::parse()`](https://rdrr.io/r/base/parse.html)
and walks the resulting AST to find:

1.  **Invented functions** – calls to names that appear neither in the
    rrlmgraph call-graph (`graph`) nor in the current R session via
    [`getAnywhere()`](https://rdrr.io/r/utils/getAnywhere.html).

2.  **Invalid arguments** – named arguments that are not listed in
    [`base::formals()`](https://rdrr.io/r/base/formals.html) for the
    target function (only checked when the function can be resolved in
    session).

3.  **Wrong-package namespace calls** – `pkg::fn()` references where
    `fn` does not actually export `fn`.

Non-standard-evaluation column references (bare names inside `dplyr`
verbs, `data.table` indexing, or formula RHS) are **not** flagged; the
detector only inspects calls whose first element is a symbol.

## Usage

``` r
count_hallucinations(code, graph = NULL)
```

## Arguments

- code:

  Character(1). R source code, as returned by the LLM.

- graph:

  An `rrlm_graph` object built over the target project, or `NULL`
  (default). When provided, function names present as nodes in the graph
  are trusted even if not loadable in the current session.

## Value

A named list; each element represents one detected hallucination with
fields:

- `type`:

  Character. One of `"invented_function"`, `"invalid_argument"`, or
  `"wrong_namespace"`.

- `fn`:

  Character. The function name involved.

- `detail`:

  Character. Human-readable explanation.

Returns an empty list when no hallucinations are found.

## Examples

``` r
code <- "result <- xyzzy_nonexistent_fn(mtcars, foo = 1)"
count_hallucinations(code)
#> [[1]]
#> [[1]]$type
#> [1] "invented_function"
#> 
#> [[1]]$fn
#> [1] "xyzzy_nonexistent_fn"
#> 
#> [[1]]$detail
#> [1] "'xyzzy_nonexistent_fn' could not be found in the R session or the project graph."
#> 
#> 
```

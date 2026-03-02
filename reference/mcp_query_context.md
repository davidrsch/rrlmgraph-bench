# Call the MCP `query_context` tool and return `list(chunks, node_ids)`. Returns an empty result on error or timeout (with a `warning()`).

Call the MCP `query_context` tool and return `list(chunks, node_ids)`.
Returns an empty result on error or timeout (with a
[`warning()`](https://rdrr.io/r/base/warning.html)).

## Usage

``` r
mcp_query_context(
  query,
  seed_node,
  budget_tokens,
  mcp_state,
  timeout_ms = 30000L
)
```

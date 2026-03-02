# Poll the stdout of an MCP server process until a JSON-RPC response matching `id` is received, or until `timeout_ms` milliseconds elapse. Returns the parsed response list, or `NULL` on timeout.

Poll the stdout of an MCP server process until a JSON-RPC response
matching `id` is received, or until `timeout_ms` milliseconds elapse.
Returns the parsed response list, or `NULL` on timeout.

## Usage

``` r
mcp_read_response(proc, id, timeout_ms = 30000L)
```

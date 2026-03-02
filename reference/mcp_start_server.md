# Start the rrlmgraph-mcp Node.js server, perform the MCP initialize handshake, and return a mutable state environment with `$proc` and `$next_id`. Returns `NULL` with a `cli_warn()` if Node.js is absent, the `dist/index.js` file is missing, or the initialization handshake times out.

Start the rrlmgraph-mcp Node.js server, perform the MCP initialize
handshake, and return a mutable state environment with `$proc` and
`$next_id`. Returns `NULL` with a `cli_warn()` if Node.js is absent, the
`dist/index.js` file is missing, or the initialization handshake times
out.

## Usage

``` r
mcp_start_server(mcp_dir, project_path, timeout_ms = 10000L)
```

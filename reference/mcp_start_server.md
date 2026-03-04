# Start the rrlmgraph-mcp Node.js server, perform the MCP initialize handshake, and return a mutable state environment with `$proc` and `$next_id`. Returns `NULL` with a `cli_warn()` if Node.js is absent, the `dist/index.js` file is missing, or the initialization handshake times out.

Start the rrlmgraph-mcp Node.js server, perform the MCP initialize
handshake, and return a mutable state environment with `$proc` and
`$next_id`. Returns `NULL` with a `cli_warn()` if Node.js is absent, the
`dist/index.js` file is missing, or the initialization handshake times
out.

## Usage

``` r
mcp_start_server(mcp_dir, project_path, db_path = NULL, timeout_ms = 10000L)
```

## Arguments

- mcp_dir:

  Path to the rrlmgraph-mcp checkout (must contain `dist/index.js`).

- project_path:

  Path to the R project root (passed as `--project-path`).

- db_path:

  Optional path to an existing `graph.sqlite`. When supplied it is
  passed as `--db-path`, overriding the default
  `<project_path>/.rrlmgraph/graph.sqlite` lookup. Use this to supply a
  temporary SQLite export created by `rrlmgraph::export_to_sqlite()` for
  per-task benchmarking.

- timeout_ms:

  Handshake timeout in milliseconds (default 10\\000).

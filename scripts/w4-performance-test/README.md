# W4 performance test (k6)

This directory contains a small harness to do **simple performance testing** of the same W4 application under multiple domains, both **with default caching behavior** and **with explicit no-cache headers**.

It works in two steps:

1. Generate a stable list of **50 internal paths** by crawling `https://www4.uib.no/`.
2. Replay those same paths against each target domain twice:
   - `cacheMode=cached`
   - `cacheMode=no-cache` (adds `Cache-Control/Pragma/Expires` headers)

## Requirements

- `node` (Node.js 18+ recommended; needs built-in `fetch`)
- `k6` installed locally (`k6 run ...`)
- Network access to the domains you want to test

## Quick start

Generate paths:

```bash
node ./scripts/w4-performance-test/generate-paths.mjs
```

Run k6:

```bash
k6 run ./scripts/w4-performance-test/perf.js
```

Artifacts are written to `scripts/w4-performance-test/out/` (gitignored), and a readable summary is also printed to stdout.

## What it tests

Default domains tested (override with `DOMAINS` if you want):

- `www4.uib.no`
- `w4.test.uib.no`
- `w4.bgo1.prod.rail.uib.no`
- `w4-novarnish.bgo1.test.rail.uib.no`
- `w4.bgo1.test.rail.uib.no`

Each domain is tested with both cache modes, using the same set of paths from `paths.json`.

## Tunables (environment variables)

### Path generation (`generate-paths.mjs`)

- **`START_URL`**: starting point (default `https://www4.uib.no/`)
- **`MAX_PATHS`**: number of unique paths to collect (default `50`)
- **`MAX_PAGES`**: maximum number of pages to fetch while crawling (default `200`)
- **`OUT_FILE`**: output file path (default `./scripts/w4-performance-test/paths.json`)

Example (generate only 10 paths, faster):

```bash
MAX_PATHS=10 MAX_PAGES=50 node ./scripts/w4-performance-test/generate-paths.mjs
```

### Load test (`perf.js`)

- **`DOMAINS`**: comma-separated domain list to test (defaults to the 5 domains above)
- **`PATHS_FILE`**: JSON file to read paths from (default `./scripts/w4-performance-test/paths.json`)
  - Supported formats: either `{ "paths": ["/", ...] }` or a plain `["/", ...]` array.
- **`MAX_PATHS`**: cap number of paths used from `PATHS_FILE` (default `50`)
- **`PROTO`**: `https` or `http` (default `https`)
- **`TIMEOUT`**: request timeout (default `30s`)
- **`BATCH_SIZE`**: requests per `http.batch()` chunk (default `10`)
- **`SLEEP_BETWEEN_BATCH_MS`**: sleep between batches (default `0`)
- **`VUS`**: k6 VUs (default `1`)
- **`ITERATIONS`**: k6 iterations (default `1`)
- **`RPS`** + (**`DURATION`** or **`DURATION_S`**): enable **rate mode** (spread requests over time)\n  - `RPS=10 DURATION=300s` means 10 requests/second for 300 seconds.\n  - In rate mode, each k6 iteration performs exactly 1 request (round-robin across domain × cacheMode × path).\n  - Optional: `PREALLOCATED_VUS`, `MAX_VUS` to control the executor.\n - **`OUT_DIR`**: where summaries are written (default `./scripts/w4-performance-test/out`)
- **`OUT_DIR`**: where summaries are written (default `./scripts/w4-performance-test/out`)

Example (quick smoke test on 5 paths):

```bash
MAX_PATHS=5 k6 run ./scripts/w4-performance-test/perf.js
```

Example (test only two domains):

```bash
DOMAINS="www4.uib.no,w4.test.uib.no" k6 run ./scripts/w4-performance-test/perf.js
```

Example (run over time, 10 RPS for 300 seconds):

```bash
RPS=10 DURATION=300s k6 run ./scripts/w4-performance-test/perf.js
```

## Output

The k6 run prints a readable per-domain summary to stdout and also writes:

- `summary-<timestamp>.md`
- `summary-<timestamp>.json`

to the output directory (`OUT_DIR`).

## Notes

- `no-cache` mode adds client-side cache control headers. This is not the same as disabling server-side caches (e.g. Varnish), but it’s useful to compare “best effort” client no-cache behavior against the default.\n
- The repo includes an empty `out/.gitkeep` so the directory exists; outputs inside `out/` are intentionally not committed.

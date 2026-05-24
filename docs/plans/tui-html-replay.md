# TUI & HTML session replay

## Overview

Garazyk records scenario dashboard sessions for visual playback (asciicast v2) and
logical harness replay (`replay.jsonl`), plus a persisted HTML run timeline from
`RunEvent` rows.

## TUI (`@garazyk/tui/testing`)

| Module | Purpose |
|--------|---------|
| `cast.ts` | Parse/serialize asciicast v2 |
| `recorder.ts` | `CastRecorder`, `TuiSessionRecorder`, `attachRecorder` |
| `replay.ts` | `replayScript()` for deterministic tests |
| `replay_types.ts` | `ReplayStep` / `replay.jsonl` |

Record live TUI:

```bash
cd scripts/scenario-dashboard
deno task tui:record
# or
deno run -A tui.ts --record=path/to/session.cast
```

## Dashboard

- `GET /api/runs/:id/events` — timeline JSON
- `GET /api/runs/:id/tui-cast` — asciicast when `run_dir/tui/dashboard.cast` exists
- Run detail page: timeline scrubber + asciinema player + logs

Export standalone bundle:

```bash
cd scripts/scenario-dashboard
deno task export-run -- <runId>
# or open in browser from run detail → Export replay
# GET /api/runs/:id/export
```

Writes `run_dir/export/index.html` plus `dashboard.cast` and `events.json`.

## Timeline ↔ logs

- `log_line` events store `at` (epoch ms) and `lineIndex` when emitted by RunManager
- Timeline scrubber maps offset → log line via `lib/timeline.ts`
- Mirror stream: `run_dir/events.ndjson` (append-only, one event per line)

## Playwright traces (dashboard browser tests)

On failure, `runBrowserTest` saves `trace-*.zip` under `test-results/traces/` (override with `GARAZYK_DASHBOARD_TRACE_DIR`). Open at [trace.playwright.dev](https://trace.playwright.dev/).

## Artifacts

| Path | Format |
|------|--------|
| `run_dir/tui/dashboard.cast` | asciicast v2 |
| `run_dir/tui/dashboard.cast.replay.jsonl` | logical replay (when cast path set) |
| `run_dir/export/index.html` | offline viewer |
| SQLite `run_events` | `RunEvent` timeline |

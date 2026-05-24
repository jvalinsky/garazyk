---
name: garazyk-scenario-dashboard
description: "Fresh/Preact web app + TUI dashboard for the Garazyk Deno scenario runner. Covers Fresh layout, islands, components, TUI mode, SQLite DB integration, state management, and development commands."
---

# Garazyk Scenario Dashboard

The Scenario Dashboard is a full-featured Fresh/Preact web application and interactive Terminal User Interface (TUI) designed to monitor, analyze, and control the 92+ E2E scenario integration tests in Garazyk.

## When to Use

- Build, extend, or debug the scenario dashboard interface (web or TUI)
- Manage local dashboard state or database queries (`dashboard.db`)
- Intercept and parse run commands via the built-in command interpreter
- Verify integration between the hamownia runner and the dashboard server

## Architecture Overview

Location: `scripts/scenario-dashboard/`

```
db/                         — SQLite database schemas & run migrations
components/                 — Preact visual primitives & layout elements
islands/                    — Interactive components (RunControl, LogViewer, LiveStats)
routes/                     — Fresh filesystem-based routing (Web UI)
services/                   — Backend logic for telemetry ingestion & scenario scheduling
static/                     — Static stylesheets & client assets
cmd_interpreter.ts          — Parses interactive sub-commands for scenario running
dashboard_state.ts          — Central state machine tracking current/historical test runs
runtime.ts                  — OS-level process controls & service wrappers
tui.ts                      — Interactive terminal UI rendering panel
```

## Quick Start (Development)

Run dashboard tasks inside `scripts/scenario-dashboard/` or via root shortcuts:

```bash
# Human / local development
cd scripts/scenario-dashboard && deno task dev
# Or from repo root: deno task dashboard:dev

# Cursor / automation (Agent checkbox enabled on load)
cd scripts/scenario-dashboard && deno task dev:agent
# Or from repo root: deno task dashboard:dev:agent
# If the server is already running: open http://localhost:3001/?agentLaunch=1

# Start interactive Terminal UI (TUI) mode
cd scripts/scenario-dashboard && deno task tui
# Or from repo root: deno task dashboard:tui

# Build production assets for deployment
cd scripts/scenario-dashboard && deno task build

# Preview production build locally
cd scripts/scenario-dashboard && deno task preview
```

## Database Schema & State

The dashboard persists run history to a local SQLite database at `scripts/scenarios/reports/dashboard.db` using the raw `sqlite3` Deno bindings:

- **Runs Table**: Tracks `run_id`, `start_time`, `end_time`, `overall_status`, and `git_commit`.
- **Scenarios Table**: Tracks individual scenario results per run.
- **Steps Table**: Logs exact steps inside a scenario including `duration_ms` and `error_message`.
- **Logs Table**: Real-time stdin/stdout capture of service output during scenario execution.

## Key APIs & Integration Patterns

### 1. DashboardState (`dashboard_state.ts`)
Tracks current monorepo state, parses JSON telemetry frames on the fly, and exposes reactive Preact signals for live updates.

```ts
import { DashboardState } from "./dashboard_state.ts";

const state = new DashboardState(dbPath);
await state.loadInitialState();

// Subscribe to live run telemetry
state.on("run-update", (run) => {
  console.log(`Run ${run.id}: ${run.status}`);
});
```

### 2. TUI Rendering (`tui.ts` / `tui_test.ts`)
Leverages `@garazyk/tui` primitives to rasterize full-screen grid layouts directly onto `Deno.stdout`.

```ts
import { solveLayout, dashboardLayoutTree } from "@garazyk/tui";
import { rasterize } from "@garazyk/tui";

const nodes = solveLayout(dashboardLayoutTree(), w, h);
// ... renders progress bar, active logs, and service status boxes ...
```

### 3. Command Interpreter (`cmd_interpreter.ts`)
Supports inline shell commands to run, filter, or triage tests interactively:

```ts
import { CommandInterpreter } from "./cmd_interpreter.ts";

const interpreter = new CommandInterpreter(state);
const result = await interpreter.execute("run 01 06 --keep-running");
```

## Session replay

- **TUI recording:** `deno task tui:record` or `--record=path.cast` (asciicast v2 under `reports/tui-sessions/`)
- **Run timeline:** `run_events` table + `GET /api/runs/:id/events`
- **TUI playback:** place `tui/dashboard.cast` under `run_dir`; run detail shows asciinema player
- **Export:** `deno task export-run -- <runId>` → `run_dir/export/index.html`

See `docs/plans/tui-html-replay.md`.

## Related Skills

- **agent-scenario-testing** — CLI subcommands that feed data into the dashboard
- **garazyk-hamownia** — scenario runner producing the NDJSON logs parsed by the dashboard
- **garazyk-tui** — visual rendering library driving TUI mode
- **garazyk-laweta** — Docker compose runtime monitored by the dashboard

# Scenario Dashboard — Fix Plan

Date: 2026-05-13
Scope: `scripts/scenario-dashboard/`

## Triage summary

22 issues identified during review, grouped into three tiers:

- **P0 (broken on main flow)**: 4 items
- **P1 (visible UI/UX defects)**: 7 items
- **P2 (incomplete features, dead code, polish)**: 11 items

The dashboard renders, but several headline interactions silently fail or display incorrect data. The first priority is making the data the dashboard *does* show actually correct, then making the buttons it exposes actually work, then trimming the rest.

---

## 2026-05-24 implementation update

Commit: `b27b3982` (`Fix scenario dashboard run state and network health`)

This pass handled the visible regression cluster reported from the dashboard screenshots rather than the whole May 13 backlog:

- Fixed stale run progress rendering by reading polled progress state and using `finishedAt`/`stoppedAt` for completed elapsed time.
- Added the missing recent-runs API route and refreshed recent runs after terminal run events.
- Normalized persisted run timestamps from run IDs when stored epochs are bogus, preventing 2016/2017 display for 2026 run IDs.
- Normalized network API route responses to arrays so web and TUI runtimes interpret service status consistently.
- Seeded host-mode network service state from topology defaults so the dashboard does not show `0/0 services` before Docker discovery succeeds.
- Reworked runner-aware host/docker start/stop handling and reduced expected binary-service startup probe noise.
- Reconciled stale running rows at dashboard startup and skipped non-scenario JSON artifacts during report import.
- Added focused dashboard persistence, runner, and run-detail tests.

Verification:

- `deno check scripts/scenario-dashboard/main.ts`
- `deno test -A scripts/scenario-dashboard`
- `deno test -A packages/laweta/docker_health_test.ts`

Remaining from this plan:

- Several May 13 P1/P2 polish items remain open, especially sidebar/mobile behavior, JSON report links, per-service controls, and deeper browser visual QA.
- Docker-mode should be re-smoked with live Docker logs if connection failures persist after the runner-aware network fixes.

---

## P0 — Wrong data or broken primary flows

### P0.1 Sidebar status dots are dead (prop name mismatch)
**File**: `routes/index.tsx:96`, `components/Sidebar.tsx:67-77`
**Symptom**: Every scenario in the sidebar shows the "stopped" (grey) dot regardless of last-run status.
**Cause**: Route passes `latestStatus`; component reads `lastStatus`.
**Fix**: In `routes/index.tsx`, when building `scenarios` for the Sidebar, map `latestStatus` → `lastStatus`. Or rename in `Sidebar`'s `ScenarioMeta` to `latestStatus` and update the JSX. Prefer the latter for consistency with `ScenarioCard`.
**Test**: Load `/`, sidebar dots should match badge colors on cards.

### P0.2 "Run All" button is permanently broken
**File**: `islands/Toolbar.tsx:11`, `routes/api/scenarios.ts:25-30`
**Symptom**: Clicking "Run All ▾" never starts a run.
**Cause**: Island POSTs `{ ids: [] }`; the API returns 400 on empty IDs.
**Fix**: Two options:
  1. **Server-side**: Treat empty `ids` as "run all discovered scenarios" — call `getScenarios()` in the handler when `ids.length === 0`.
  2. **Client-side**: Have the island GET `/api/scenarios` first, then POST with the full ID list.
**Recommend**: option 1 (one round-trip, simpler client).
**Test**: Click Run All → check `runs` table for a new row, dashboard redirects somewhere sensible (TBD — currently the island doesn't navigate).

### P0.3 "Latest result per scenario" SQL is wrong
**File**: `routes/index.tsx:51-56`
**Symptom**: Per-scenario badges and passed/failed counts on the dashboard cards may show data from a non-latest run.
**Cause**: `GROUP BY scenario_id HAVING started_at = MAX(started_at)` doesn't pin the projected columns to the row at `MAX(started_at)` in SQLite — the engine picks an arbitrary row per group.
**Fix**: Replace with a window-function query:
```sql
SELECT scenario_id, status, passed, failed, skipped
FROM (
  SELECT scenario_id, status, passed, failed, skipped,
         ROW_NUMBER() OVER (PARTITION BY scenario_id ORDER BY started_at DESC) AS rn
  FROM scenario_results
)
WHERE rn = 1
```
Or a correlated subquery if window functions aren't available in the bundled SQLite.
**Test**: Run scenario 01, observe pass; deliberately fail it, observe latest now shows fail — currently this is non-deterministic.

### P0.4 Runs are stuck in `status='running'` on failure
**File**: `routes/api/scenarios.ts:48-65`
**Symptom**: If the spawned `run_scenarios.ts` crashes before writing reports, the inserted `runs` row stays as `status='running'` forever.
**Cause**: The IIFE ignores `code` from `command.output()` and `scanReports` won't see any reports to import.
**Fix**:
- After `await command.output()`, check `code`. On non-zero, `UPDATE runs SET status='error', finished_at=? WHERE id=?`.
- After `scanReports(db)`, if the run record is still `status='running'` and `now - startedAt > N`, mark it `error`.
- Wrap the IIFE in try/catch so spawn errors mark the run as error too.
**Test**: Force a failure (e.g., invalid scenario id with a bad shell) and confirm DB row reflects `error`.

---

## P1 — Visible UI/UX defects

### P1.1 Network sidebar dot is always green
**File**: `components/Sidebar.tsx:53`
**Symptom**: "N/M services" always shows a green dot, even when N=0.
**Fix**: Compute the dot class:
- 0 running → `stopped`
- 0 < N < M → `skipped` (yellow)
- N === M → `running` (green)

### P1.2 Dashboard "summary cards" mix data from different runs
**File**: `routes/index.tsx:88-90`
**Symptom**: The top-of-page Passed/Failed/Skipped totals sum the *latest* result for each scenario — but those latests come from different runs. The number is incoherent.
**Fix**: Replace with the most recent `runs` row's `passed/failed/skipped` columns. Pull from `runs[0]` (already queried, ordered DESC). Add a small label like "Latest run · 2026-05-13 14:22".
**Optional**: Add a second row with all-time totals if useful.

### P1.3 "Skipped" uses the warning icon
**File**: `components/ScenarioCard.tsx:13-18`, `components/StepRow.tsx:10-14`
**Symptom**: Skipped steps look like errors. Visually noisy.
**Fix**: Use a neutral glyph (`–` or `⊝`) and the `badge-secondary` class for skipped, reserve `badge-warning` for transient/yellow states like "starting" or "unhealthy". Keep `step-icon.skipped` color as warning amber if you want it slightly visible, but de-emphasize.

### P1.4 ScenarioCard badge has no "running" variant
**File**: `components/ScenarioCard.tsx:30-33`
**Symptom**: A live-running scenario renders as a yellow `badge-warning` with the ⟳ icon — looks like a warning.
**Fix**: Add explicit mapping: `running → badge-info` (define `badge-info` in CSS using `--color-info`). Add a subtle spin animation on the ⟳ icon for the running state.

### P1.5 Scenario detail badge is two-state only
**File**: `routes/scenario/[id].tsx:141-143`
**Symptom**: Skipped runs render as red `badge-destructive`.
**Fix**: Three-way mapping consistent with other components:
```tsx
const klass = status === "passed" ? "badge-success"
            : status === "failed" ? "badge-destructive"
            : "badge-secondary";
```

### P1.6 Run detail page omits headline metadata
**File**: `routes/run/[runId].tsx:63-118`
**Symptom**: The page queries `startedAt`, `finishedAt`, `durationS`, `status`, `pds2`, `binaryMode` but renders none of them.
**Fix**: Add a header block above the summary cards:
- Started: formatted local date/time
- Duration: e.g. "2m 14s"
- Status: badge (`completed`/`running`/`error`)
- Flags: `PDS2`, `binary mode` chips if true
- Refresh indicator when `status === 'running'` (poll every 5s)

### P1.7 Run detail shows no progress when run is in-flight
**File**: `routes/run/[runId].tsx:95-110`
**Symptom**: Immediately after kicking off a run, `ScenarioRunner` redirects to `/run/{id}` where `scenarioResults` is empty. The page shows zeros with no explanation.
**Fix**:
- When `run.status === 'running'`, render a "Running..." banner with an animated indicator.
- Add a small island that polls `/api/runs/{id}` (need to create this endpoint) every 3s and refreshes the page when status changes to `completed` or `error`.

---

## P2 — Dead code, incomplete features, polish

### P2.1 SSE/event bus is never delivered to clients
**File**: `services/event_bus.ts`, `services/network_manager.ts:208`
**Decision needed**: Either (a) build SSE endpoint and subscribe in islands, or (b) delete `event_bus.ts` and trim `emit()` calls.
**Recommend**: (b) for now — 5s polling already covers the use case. Defer SSE until log streaming is actually needed.

### P2.2 Per-service start/stop/logs are no-ops
**File**: `islands/NetworkStatus.tsx:57-67, 138`
**Decision needed**: Either implement `routes/api/network/[name]/{start,stop,logs}.ts` + wire `streamLogs`, or hide the per-row buttons.
**Recommend**: For initial cleanup, remove the per-row Start/Stop/Log buttons and the corresponding `streamLogs` method. Bring them back when there's a real use case.

### P2.3 "View Full Report JSON" button has no handler
**File**: `routes/scenario/[id].tsx:172-174`
**Fix**: Add an API route `routes/api/runs/[runId]/scenario/[scenarioId].json` that returns the raw `steps_json` / `artifacts_json` blob, and make the button an `<a>` linking to it (target=_blank). Or remove the button until needed.

### P2.4 Filter input is decorative
**File**: `islands/Toolbar.tsx:23-28`
**Fix**:
- Add a signal in the island for the filter query.
- Either: (a) hoist to a higher-level island that contains the grid, or (b) write the filter to `URLSearchParams` and reload (cheaper architecturally for Fresh).
- Recommend (b): set `?q=foo`, server-side filter in `routes/index.tsx`.

### P2.5 `components/Toolbar.tsx` is dead
**File**: `components/Toolbar.tsx`
**Fix**: Delete — the island version is canonical.

### P2.6 `routes/api/runs.ts` is unused
**File**: `routes/api/runs.ts`
**Fix**: Either consume it from `RunHistory` (turn it into an island that polls), or delete. Recommend delete for now; the SSR list is fine.

### P2.7 `NAME_TO_ID` map and `/runs/` filter in `report_scanner.ts` are dead
**File**: `services/report_scanner.ts:33-46, 83`
**Fix**: Delete both. The `^(\d+)` regex always matches; the `/runs/` substring can never appear in a bare filename from `Deno.readDir`.

### P2.8 `discoverRunningServices` spawns 2 subprocesses every 10s
**File**: `services/network_manager.ts:40-103, 158-160`
**Fix**:
- Move `discoverRunningServices` out of the hot path. Run it once at startup, then only when a state transition happens or on explicit refresh.
- Or: keep it but cache for 30s.

### P2.9 `_health` endpoint coverage unverified
**File**: `services/network_manager.ts:165-170`
**Fix**: Audit each service's actual health endpoint and update the URL switch. Some likely candidates:
- AppView: `/xrpc/_health` or similar
- PLC: `/_health` (probably works)
- Video: TBD
- Admin UI: probably no health endpoint, just a 200 on `/`
**Test**: Start the stack, hit `/api/network/health`, every service should show `healthy: true`.

### P2.10 `db/index.ts` runs `await scanReports` at module load
**File**: `db/index.ts:12`
**Symptom**: Cold start slows as reports accumulate. Any scanReports exception crashes module init.
**Fix**:
- Wrap in try/catch and log.
- Defer to a background `setTimeout(scanReports, 0)` so the dashboard can start serving requests immediately.

### P2.11 Inline styles + responsive gaps
**Files**: many components
**Fix** (low priority):
- Extract repeated inline patterns to CSS classes: `.empty-state`, `.section-back-link`, `.section-header-row`.
- Mobile (<768px): add a hamburger button in the toolbar that toggles the sidebar instead of hiding it entirely.
- Reconsider the 1200px max-width on data-heavy pages (network table, run detail).

---

## Suggested execution order

1. **Sprint 1 — Correctness (P0)**: 1.1, 1.2, 1.3, 1.4. Half a day. Unblocks trust in the UI.
2. **Sprint 2 — UX truth (P1)**: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7. One day. Makes the dashboard read correctly.
3. **Sprint 3 — Trim (P2.1, P2.2, P2.5, P2.6, P2.7)**: Half a day. Delete dead code and stub buttons before they tempt future readers.
4. **Sprint 4 — Optional**: P2.3, P2.4, P2.8, P2.9, P2.10, P2.11. Spread over future work.

## Out of scope for this plan

- Replacing SQLite with a different store.
- Adding authentication.
- Real-time log streaming (defer until P2.2 is reconsidered).
- Test coverage — currently zero tests in `scenario-dashboard/`; worth a separate plan.

## Open questions

1. Should "Run All" default to with-PDS2 or without? Currently the island sends `pds2: undefined`.
2. Should the dashboard refuse to start a run when the network is `stopped`? Currently it blindly passes `--no-setup`.
3. Is anyone using `routes/api/runs.ts` from outside the dashboard? If yes, keep; if no, delete.

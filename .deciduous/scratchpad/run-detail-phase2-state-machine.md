# Phase 2: State Machine — Msgs, overlay state, update handler

## Goal
Add the TEA state machine pieces for the run detail overlay.

## Changes

### 1. `dashboard_state.ts` — New state fields

Add to `DashboardState.runs`:
```ts
detailRunId: string | null;       // which run is being viewed
detailResults: ScenarioResult[];   // fetched results
detailCursor: number;              // cursor position in scenario list
detailScrollOffset: number;        // scroll offset for scenario list
```

### 2. `dashboard_state.ts` — New Msg variants

```ts
{ type: "runs/viewDetail"; runId: string }
{ type: "runs/closeDetail" }
{ type: "runs/detailResults"; results: ScenarioResult[] }
{ type: "runs/detailCursorUp" }
{ type: "runs/detailCursorDown" }
```

### 3. `dashboard_state.ts` — Update handler

- `runs/viewDetail`: sets `detailRunId`, issues Cmd to fetch results
- `runs/closeDetail`: clears `detailRunId`, `detailResults`, `detailCursor`, `detailScrollOffset`
- `runs/detailResults`: stores results, clamps cursor
- `runs/detailCursorUp/Down`: moves cursor, adjusts scroll offset

### 4. Cmd for fetching results

Add a Cmd that fetches `/api/runs/:id/results` and dispatches `runs/detailResults`.

## Verification
- `deno check` on dashboard_state.ts

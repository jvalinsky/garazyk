# Phase 4: Key Handling + TUI Integration

## Goal
Wire the overlay into the TUI event loop — Enter opens it, overlay captures keys, Esc closes.

## Changes

### 1. `tui.ts` — Enter key on History panel

In `handleHistoryKey()`, add:
```ts
if (isKey(key, Keys.ENTER)) {
  const selectedRun = getSelectedRun(recentRuns, panelStates.history);
  if (selectedRun) {
    runtime.dispatch({ type: "runs/viewDetail", runId: selectedRun.id });
  }
  return true;
}
```

### 2. `tui.ts` — Overlay key capture mode

When `runtime.state.runs.detailRunId !== null`, the main key loop should:
- Skip all panel-specific key handling
- Route keys to overlay handler instead:
  - ↑/k: `runs/detailCursorUp`
  - ↓/j: `runs/detailCursorDown`
  - Esc/q: `runs/closeDetail`
  - Enter: future (step detail), for now no-op

### 3. `tui.ts` — Pass overlay state to renderView

The `renderAndWrite()` call needs to pass `state.runs.detailRunId !== null`
so `renderView` can render the overlay.

### 4. `tui/view.ts` — Update hint bar for overlay mode

When overlay is active, the hint bar should show overlay-specific hints:
`↑↓ Navigate  Esc Close`

## Verification
- `deno check` on tui.ts and view.ts
- Manual: run dashboard, select a failed run, press Enter, verify overlay appears
- Manual: press Esc, verify overlay closes
- Manual: ↑↓ moves cursor, scroll follows

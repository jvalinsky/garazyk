# Phase 3: TEA Integration — Bridge Events to State Machine

## Problem

The TUI runtime interprets `Cmd.fetch` as service method calls and uses `Cmd.schedule`
for polling loops. Even with Phase 2's events, the state machine still generates polling
Cmds that the TUI runtime must execute (and discard). The 50ms render timer is a hack
to work around the blocking `readKeys()` loop.

## Approach

1. **Add `runs/event` Msg variant** to `dashboard_state.ts`:
   ```typescript
   | { type: "runs/event"; event: RunEvent }
   ```

2. **Add `update()` case for `runs/event`** — translates `RunEvent` into state changes:
   - `run_started` → set active run, clear progress
   - `scenario_started` → update currentScenario
   - `scenario_finished` → update progressByRunId, increment completed
   - `run_completed` → set final status, clear active, add to recentRuns
   - `log_line` → append to `logs.textByRunId`

3. **Subscribe TUI runtime to RunManager events** in `createTuiRuntime()`:
   ```typescript
   const unsubscribe = runManager.onEvent((event) => {
     dispatch({ type: "runs/event", event });
   });
   // Add to destroy(): unsubscribe();
   ```

4. **Suppress redundant polling Cmds** in TUI runtime's `interpretCmds()`:
   - Skip `Cmd.fetch` for URLs that are now event-driven:
     `/api/runs/active`, `/api/runs/:id/progress`, `/api/runs/:id/logs`
   - Keep polling for: `/api/network/health`, `/api/runs/recent`, `/api/runs/active/metrics`
     (these don't have event sources yet)
   - Web dashboard continues to use polling unchanged

5. **Remove the 50ms render timer** from `tui.ts`:
   - The `onChange` callback already fires after every `dispatch()`
   - Move render into `onChange` instead of polling `needsRender`
   - Key input loop still renders on keypress (unchanged)

## Files Changed

- `scripts/scenario-dashboard/dashboard_state.ts` — add `runs/event` Msg, add update case
- `scripts/scenario-dashboard/tui/runtime.ts` — subscribe to events, suppress polling Cmds
- `scripts/scenario-dashboard/tui.ts` — remove `setInterval(50ms)`, render in `onChange`

## Verification

- `deno test` — state machine tests pass
- Manual: start a run, verify progress updates appear instantly
- Verify no 50ms timer is running (check with `Deno.inspect` or logging)

## Risk

- Removing render timer might cause missed renders if `onChange` doesn't fire
  for all state changes — mitigated: `onChange` fires after every `dispatch()`,
  which is the same timing as the timer check
- Web dashboard must not break — polling Cmds are only suppressed in TUI runtime,
  web runtime still uses them

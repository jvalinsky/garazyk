# Phase 2: Event-Driven RunManager

## Problem

- `RunManagerImpl` mutates `this.activeRun` in place; TUI discovers changes via polling.
- Progress handler (`/api/runs/:id/progress`) scans `Deno.readDir(run.reportsDir)` on every
  2s poll, counting `.json` files and `stat`-ing each for mtime. Slow, stale, lossy.
- Log handler (`/api/runs/:id/logs`) reads the entire log file on every poll.
- No way to detect "scenario X just started" — only "scenario X's report file now exists".

## Approach

1. **Define `RunEvent` type** — discriminated union:
   ```
   run_started | run_status | scenario_started | scenario_finished |
   run_completed | run_failed | log_line
   ```

2. **Add `onEvent()` to `RunManager` interface** — returns unsubscribe function:
   ```typescript
   onEvent(listener: (event: RunEvent) => void): () => void;
   ```

3. **Emit events from existing mutation points**:
   - `startRun()` → `run_started`, `run_status("starting")`, `run_status("running")`
   - `spawnRunner()` completion → `run_completed` or `run_failed`
   - `stopRun()` → `run_status("stopping")`

4. **Add `Deno.watchFs` on reportsDir** — replaces directory-scanning poll:
   - Watch for `create`/`modify` events on `.json` files
   - Parse new report files and emit `scenario_finished` events
   - Fallback: if `watchFs` unavailable, keep polling as degraded mode

5. **Stream log lines** — pipe `stdout` through `TextLineStream`, emit `log_line` events:
   ```typescript
   const logStream = childProcess.stdout.pipeThrough(new TextLineStream());
   for await (const line of logStream) {
     this.emit({ type: "log_line", runId: run.id, line });
   }
   ```
   Keep file-based log as source of truth; stream is for real-time display only.

## Files Changed

- `scripts/scenario-dashboard/services/types.ts` — add `RunEvent` type
- `scripts/scenario-dashboard/services/run_manager.ts` — add `onEvent()`, emit events,
  add `watchReports()`, stream log lines

## Verification

- Unit tests: start a run, verify events arrive in correct order
- Integration: verify `scenario_finished` events fire when report files appear
- Test `watchFs` fallback on platforms without support

## Risk

- `Deno.watchFs` not available on all platforms — fallback to polling
- Log stream may lose lines if process exits before drain — file log is source of truth
- Event ordering: `scenario_finished` from watcher may arrive before `run_completed`
  from process exit — state machine must handle out-of-order events

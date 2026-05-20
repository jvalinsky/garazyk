# Garazyk Deno/TypeScript Review Fix Plan

**Date:** 2026-05-16
**Status:** Active
**Scope:** All HIGH and MEDIUM issues from the comprehensive Deno code review
**Parent Goal:** deciduous node TBD (to be created)

---

## Phase 1: Data-Loss & Silent-Corruption Bugs (P0)

These can cause tests to silently pass with broken behavior, or lose data at runtime.

### 1.1 Fix response body double-read bug (M6/M14)
**Files:** `skylab/services/proxy.ts`, `skylab/routes/api/execute.ts`
**Problem:** `resp.json()` consumes the body stream; if it throws, the catch block calls `resp.text()` on an empty stream, returning `{ raw: "" }` instead of the actual error body.
**Fix:**
```typescript
// Before (broken):
if (contentType.includes("application/json")) {
  try {
    payload = await resp.json();
  } catch {
    payload = { raw: await resp.text() }; // body already consumed!
  }
}

// After (correct):
const text = await resp.text();
if (contentType.includes("application/json")) {
  try {
    payload = JSON.parse(text);
  } catch {
    payload = { raw: text };
  }
} else {
  payload = { raw: text };
}
```
**Apply to both:** `proxyRequest()` in proxy.ts and the fallback proxy in execute.ts.
**Extraction:** Consider a shared `parseProxyResponse(resp: Response)` utility in `skylab/services/proxy.ts` to eliminate the duplication.

### 1.2 Fix firehose placeholder event emission (H2)
**File:** `scripts/lib/deno/firehose.ts`
**Problem:** CBOR header parse failure silently emits `FirehoseEvent(seq=0, type="unknown")`. Downstream assertions can't distinguish malformed events from legitimate ones.
**Fix:**
- Log the parse failure at `console.warn` level
- Skip the event (don't push to callback/events array) when header parsing fails
- Add a `malformed` boolean to `FirehoseEvent` for cases where we want to track but not assert
- Update `collect()` to filter out malformed events by default

### 1.3 Fix event log sequence numbers after shift (M2)
**File:** `skylab/services/control_bridge.ts`
**Problem:** `seq = eventLog.length + 1` is computed before push, but after `shift()` the length decreases, making `afterSeq` filters return wrong results.
**Fix:** Replace `eventLog.length + 1` with a monotonic counter:
```typescript
let _eventSeq = 0;
// In recordEvent:
const entry: EventLogEntry = {
  seq: ++_eventSeq,
  timestamp: Date.now() / 1000,
  ...event,
};
```

### 1.4 Fix fetchLatestResultPerScenario duplicate rows (M3)
**File:** `scripts/scenario-dashboard/db/queries.ts`
**Problem:** Correlated subquery returns all rows matching `MAX(started_at)`, which can be multiple if two results share the same timestamp.
**Fix:** Use a window function or add tiebreaker:
```sql
SELECT scenario_id, status, passed, failed, skipped
FROM (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY scenario_id ORDER BY started_at DESC, id DESC) AS rn
  FROM scenario_results
)
WHERE rn = 1
```

---

## Phase 2: Broken Test Assertions (P0)

These cause tests to assert the wrong thing, so they can pass when behavior is broken.

### 2.1 Fix inverted negative assertion in 53_phone_verification (H4)
**File:** `scripts/scenarios/scenarios/53_phone_verification.ts`
**Problem:** "Wrong code is rejected" step throws when status is *not* 200 — meaning a proper 400/403 rejection is treated as failure.
**Fix:** Invert the assertion: expect non-200 status for wrong code, throw on unexpected 200.

### 2.2 Fix websocket reconnection test (H5)
**File:** `scripts/scenarios/scenarios/48_websocket_reconnection.ts`
**Problem:** Resubscribes without cursor, doesn't assert event continuity. Only proves "can subscribe twice."
**Fix:**
- Collect events from first subscription, note the last `seq`
- Disconnect
- Resubscribe with `cursor = lastSeq`
- Assert that the second subscription starts from `seq > lastSeq` (no gaps, no duplicates)
- Add a step verifying the firehose client handles cursor-based resumption

### 2.3 Validate video jobId before polling (M7)
**File:** `scripts/scenarios/scenarios/36_video_processing.ts`
**Problem:** If upload response shape changes, `jobId` could be `undefined`, and the polling loop queries with an undefined path segment.
**Fix:** Add assertion after upload step:
```typescript
if (!jobId) throw new Error("Upload response missing jobId");
```

### 2.4 Tighten auth-negative assertions (M8)
**File:** `scripts/scenarios/scenarios/21_appview_lexicon_endpoints.ts`
**Problem:** Wrong-secret path doesn't clearly assert the expected failure mode (401/403).
**Fix:** Assert specific status codes for auth-negative steps. A 200 with empty body should fail the test.

---

## Phase 3: Type Safety & API Correctness (P1)

### 3.1 Replace `Record<string, any>` in RunConfig (H6)
**File:** `scripts/scenario-dashboard/services/types.ts`
**Problem:** `scenarioParams: Record<string, any>` bypasses all type safety.
**Fix:**
```typescript
export type ScenarioParamValue = string | number | boolean;
export interface RunConfig {
  // ...
  scenarioParams?: Record<string, ScenarioParamValue>;
}
```
Update all consumers (run_manager.ts, API routes) to match.

### 3.2 Fix `unregisterClient` cancelling all commands (M1)
**File:** `skylab/services/control_bridge.ts`
**Problem:** Loop rejects every pending command, not just the disconnecting client's.
**Fix:** Add `clientId` to `PendingCommand` interface, filter in `unregisterClient`:
```typescript
interface PendingCommand {
  clientId: string;
  resolve: (result: unknown) => void;
  reject: (error: Error) => void;
  timer: number;
}
// In dispatchCommand:
pendingCommands.set(cmdId, { clientId: client.id, resolve, reject, timer });
// In unregisterClient:
for (const [cmdId, pending] of pendingCommands.entries()) {
  if (pending.clientId === id) {
    clearTimeout(pending.timer);
    pending.reject(new Error("Browser client disconnected"));
    pendingCommands.delete(cmdId);
  }
}
```

### 3.3 Fix `as any` cast in restartRun (M10)
**File:** `scripts/scenario-dashboard/services/run_manager.ts`
**Problem:** `db.prepare("SELECT * FROM runs WHERE id = ?").get(runId) as any` — then accesses both snake_case and camelCase.
**Fix:** Add a `fetchRunFull()` query that returns all columns with aliases, or reuse `fetchRun` after fixing M11.

### 3.4 Fix fetchRun not returning new columns (M11)
**File:** `scripts/scenario-dashboard/db/queries.ts`
**Problem:** SELECT only includes original columns, not v1 migration additions.
**Fix:** Add all columns to the SELECT with camelCase aliases:
```sql
SELECT
  id, started_at as startedAt, finished_at as finishedAt,
  passed, failed, skipped, total_scenarios as totalScenarios,
  duration_s as durationS, status, pds2, binary_mode as binaryMode,
  topology, runner, web_client as webClient, client_flow as clientFlow,
  scenario_ids_json, run_dir as runDir, reports_dir as reportsDir,
  log_path as logPath, compose_project, manifest_path, child_pid as childPid,
  exit_code as exitCode, stopped_at as stoppedAt, stop_reason as stopReason,
  scenario_params_json as scenarioParamsJson
FROM runs WHERE id = ?
```

### 3.5 Fix shallow copy leaking internal state (M17)
**File:** `skylab/services/control_bridge.ts`
**Problem:** `getState()` returns `{ ...clientState }` — `timeline` and `chats` arrays are shared references.
**Fix:** Deep-clone arrays:
```typescript
export function getState(): ClientState {
  return {
    ...clientState,
    timeline: [...clientState.timeline],
    chats: [...clientState.chats],
    firehose: { ...clientState.firehose },
  };
}
```

---

## Phase 4: Character Registry Collision Fix (P1)

### 4.1 Replace collision-prone suffix strategy (H1)
**File:** `scripts/lib/deno/config.ts`
**Problem:** `Date.now() % 0xFFFF` — only 65536 values, concurrent runs collide.
**Fix:** Use `crypto.randomUUID()` or a monotonic counter with run-scoped prefix:
```typescript
let _suffixCounter = 0;
function generateSuffix(): string {
  return `${Deno.pid}-${++_suffixCounter}`;
}
```
Or simpler: `crypto.randomUUID().slice(0, 8)` for a short unique suffix.

---

## Phase 5: OTel & Diagnostics Correctness (P1)

### 5.1 Fix misleading `initTracing` auto-set (H3)
**File:** `scripts/lib/deno/otel.ts`
**Problem:** `Deno.env.set("OTEL_DENO", "true")` after startup has no effect on Deno's built-in OTel pipeline.
**Fix:**
- Remove the auto-set of `OTEL_DENO`
- Add a JSDoc note: "OTEL_DENO must be set before process start. This function only configures the OTLP endpoint and service name."
- Add a `console.warn` if `initTracing` is called without `OTEL_DENO` already set

### 5.2 Remove dead code in streamLogsViaAPI (M5)
**File:** `scripts/scenario-dashboard/services/network_manager.ts`
**Problem:** The `for await` loop over `streamEvents()` immediately breaks.
**Fix:** Remove the dead loop (lines 447-452). The `fetch()` call below is the actual implementation.

---

## Phase 6: Proxy & Routing Hardening (P2)

### 6.1 Remove dead browser clients on send failure (M16)
**File:** `skylab/services/control_bridge.ts`
**Problem:** `broadcastToBrowsers` catches send errors but leaves the dead client in the array.
**Fix:**
```typescript
export function broadcastToBrowsers(message: unknown): void {
  const data = JSON.stringify(message);
  const dead: string[] = [];
  for (const client of browserClients) {
    try {
      client.socket.send(data);
    } catch {
      dead.push(client.id);
    }
  }
  for (const id of dead) {
    unregisterClient(id);
  }
}
```

### 6.2 Consider lexicon-based routing for xrpcMethodUsesHttpGet (M15)
**File:** `skylab/services/routing.ts`
**Problem:** Heuristic based on NSID segment prefix can misroute custom methods.
**Fix (low priority):** Add a `KNOWN_QUERY_METHODS` set for standard ATProto methods, fall back to heuristic for unknowns. This is a correctness improvement, not a bug.

---

## Phase 7: Coverage Gaps (P2, Ongoing)

Track but don't block the fix phases above.

- Follow/follower/block read API scenarios
- Session refresh / token lifecycle
- Firehose cursor recovery / idle timeout
- OAuth PKCE / DPoP validation
- Multi-PDS / multi-account interaction

---

## Dependency Order

```
Phase 1 (Data-Loss Bugs)
  1.1 proxy body double-read ──► no deps
  1.2 firehose placeholder     ──► no deps
  1.3 event log seq numbers    ──► no deps
  1.4 duplicate query rows     ──► no deps

Phase 2 (Broken Assertions)
  2.1 phone verification       ──► no deps
  2.2 websocket reconnection    ──► 1.2 (firehose fix)
  2.3 video jobId validation    ──► no deps
  2.4 auth-negative tightening  ──► no deps

Phase 3 (Type Safety)
  3.1 Record<string,any>        ──► no deps
  3.2 unregisterClient filter   ──► no deps
  3.3 as any cast               ──► 3.4 (fetchRun fix)
  3.4 fetchRun columns          ──► no deps
  3.5 shallow copy              ──► no deps

Phase 4 (Registry Collision)
  4.1 suffix strategy           ──► no deps

Phase 5 (OTel/Diagnostics)
  5.1 initTracing misleading    ──► no deps
  5.2 dead code removal         ──► no deps

Phase 6 (Proxy Hardening)
  6.1 dead browser clients      ──► 3.2 (unregisterClient fix)
  6.2 lexicon routing           ──► no deps

Phase 7 (Coverage)              ──► 2.1-2.4 (assertions fixed first)
```

Most phases are independent and can be parallelized. Only dependencies:
- 2.2 depends on 1.2 (firehose must be fixed before reconnection test can use it)
- 3.3 depends on 3.4 (restartRun needs fetchRun to return full columns)
- 6.1 depends on 3.2 (dead client removal uses the fixed unregisterClient)

---

## Estimated Effort

| Phase | Items | Est. Time |
|-------|-------|-----------|
| Phase 1 | 4 | 1-2 hours |
| Phase 2 | 4 | 1-2 hours |
| Phase 3 | 5 | 2-3 hours |
| Phase 4 | 1 | 30 min |
| Phase 5 | 2 | 30 min |
| Phase 6 | 2 | 1 hour |
| Phase 7 | ongoing | — |
| **Total** | **18** | **~6-9 hours** |

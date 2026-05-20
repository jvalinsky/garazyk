# Garazyk Deno/TypeScript Code Review Findings

**Date:** 2026-05-16
**Scope:** Core library, scenarios, dashboard, skylab

---

## HIGH Priority

| ID | Issue | File | Description |
|---|---|---|---|
| H1 | Character suffix collision | config.ts | `Date.now() % 0xFFFF` only 65536 values, concurrent runs collide |
| H2 | Firehose placeholder events | firehose.ts | CBOR parse failure emits `FirehoseEvent(seq=0, type="unknown")` silently |
| H3 | Misleading initTracing auto-set | otel.ts | `Deno.env.set("OTEL_DENO")` after startup has no effect |
| H4 | Inverted negative assertion | 53_phone_verification.ts | Throws on non-200 (correct rejection) instead of on 200 (bad acceptance) |
| H5 | Reconnection test doesn't test reconnection | 48_websocket_reconnection.ts | No cursor, no continuity assertion |
| H6 | `Record<string, any>` in RunConfig | types.ts | Bypasses all type safety for scenario parameters |

## MEDIUM Priority

| ID | Issue | File | Description |
|---|---|---|---|
| M1 | unregisterClient cancels all commands | control_bridge.ts | Doesn't filter by clientId |
| M2 | Event log seq wrong after shift | control_bridge.ts | `eventLog.length + 1` breaks after circular buffer shift |
| M3 | Duplicate rows from latest-result query | queries.ts | Correlated subquery returns multiple rows on tied timestamps |
| M4 | SQL string interpolation | migrations.ts | `PRAGMA table_info(${table})` — safe today but bad pattern |
| M5 | Dead code in streamLogsViaAPI | network_manager.ts | Events loop immediately breaks |
| M6/M14 | Response body double-read | proxy.ts, execute.ts | `resp.json()` consumes body, catch `resp.text()` returns empty |
| M7 | Video jobId not validated | 36_video_processing.ts | Polling with undefined jobId |
| M8 | Auth-negative assertions too loose | 21_appview_lexicon_endpoints.ts | Doesn't assert specific failure status |
| M9 | Labeler subscription test weak | 45_labeler_subscription.ts | Doesn't validate subscription behavior end-to-end |
| M10 | `as any` cast in restartRun | run_manager.ts | Accesses both snake_case and camelCase from DB |
| M11 | fetchRun missing new columns | queries.ts | SELECT doesn't include v1 migration columns |
| M12 | AsyncMutex doesn't handle rejected promises | run_manager.ts | Queue callback errors leave mutex inconsistent |
| M13 | setInterval without unref | network_manager.ts | Prevents clean process exit |
| M15 | Heuristic HTTP method routing | routing.ts | NSID segment prefix can misroute custom methods |
| M16 | Dead browser clients left in array | control_bridge.ts | Send failure doesn't remove client |
| M17 | Shallow copy leaks internal state | control_bridge.ts | `getState()` shares array references |

## Coverage Gaps

- Follow/follower/block read APIs
- Session refresh / token lifecycle
- Firehose cursor recovery / idle timeout
- OAuth PKCE / DPoP validation
- Multi-PDS / multi-account interaction

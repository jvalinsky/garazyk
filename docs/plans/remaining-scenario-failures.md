# Remaining Scenario Failure Investigation Plan

**Context:** 41 failures remain across 27 scenarios (94% pass rate). These are
pre-existing issues, not caused by recent infrastructure fixes.

## Investigation Priority

### P0: Infrastructure gaps (easily fixable, unblocks other scenarios)

| #  | Scenario | Failure | Root Cause | Investigation |
|----|----------|---------|------------|---------------|
| 1  | 04, 55   | Admin login: `Invalid admin password` | Admin password config mismatch between services. 7 steps cascade from this single failure. | Check admin password in PDS config vs. what the scenario uses. Default is `admin` but may differ per deployment. |
| 2  | 11       | `UI Server health check`: Connection refused on `localhost:2590` | `garazyk-ui` not included in default topology or Docker Compose. | Verify UI service is part of the topology preset. Check `docker-compose.yml` and topology compiler for `ui` service inclusion. |
| 3  | 13       | `DID document inspection`: PDS serviceEndpoint not found | OAuth flow needs the PDS URL in the DID document. If using PLC, the DID document may not contain the PDS endpoint during local dev. | Trace the OAuth DID resolution path: PLC returns DID doc without endpoint → scenario looks for `http://127.0.0.1:2583` in `service` array. |
| 4  | 53       | `requestPhoneVerification`: `PhoneVerificationNotConfigured` | Twilio/SMS provider not wired in local dev. | Add mock/skip for phone verification in dev mode. `mock_twilio.ts` exists in hamownia. |
| 5  | 36, 46   | `Token verification failed` on video upload | Video service auth token not configured or mismatched. | Trace video upload token flow. Check if video service requires JWT that matches PDS issuer. |
| 6  | 59       | Playwright browser executable not found | Chromium not installed. | Fixed via flake dev env + `npx playwright install chromium`. Verify fix works. |
| 7  | 18       | `BackfillDisabled`: Backfill orchestrator not running | The backfill orchestrator process is not started in the local network. | Check if `campagnola` (backfill service) is included in default Docker Compose. Start it or add conditional skip. |

### P1: Service handler gaps (missing XRPC endpoints)

| #  | Scenario | Failure | Root Cause | Investigation |
|----|----------|---------|------------|---------------|
| 8  | 39       | `getLists` / `getList`: `No handler for GET /xrpc/app.bsky.graph.getLists` | AppView missing graph list endpoints. | The endpoint is defined in the lexicon but not registered in AppView. Check `appview route registration.` |
| 9  | 45       | `getServices`: `No handler for GET /xrpc/app.bsky.labeler.getServices` | AppView missing labeler service endpoint. | Check `app.bsky.labeler.getServices` registration in AppView routes. |
| 10 | 21       | `getRecent`: `No handler for GET /xrpc/com.shinolabs.pinksea.getRecent` | Dynamic lexicon endpoint not registered in AppView. | These are known community lexicons. Either register stubs or mark scenarios as known-skip. |
| 11 | 23       | `createRecord` on AppView: `Outbound request target failed SSRF validation` | AppView write proxy SSRF validation rejects the upstream PDS URL. | Check SSRF allowlist configuration. The proxy needs to allow PDS URLs. |

### P2: Application logic bugs (need code investigation)

| #  | Scenario | Failure | Root Cause | Investigation |
|----|----------|---------|------------|---------------|
| 12 | 06       | `getConvoForMembers` not rejected by allowIncoming=none | Chat service allows conversation creation despite `allowIncoming=none` setting. | Trace `allowIncoming` enforcement in chat service. The setting is stored but not checked on `getConvoForMembers`. |
| 13 | 09       | `AppView backfill status`: HTTP 401 | AppView backfill endpoint requires auth that PDS doesn't provide. | Check what auth credential the PDS backfill client sends to AppView. |
| 14 | 10       | `AppView consistency check`: HTTP 401 | Same root cause as #13. | Check AppView auth for consistency endpoints. |
| 15 | 15       | `Wait for starter pack in AppView`: Timeout | AppView not indexing starter packs created on PDS. | Check subscription/ingestion pipeline for `app.bsky.graph.starterpack` records. |
| 16 | 19       | `verifyPhone`: `Invalid or expired verification code` | Phone verification code mock may be broken or expired. | Check `mock_twilio.ts` implementation. The code generation and verification path. |
| 17 | 19       | `importContacts`: `Invalid token` | Contact import requires auth but token is invalid. | Trace auth token used for contact import. |
| 18 | 30       | `getHead`: Missing root | Temporal distortion scenario — repo head mismatch. | Root cause to be determined. Check scenario logic and PDS repo handling. |
| 19 | 31       | `Troll's 61st request`: Expected 429 but got 200 | Rate limiter not enforcing per-actor limits after 60 requests. | Check rate limiter configuration. Default limit may be higher than 60 or not per-actor. |
| 20 | 39       | `Get lists for Luna`: 404 | Lists endpoint not found on AppView. | Same as #8. AppView missing graph list handlers. |
| 21 | 43       | `Session revoked` for device 2 | Session may have been invalidated by another operation. | Trace session lifecycle. Check if `createSession` for second device is using wrong credentials. |
| 22 | 45       | `createRecord`: Missing required field `labelValues` | Labeler schema requires `labelValues` but scenario doesn't provide it. | Scenario may be out of sync with current labeler schema. Check both. |
| 23 | 51       | `Keep-alive blob missing`: Blob GC collected it | Blob garbage collection is too aggressive or keep-alive mechanism broken. | Trace blob keep-alive reference in GC logic. Blob may be collected despite being referenced. |
| 24 | 54       | `Suspended account write/read`: Expected failure but call succeeded | Suspension enforcement not working for writes or reads. | Trace account suspension check in PDS write and read paths. |
| 25 | 58       | `Records/CAR/Blob accessible after account delete` | Deletion cascade not fully implemented or not propagated to all services. | Trace `deleteAccount` flow: records, CAR, and blob cleanup. |

### P3: Performance / timeout issues

| #  | Scenario | Failure | Root Cause | Investigation |
|----|----------|---------|------------|---------------|
| 26 | 26       | Timeout after 120s | AppView ingest load test pushes too many records for local dev. | Check scenario load parameters. Reduce concurrency for local runs. |
| 27 | 33       | Timeout after 120s | Tortoise consumer test pushes too many records for local dev. | Check scenario parameters. May need timeout increase or load reduction. |
| 28 | 32       | Rate limit: Expected 400 got 200 | Hourly rate limit not hit within scenario window. | Check rate limit configuration: window size and threshold. Scenario may need more requests or shorter window. |

## Workflow

1. For each failure, read the scenario source and the relevant service code
2. Fix or document as known limitation
3. Re-run individual scenarios with `--setup --teardown` to verify fix
4. Update this plan with findings and `[fixed]` or `[wontfix]` annotations

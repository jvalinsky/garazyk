# Scratchpad: Fix Skipped Scenario Tests

## Context
Running the full scenario suite (`python3 scripts/scenarios/run_scenario.py`) initially yielded 134 passed / 0 failed / 19 skipped. Each "skip" hidden a real gap — a missing endpoint, a routing mismatch, an auth misconfiguration, or a missing client dependency.

## Investigation & Findings
The 19 skips fell into several buckets:
1. **Server-side bugs / missing implementations**: genuine code fixes needed.
2. **Routing/wiring gaps**: Handlers existed but were unreachable in the test topology.
3. **Test-side bugs**: incorrect method names, missing admin auth, or JSON-decoding binary responses.
4. **WebSocket/Handshake issues**: `Connection` header being overwritten by the server.

## Progress
### Phase 1: Test & Infra Fixes (Completed)
- **Bookmark NSID**: Fixed in `03_content_creation.py`.
- **Chat method name**: `getList` -> `listConvos` in `06_chat_dms.py`.
- **OAuth PAR flow**: Switched to spec-correct PAR push in `08_oauth_sessions.py`.
- **Sync binary handling**: Added `xrpc_get_binary` to `client.py` for CAR files.
- **Admin token bootstrap**: Added `/admin/login` support and wired it into `04_moderation_safety.py`.

### Phase 2: Server-side Proxy & Routing (Completed)
- **AppView Proxying**: Extended `XrpcAppBskyProxyMethodPack.m` to forward search and feed endpoints.
- **Handler Gating**: Corrected `XrpcAppBskyMethods.m` to only register AppView handlers locally when enabled, avoiding 404/500 conflicts.
- **Actor Service Splitting**: Separated PDS-side (preferences) from AppView-side (profiles) in `XrpcAppBskyActorPack`.

### Phase 3: Targeted Bug Fixes (Completed)
- **sync.getHead Public Access**: Removed auth requirement and switched to query param.
- **Takedown Enforcement**: Added 410 Gone checks in `getRecord` and `listRecords`.
- **Search Parameter Mismatch**: Fixed `q` vs `term` in Syrena.
- **WebSocket Upgrade Fix**: Fixed `HttpResponse.m` case-sensitive header bug and `HttpServer.m` dispatch fallthrough.

## Remaining Gaps
1. **Relay Stability (Scenario 09)**: `zuk` crashes during Firehose connection/replay.
2. **PDS Load Stability (Scenario 10)**: `kaszlak` crashes/refuses connections under burst post creation.

## Final Plan for 100% Pass
1. **Relay Replay Refactor**: Throttled, async repository replay in `SubscribeReposHandler.m`.
2. **PDS Listen Backlog**: Increase `SOMAXCONN` in `PDSNetworkListener.m`.
3. **Strict Test Assertions**: Remove skip-wrappers now that endpoints are implemented.
4. **Firehose Sequence Retry**: Implement event-count waiting in `09_firehose_streaming.py`.

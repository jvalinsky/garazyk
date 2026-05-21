# Sub-plan: 61 — Graph Read Verification (getFollows Returns 0)

## Problem
Scenario creates a follow (Luna→Marcus) then calls `getFollows` for Luna and gets 0 follows. Expected: Marcus in the follows list.

## Investigation

### Determine where getFollows is routed
1. Check which `PDS1` URL resolves to (PDS direct or AppView) in `scripts/scenarios/config/`
2. If PDS direct: PDS handles `app.bsky.graph.getFollows` via `XrpcAppBskyGraphPack.m`
3. If AppView: AppView handles via `AppViewXRpcRoutePack.m` → `GraphService.getFollowsForActor:`

### Check each case

**If routed to PDS directly:**
- PDS XRPC handler creates the follow record via `com.atproto.repo.createRecord`
- The record exists in the repo, so `getFollows` should find it
- Check if `getFollows` in `XrpcAppBskyGraphPack.m` has access to the same database

**If routed to AppView:**
- AppView's `getFollowsForActor:` queries `records` table for `app.bsky.graph.follow`
- Need to verify the AppView has indexed the follow record from the firehose
- Check if AppView subscription is processing follow records correctly

### Root Causes to Check
1. AppView not indexing follow records at all
2. AppView indexing lag (need wait/retry)
3. XRPC handler routing issue (wrong service)
4. Database permission/connection issue

## Files
- `Garazyk/Sources/Network/XrpcAppBskyGraphPack.m` (PDS handler)
- `Garazyk/Sources/Network/AppViewXRpcRoutePack.m` (AppView handler registration)
- `Garazyk/Sources/AppView/Services/GraphService.m` (AppView query logic)
- `scripts/scenarios/config/` (PDS1 URL config)
- `scripts/scenarios/scenarios/61_graph_read_verification.ts` (scenario)

## Verification
Add debug logging to determine which service handles the request. Then fix the indexing or routing gap. Re-run:
```bash
nix develop -c bash -c "cd scripts/scenarios && deno run -A e2e_runner.ts --scenario 61"
```

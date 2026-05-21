# Sub-plan: 54 — Suspension Enforcement (Negative Auth Paths)

## Problem
Suspended accounts can still write and read. Expected: HTTP 403 on both write and read operations.

## Failures
1. "Suspended account write denied" — write succeeds (expected failure)
2. "Suspended account read returns error" — read succeeds (expected failure)

## Work

### 1. Find suspension data model
- Search for how accounts are suspended (DB column, status field in accounts table)
- Search for existing suspension checks (if any partial implementation exists)

### 2. Add write-path suspension check
- In `com.atproto.repo.createRecord`, `com.atproto.repo.putRecord`, `com.atproto.repo.deleteRecord`
- Check if the requesting DID has a suspended status before allowing the operation
- Return `XRPCError` 403 with `AccountTakedown` or similar error

### 3. Add read-path suspension check
- In `com.atproto.repo.getRecord`, `com.atproto.sync.getRecord`, and feed/graph reads
- For reads: the question is whether to hide the suspended user's content (privacy) vs. block the suspended user from reading (enforcement)
- Check the scenario expectation: does it expect the suspended user gets 403, or that the suspended user's content is hidden from others?

### 4. Check middleware layer
- See if there's an auth middleware that can be extended with suspension checks
- Or add checks per handler in the XRPC route packs

## Files
- `scripts/scenarios/scenarios/54_negative_auth_paths.ts` (scenario)
- `Garazyk/Sources/Services/Auth/` (auth middleware)
- `Garazyk/Sources/Network/XrpcAppBskyGraphPack.m` (graph handlers)
- `Garazyk/Sources/Network/XrpcServerPack.m` (server handlers)
- Database schema for account status

## Verification
```bash
nix develop -c bash -c "cd scripts/scenarios && deno run -A e2e_runner.ts --scenario 54"
```

# Sub-plan: 55 — Takedown Read Enforcement

## Problems
Three distinct failures:

1. **updateSubjectStatus (400)**: "Missing subject DID" — Admin API payload format mismatch
2. **admin.getRecord (404)**: "MethodNotFound" — Handler not registered
3. **Takedown not enforced on read**: Public reads return taken-down records

## Work

### 1. Fix updateSubjectStatus payload
- Check the scenario's payload for `com.atproto.admin.updateSubjectStatus`
- Ensure it includes `subject.did` in the correct format
- Compare against the lexicon in `lexicons/com/atproto/admin/updateSubjectStatus.json`

### 2. Register admin.getRecord handler
- Add handler for `com.atproto.admin.getRecord` in the AppView or PDS
- Check if this should be on the PDS (admin namespace) or AppView
- Follow existing admin handler patterns

### 3. Implement takedown read enforcement
- Add a takedown filter to record read paths:
  - `com.atproto.repo.getRecord`
  - `com.atproto.sync.getRecord`
  - Feed/Graph reads that expose record content
- Query a `takedowns` table or similar to check if a record/DID is taken down
- Return a 404 or empty result for taken-down content

## Files
- `scripts/scenarios/scenarios/55_takedown_read_enforcement.ts` (scenario)
- `lexicons/com/atproto/admin/updateSubjectStatus.json`
- `lexicons/com/atproto/admin/getRecord.json`
- `Garazyk/Sources/Network/XrpcAdminPack.m` or similar (admin handlers)
- `Garazyk/Sources/Network/AppViewXRpcRoutePack.m` (AppView handlers)
- `Garazyk/Sources/AppView/Services/` (read path services)

## Verification
```bash
nix develop -c bash -c "cd scripts/scenarios && deno run -A e2e_runner.ts --scenario 55"
```

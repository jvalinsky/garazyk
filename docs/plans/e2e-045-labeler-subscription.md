# Sub-plan: 45 — Labeler Subscription

## Problems
1. `com.atproto.repo.createRecord` for labeler service fails (400): "Missing required field 'labelValues' (at record.policies)"
2. `app.bsky.labeler.getServices` returns 404 — no handler registered

## Work

### Issue A: Missing labelValues in scenario payload
- **Root cause**: The scenario creates a labeler service record without the required `policies.labelValues` field
- **Fix**: Update the scenario to include `policies: { labelValues: [...] }` in the `createRecord` body
- **Lexicon reference**: Check `lexicons/app/bsky/labeler/service.json` for required fields

### Issue B: getServices handler not registered
- Add `getServices` query method to appropriate service (check AppView or GraphService)
- Register handler in `AppViewXRpcRoutePack.m` for `app.bsky.labeler.getServices`

## Files
- `scripts/scenarios/scenarios/45_labeler_subscription.ts` (scenario)
- `lexicons/app/bsky/labeler/service.json` (labeler service lexicon)
- `Garazyk/Sources/Network/AppViewXRpcRoutePack.m` (handler registration)
- `Garazyk/Sources/AppView/Services/GraphService.m` or relevant service

## Verification
```bash
nix develop -c bash -c "cd scripts/scenarios && deno run -A e2e_runner.ts --scenario 45"
```

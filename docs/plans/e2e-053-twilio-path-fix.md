# Sub-plan: 53 — Phone Verification Twilio Path Fix

## Problem
PDS returns HTTP 500 "Not Found" on `requestPhoneVerification`. Mock Twilio returns 404 because URL paths don't match.

## Root Cause Analysis

**PDS URL construction** (`PDSTwilioPhoneVerificationProvider.m:120-134`):
- Reads `TWILIO_API_BASE_URL` (Docker: `http://local-mock-twilio:8081`) or defaults to `https://verify.twilio.com/v2/Service`
- Constructs: `{baseURL}/{serviceSID}/Verifications`
- Result: `http://local-mock-twilio:8081/VA.../Verifications`

**Mock Twilio route matching** (`mock_twilio.ts:197-199`):
- Expects: `/v2/Service/{serviceSID}/Verifications`
- Path mismatch: missing `/v2/Service/` prefix

Two possible fixes:

### Option A: Fix the PDS (add /v2/Service prefix)
- Change `PDSTwilioPhoneVerificationProvider.m` to always append `/v2/Service` between baseURL and serviceSID
- Or set the env var to `http://local-mock-twilio:8081/v2/Service`
- Pros: mock matches real Twilio API path structure
- Cons: changes PDS code

### Option B: Fix the mock (relax path matching)
- Change mock to match `/{serviceSID}/Verifications` as well as `/v2/Service/{serviceSID}/Verifications`
- Or change prefix to just `/v2/Service` and append it in the matching
- Pros: no change to PDS binary, just test infrastructure
- Cons: diverges from real Twilio path structure

## Files
- `Garazyk/Sources/PhoneVerification/PDSTwilioPhoneVerificationProvider.m` (PDS client)
- `packages/hamownia/mock_twilio.ts` (mock server routes)
- `docker/local-network/docker-compose.yml` (env var config)
- `scripts/scenarios/config/pds-config.json` (local config)
- `docker/local-network/Dockerfile.mock-twilio` (mock Twilio container)

## Verification
```bash
nix develop -c bash -c "cd scripts/scenarios && deno run -A e2e_runner.ts --scenario 53"
```

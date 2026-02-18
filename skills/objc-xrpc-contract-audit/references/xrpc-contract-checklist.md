# XRPC Contract Checklist

Use this checklist while validating candidates from `scan_xrpc_contracts.sh`.

## Endpoint registration and dispatch
- Verify each NSID registration resolves to intended handler.
- Verify endpoint sensitivity matches auth/scope requirement.
- Verify deprecated or alias methods preserve expected behavior.

## Input contract
- Verify required fields are checked before side effects.
- Verify type validation and normalization are deterministic.
- Verify unknown fields are handled according to schema policy.

## Output and errors
- Verify success payload shape is stable and documented.
- Verify error payload includes consistent code/message shape.
- Verify status code mapping is explicit and tested.

## Regression guardrails
- Add endpoint tests for auth boundary cases.
- Add validation tests for malformed body/query input.
- Add snapshot or schema tests for response/error payloads.

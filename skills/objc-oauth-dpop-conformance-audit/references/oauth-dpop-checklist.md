# OAuth DPoP Checklist

Use this checklist while validating candidates from `scan_oauth_dpop_conformance.sh`.

## Proof validation
- Verify `htm`, `htu`, `iat`, and `jti` are required and checked.
- Verify proof expiry and skew window are explicit.
- Verify replay protection is enforced for `jti` and nonce policy.

## Token lifecycle
- Verify refresh rotates credentials and invalidates old artifacts.
- Verify revoked/expired token paths fail closed.
- Verify scope or audience narrowing is preserved across refresh.

## Key and trust model
- Verify signing and verification keys map correctly by `kid`.
- Verify rotation does not create acceptance windows for stale keys.
- Verify key source and trust anchors are explicit and test-covered.

## Operational resilience
- Verify clock skew handling is consistent across mint and verify.
- Verify audit logs avoid leaking token/proof secrets.
- Verify conformance tests include malformed proof and replay cases.

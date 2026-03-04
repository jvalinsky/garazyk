---
title: PLC Signature Encoding Notes
---

# PLC Signature Encoding Notes

This project follows the official did:plc reference implementation for signature encoding.

## Summary

- PLC operations are DAG-CBOR encoded before signing.
- The `sig` field is **base64url without padding** (no `=` characters).
- Padded base64url signatures are rejected by the reference implementation.

## Reference Implementation Pointers

- Signing behavior (CBOR encode + base64url signature):
  - `reference/did-method-plc/packages/lib/src/operations.ts`
- Rejection of padded signatures:
  - `reference/did-method-plc/packages/lib/tests/data.test.ts`

## Implementation Guidance

- When serializing the signature, ensure base64url **no padding**.
- When validating signatures, reject any `sig` that ends with `=`.
- The bytes signed are the DAG-CBOR encoding of the unsigned operation.

---

## Related Documentation

- [Archive Index](README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [Architecture Docs](../../architecture/README) - System architecture documentation

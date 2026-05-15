---
title: PLC Server Operations
---

# PLC Server Operations

Garazyk includes a standalone PLC server that validates identity operations, stores history, and serves DID documents and audit logs. This server manages identity history independently of account or repository state.

## Runtime Model

The PLC server entry point supports two primary configuration flags:

- `--port <number>`: Sets the listen port (defaults to `2582`).
- `--database <path>`: Specifies a persistent SQLite store.

Omitting `--database` causes the server to use `PLCMockStore`. This in-memory mode is suitable for local development but does not persist identity history across restarts. Use `--database` for production.

## HTTP Interface

- `GET /:did`: Resolves the current DID document.
- `GET /:did/log`: Returns the PLC operation history.
- `POST /:did`: Submits a new operation.
- `GET /_health`: Health status.
- `GET /_metrics`: Operational metrics.

## Persistence Strategy

Choose the persistence mode based on the environment:

- **In-memory (`PLCMockStore`)**: Fast startup for local development and testing.
- **SQLite (`PLCPersistentStore`)**: Durable identity history and replay capability for production.

## Validation and Auditing

`PLCAuditor` processes all submitted operations to verify integrity:

- DID format and operation structure.
- `prev` history hash links and signature validity.
- Rotation key authority and tombstone rules.
- Field normalization for `alsoKnownAs` and service endpoints.
- Rate limits for operation frequency.

## DID State Mechanics

A PLC DID reflects the replayed result of its operation history. The current state includes rotation keys, verification methods, `alsoKnownAs`, services, and tombstone status. DID mismatches usually indicate history or normalization errors rather than lookup failures.

## Operational Guidelines

- Enable persistent storage for any non-ephemeral environment.
- Monitor health and metrics separately from the main PDS metrics.
- Treat the operation log as the source of truth for resolving document discrepancies.
- Analyze auditor rules to diagnose validation failures.

The PLC server does not handle PDS account state, repository ownership, or application handles.

## Related Resources

- [PLC Directory](../02-core-concepts/plc-directory)
- [DID Document Updates](../02-core-concepts/did-document-updates)
- [ATProto Basics](../02-core-concepts/atproto-basics)
- [Documentation Map](documentation-map.md)

## Appendix: Operational Checks

```bash
# Health check
curl -sS http://127.0.0.1:2582/_health | jq .

# Metrics
curl -sS http://127.0.0.1:2582/_metrics | head
```

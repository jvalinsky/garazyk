---
title: PLC Server Operations
---

# PLC Server Operations

## Overview

September ships a standalone PLC server alongside the PDS. Its job is narrower
than the PDS job: accept PLC operations, validate them, store history, and
serve current DID documents plus audit logs.

That boundary matters because PLC operational guidance should be about identity
history, not about account or repository state.

## The Runtime Model

The PLC server entry point accepts two operational flags:

- `--port <number>` to choose the listen port, default `2582`
- `--database <path>` to use a persistent SQLite store

If you omit `--database`, the server uses `PLCMockStore` and runs entirely in
memory. That is appropriate for tests and short-lived local development. It is
not appropriate for any environment where identity history must survive a
restart.

## Public HTTP Surface

The standalone PLC server exposes a small surface:

- `GET /:did` resolves the current DID document
- `GET /:did/log` returns the PLC operation history
- `POST /:did` submits an operation
- `GET /_health` exposes a health check
- `GET /_metrics` exposes PLC metrics

That small API is a feature. PLC becomes much easier to reason about when the
server only exposes the operations that define identity state.

## Why Persistence Is Optional In Dev And Mandatory In Real Ops

`PLCPersistentStore` uses SQLite for durable history. `PLCMockStore` keeps the
same API shape but discards everything on restart.

The reason to keep both is simple:

- local development needs low-friction startup
- operational identity infrastructure needs durable history and replay

The mistake is assuming those two modes are interchangeable. They are not.

## Validation And Audit Rules

PLC state is not just "last write wins". The server runs submitted operations
through `PLCAuditor`, which verifies:

- DID format and operation shape
- hash-linked `prev` history
- rotation-key authority
- signature validity
- tombstone and recovery rules
- normalization of fields such as `alsoKnownAs` and service endpoints
- rate limits for operation frequency

This is the most important operational fact about the PLC server. The durable
store is only as useful as the replay and validation rules protecting it.

## Understanding DID State

A PLC DID is the replayed result of an operation history. The current state
contains the fields contributors care about most:

- rotation keys
- verification methods
- `alsoKnownAs`
- services
- tombstone status

That means a DID mismatch is usually a history or normalization problem, not a
simple key-value lookup failure.

## Operational Habits That Matter

If you are operating the standalone PLC server:

- use persistent storage anywhere restarts matter
- keep health and metrics checks separate from the PDS metrics surface
- treat the operation log as the source of truth when a DID document looks wrong
- debug validation failures through auditor rules before changing storage

Those habits keep identity debugging grounded in the actual data model.

## What This Server Does Not Replace

The PLC server does not replace:

- PDS account state
- repository ownership checks inside the PDS
- application-layer handle or session logic

It only owns DID document history and validation.

## Related Reading

- [PLC Directory](../02-core-concepts/plc-directory)
- [DID Document Updates](../02-core-concepts/did-document-updates)
- [ATProto Basics](../02-core-concepts/atproto-basics)

## Appendix

### Minimal PLC checks

```bash
curl -sS http://127.0.0.1:2582/_health | jq .
```

```bash
curl -sS http://127.0.0.1:2582/_metrics | head
```

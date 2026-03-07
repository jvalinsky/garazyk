---
title: PLC Directory
---

# PLC Directory

## Overview

The PLC directory is ATProto's append-only identity history system for
`did:plc`. It exists so that a DID can remain stable while the server
association, handle, or authorized keys evolve over time.

That is the "why" that matters. PLC is not just another metadata service. It is
the durable history behind `did:plc` identity.

## What September Supports

September supports two DID methods in its validator and resolver story:

- `did:plc`
- `did:web`

The PLC directory only applies to the first one. `did:web` resolution is a
different identity path.

## PLC State Is Replayed History

The current DID document for a PLC DID is derived by replaying an operation
history. Each operation is signed and linked to the previous one, and the
replayed state contains the fields the rest of the protocol cares about:

- rotation keys
- verification methods
- `alsoKnownAs`
- services
- tombstone state

This history-based model is why PLC debugging should start with the audit log,
not just with the final resolved document.

## Validation Matters More Than Storage

September's PLC stack is built around the idea that stored history without
strong validation is not useful identity infrastructure.

`PLCAuditor` verifies operation shape, signature authority, recovery and
tombstone rules, and normalization of fields such as handles and service
endpoints. `PLCStateReplayer` then turns that validated history into current
state.

That is the core architectural idea of the PLC directory in this repository.

## Local Versus External PLC

The PDS can resolve against a configured PLC URL, and the repository also ships
a standalone PLC server implementation. That gives contributors two useful
modes:

- talk to the public `plc.directory`
- run a local PLC server for development and testing

The important distinction is that both modes still speak the same identity
model. Only the operator boundary changes.

## Why Contributors Should Care

If you work on handle changes, DID resolution, account bootstrap, or identity
verification, PLC is not optional background knowledge. It explains:

- why handle changes may require PLC writes
- why DID resolution is method-aware
- why local account state has to stay aligned with resolved identity
- why some identity bugs only show up after replaying history

## Related Reading

- [DID Document Updates](./did-document-updates)
- [PLC Operation Walkthrough](./plc-operation-walkthrough)
- [ATProto Basics](./atproto-basics)
- [PLC Server Operations](../11-reference/plc-server-operations)

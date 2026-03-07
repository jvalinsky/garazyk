---
title: DID Document Updates
---

# DID Document Updates

## Overview

In ATProto, a DID document update is an identity update, not a profile edit.
Changing it can alter which server is authoritative, which keys can sign future
operations, and which handle is associated with the DID.

That is why September handles DID updates cautiously and why the docs need to
describe the actual update path rather than a generic "PATCH the DID document"
story.

## `did:plc` Updates Are Operation-Based

For `did:plc`, the current DID document is the replayed result of PLC
operations. September therefore updates DID state by constructing and submitting
new PLC operations, not by editing one stored JSON document in place.

Those operations carry the fields that define identity state:

- rotation keys
- verification methods
- `alsoKnownAs`
- services
- the previous operation link
- the operation signature

That structure is why PLC updates feel more like append-only history than CRUD.

## What September Preserves During Updates

When the server updates DID state, it tries to preserve the identity fields that
should remain stable unless the caller is intentionally changing them.

In particular, the identity update path keeps or validates:

- existing rotation keys
- the expected `atproto_pds` service endpoint
- `alsoKnownAs` entries that should survive a handle change
- the operation history needed to compute the correct `prev` link

This is the right design pressure. Identity updates should be conservative by
default because losing the wrong field can sever future control of the DID.

## Handle Updates Are DID Updates

One place contributors often underestimate this is `com.atproto.identity.updateHandle`.
For `did:plc`, a handle update is not just a database edit. The server replays
PLC history, confirms the desired handle state, constructs a new operation when
needed, submits it to the PLC directory, then updates local account state.

That sequence explains why handle changes touch identity code, PLC code, and
application state together.

## `did:web` Is Different

September also supports `did:web`, but the update model is different. `did:web`
state is resolved from the web-hosted DID document rather than from PLC
operations.

The useful contributor lesson is simple:

- `did:plc` updates are operation history work
- `did:web` updates are external document publication work

Do not assume one update path can stand in for the other.

## What To Verify During An Update

When identity updates behave unexpectedly, verify these in order:

1. the DID method being updated
2. the current PLC audit log or resolved DID document
3. the intended `alsoKnownAs` and service endpoint values
4. the local account state that should match the resolved identity

This ordering keeps you from treating an identity history problem as a simple
database bug.

## Related Reading

- [PLC Directory](./plc-directory)
- [DID Update Walkthrough](./did-update-walkthrough)
- [ATProto Basics](./atproto-basics)
- [PLC Server Operations](../11-reference/plc-server-operations)

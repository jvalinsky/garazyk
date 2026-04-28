---
title: ATProto Basics
---

# ATProto Basics

## Overview

To understand Garazyk's AT Protocol implementation, remember:

- identity is DID-first
- handles are aliases, not primary keys
- records live in per-user repositories
- blobs are separate from records and referenced by CID
- XRPC surfaces are the protocol boundary

This page focuses on the parts of ATProto that show up directly in this
repository.

## Identity: DID First, Handle Second

Accounts are anchored by DIDs. Handles are human-friendly names that resolve to
or are associated with those DIDs.

In Garazyk today, the supported DID methods are:

- `did:plc`
- `did:web`

Higher-level behavior depends on the DID method.

## Repositories And Records

Each account has a repository. Records are namespaced entries inside that
repository, typically grouped by collection NSIDs such as
`app.bsky.feed.post`.

Repository work in this tree includes:

- create, update, and delete records
- materialize repository state through MST and CAR machinery
- expose sync and firehose views of that state

Record code, repository service code, and sync code sit together in the architecture.

## Blobs Are Adjacent, Not Embedded

Large binary objects are stored separately from records and are referenced by
blob objects containing CID links. That keeps repositories from turning into
opaque binary stores and lets the server manage blob storage with a separate
lifecycle.

Separating blobs from records simplifies repository and storage code.

## XRPC Is The Protocol Surface

ATProto methods are exposed through XRPC namespaces such as:

- `com.atproto.server.*`
- `com.atproto.repo.*`
- `com.atproto.sync.*`
- `com.atproto.identity.*`

To trace behavior:

1. find the XRPC method
2. read its auth and validation path
3. follow the owning service
4. inspect repository, database, blob, or identity code underneath

## Sync And Relay Concepts

ATProto also includes sync and relay behavior. In this repository, that shows up
primarily as:

- repository export and block retrieval
- `subscribeRepos` delivery
- crawl notifications to configured relays

A relay crawl hint differs from a firehose stream.

## How Garazyk Maps The Model

The current codebase is structured so the protocol model maps cleanly to
implementation seams:

- auth helpers own token and DPoP verification
- services own application behavior
- repository and blob layers own persistence and content addressing
- identity and PLC code own DID resolution and updates

This mapping lets the docs emphasize architecture and request flow over payload dumps.

## Related Reading

- [Codebase Map](../01-getting-started/codebase-map)
- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [IPLD and Multiformats Series](./ipld-foundations/)
- [Protocol Flow Walkthrough](./protocol-flow-walkthrough)
- [PLC Directory](./plc-directory)
- [Cryptography](./cryptography)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)


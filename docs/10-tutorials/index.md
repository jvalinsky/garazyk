---
title: Tutorials Overview
---

# Tutorials Overview

The Garazyk tutorials are designed for contributors who want to understand the system's architecture and internals. Rather than providing standalone "toy" projects, these guides focus on how the repository is structured, why specific subsystems exist, and how to verify changes.

Each tutorial explores:
- The purpose and invariants of a subsystem.
- File locations and ownership in the repository.
- Verification strategies and common failure modes.

Longer code samples and shell commands are moved to appendices to keep the main narrative focused on technical concepts.

## Core Track

Follow these tutorials to understand the production server from the inside out.

1. [Tutorial 1: Hello PDS](./tutorial-1-hello-pds) — Boot sequence and discovery.
2. [Tutorial 2: Accounts](./tutorial-2-accounts) — Identity and session management.
3. [Tutorial 3: Records](./tutorial-3-records) — Repository writes and data invariants.
4. [Tutorial 4: Authentication](./tutorial-4-auth) — JWT, DPoP, and OAuth2.
5. [Tutorial 5: Firehose](./tutorial-5-firehose) — Real-time event streaming.
6. [Subguide: Network from Scratch](./network-from-scratch/) — Sockets, HTTP, and WebSockets.
7. [Tutorial 6: Deployment](./tutorial-6-deployment) — Production operations and Docker.

## Feature Deep Dives

Once you understand the core runtime, explore these specialized topics.

- [Tutorial 8: Endpoint Workflow](./tutorial-8-endpoint-workflow) — Adding new XRPC methods.
- [Tutorial 9: Blobs and Migrations](./tutorial-9-blobs-and-migrations) — Managing binary data and repo portability.
- [Tutorial 10: OAuth2 & DPoP](./tutorial-10-oauth-dpop) — High-security authentication handshakes.
- [Tutorial 11: PLC Failover and Resolution](./tutorial-11-plc-resolution) — Identity resilience.
- [Tutorial 12: Federation & Sync](./tutorial-12-federation-sync) — Network-wide data replication.
- [Tutorial 13: Admin Internals](./tutorial-13-admin-internals) — Monitoring and management.
- [Tutorial 14: Advanced Firehose](./tutorial-14-advanced-firehose) — Filtering and backfills.
- [Tutorial 15: AppView Operation](./tutorial-15-appview-operation) — Data ingestion and indexing.

## Example Levels

We use three levels of examples to guide development:

- **Main Prose**: Architectural explanations and repository walkthroughs.
- **Inline Snippets**: Small, illustrative examples of a single idea.
- **Appendices**: Command sequences and code blocks for manual verification.

Always refer to the source files in `Garazyk/Sources/` for the absolute implementation truth.

## Supporting Reference

- [Codebase Map](../01-getting-started/codebase-map)
- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [Testing Map](../11-reference/testing-map)
- [API Reference](../11-reference/api-reference)
- [Config Reference](../11-reference/config-reference)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)


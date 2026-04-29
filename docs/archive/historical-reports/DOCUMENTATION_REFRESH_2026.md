---
title: April 2026 Documentation Refresh
---

# April 2026 Documentation Refresh

This document summarizes the comprehensive documentation update performed in April 2026 to align the technical guides with the major architectural and feature advancements in the Garazyk codebase.

## Major Advancements Covered

### 1. Sans-I/O Architecture
The network layer has been completely refactored to use a **Sans-I/O** design pattern. Protocol logic is now handled by pure state machines, ensuring high portability and deterministic testing across macOS and Linux/GNUstep environments.
*   **New Doc**: `docs/04-network-layer/sans-io.md`
*   **Updated**: `docs/01-getting-started/architecture-overview.md`, `docs/04-network-layer/http-server.md`

### 2. Standalone Server Components
Documentation now reflects the transition from a monolithic PDS to a suite of specialized, standalone servers that fulfill global AT Protocol roles.
*   **Syrena (AppView)**: High-performance indexing and read-model service.
*   **Zuk (Relay)**: Aggregation and firehose broadcasting service.
*   **Campagnola (PLC)**: Standalone `did:plc` directory server.
*   **New Docs**: `docs/03-application-layer/appview-server.md`, `docs/03-application-layer/relay-server.md`

### 3. Trust, Safety, and Compliance
The repository now includes first-class implementations for regulatory and user safety features, including regional Age Assurance flows and chat moderation.
*   **New Docs**: `docs/03-application-layer/safety-and-compliance.md`, `docs/03-application-layer/chat-service.md`, `docs/03-application-layer/video-processing.md`

### 4. Interoperability & Validation
Full syntax validation for DIDs, NSIDs, and CIDs has been implemented and verified against the official AT Protocol test suite.
*   **New Doc**: `docs/07-repository-protocol/lexicon-validation.md`
*   **Updated**: `docs/01-getting-started/codebase-map.md`

### 5. Security Hardening
A consolidated guide on security measures, including low-S signature enforcement, DPoP binding, and SSRF protection.
*   **New Doc**: `docs/security/hardening-measures.md`
*   **Updated**: `docs/06-authentication/oauth2-dpop.md`

## Summary of Changes

| Type | Count | Key Files |
| --- | --- | --- |
| **New Files** | 9 | `sans-io.md`, `appview-server.md`, `safety-and-compliance.md`, `cli-usage.md`, etc. |
| **Updated Files** | 10 | `architecture-overview.md`, `codebase-map.md`, `SUMMARY.md`, `tutorial-1-hello-pds.md`, etc. |
| **Verified Links** | 100+ | All new cross-references validated for VitePress compatibility. |

## Next Steps for Contributors

1.  Review the **[Sans-I/O Architecture](../04-network-layer/sans-io)** guide before modifying any network or protocol code.
2.  Follow the **[Kaszlak CLI Usage](../01-getting-started/cli-usage)** guide for updated operator workflows.
3.  Consult the **[Trust, Safety, and Compliance](../03-application-layer/safety-and-compliance)** guide when implementing new safety features.

---

**Refresh Date**: April 21, 2026  
**Status**: ✅ Complete  
**Goal**: 100% Documentation Accuracy vs. Code Truth.

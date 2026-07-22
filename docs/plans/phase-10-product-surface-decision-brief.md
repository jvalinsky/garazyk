---
title: Phase 10 Product Surface Decision Brief
status: awaiting-operator-decision
last_verified: 2026-07-22
---

# Phase 10 Product Surface Decision Brief

This brief resolves the six product contracts called out by workstream 05 E3.
Each needs one operator disposition: **support**, **experimental**, or **remove**. A supported
surface needs a user-visible contract, named owner, configuration that is truthful, and an
integration test. Experimental surfaces must be opt-in and clearly labelled. Removed surfaces must
be rejected at configuration or hidden from public UI/negotiation.

## Evidence and recommendation

| Surface | Current evidence | Production risk | Recommended disposition | Work required if supported |
| --- | --- | --- | --- | --- |
| SMTP email | `PDSEmailProviderFactory` accepts `smtp`, constructs `PDSSMTPEmailProvider`, and application startup registers it. Both send methods always return `PDSSMTPEmailProviderErrorNotImplemented`; their warning logs also include the recipient address. | A deployed configuration can appear valid while every verification or notification email fails. | **Remove.** Reject `smtp` during configuration/factory construction; retain `resend` for delivery and `mock` for tests. | TLS mode policy, authentication, certificate validation, timeouts, redacted logs, mock SMTP integration tests, bounded retry semantics, and scenario coverage for a user-visible email flow. |
| S3-compatible blob storage | `PDSCloudStorageBlobProvider` implements signed PUT, GET, HEAD, and idempotent DELETE; `listAllCIDs` and streaming retrieval return 501. More importantly, `PDSApplication` unconditionally instantiates `PDSDiskBlobProvider`, so configured `blob_storage.type: s3` never owns the PDS data path. There is no cloud copy operation. | The plan's former "copy/delete returns 501" statement is inaccurate, but the advertised S3 configuration is still non-operational and its readiness check is only a warning. | **Remove** until it is wired end-to-end, or choose **experimental** only behind an explicit opt-in that says it is not production storage. | Wire the factory into PDS startup; validate config and readiness against a real S3-compatible service; test put/get/head/delete, paginated listing, streaming, cancellation/timeouts, auth/signing failures, restart persistence, and audit/reconciliation behavior. |
| CAR → STAR reconstruction | `STARConverter` parses the CAR commit but explicitly does not deserialize and walk MST blocks; it emits a degenerate STAR-L0 archive. Yet STAR is negotiated for public sync export and parsed on import paths. | A public format claim can produce data without record-proof/tree fidelity. | **Remove** CAR-to-STAR conversion and public STAR negotiation until lossless MST reconstruction is implemented. Keep STAR-to-CAR parsing only where its existing tests prove it. | DAG-CBOR MST deserialization; CID/data validation; deterministic preorder traversal; full and sliced CAR round trips; malformed/missing-block tests; sync export/import interoperability and size/resource limits. |
| Skylab repost | The timeline renders a Repost button labelled "coming soon" whose click handler only logs that it is unimplemented. | Operator UI exposes a non-action as an action. | **Remove** the control until support is implemented. | Record creation/deletion flow, optimistic state rollback, auth/error display, tests with an XRPC mock, and browser smoke coverage. |
| Skylab Germ E2EE | Selecting E2EE announces client-side encryption but the send path says SDK integration is a placeholder and falls back to plaintext. | This is a privacy and consent failure: the UI can imply E2EE while transmitting plaintext. | **Remove** the E2EE selector and claims immediately; do not use an experimental fallback-to-plaintext mode. | Germ SDK/key-package lifecycle, encryption-before-network invariant, declaration lookup, authenticated mailbox delivery/poll, key rotation and recovery, test vectors, no-plaintext regression tests, and a user-visible trust/error model. |
| Scenario dashboard manifest metadata | `Run` persists `manifestPath`, and URL resolution already reads it, but `NetworkManager.healthCheck` still contains a TODO and falls back to role heuristics rather than per-run manifest health probes. | Dashboard health can describe the wrong topology or probe the wrong endpoint. | **Support.** This is bounded dashboard correctness work, not a new product promise. | Add typed health-probe metadata to the resource manifest, use it for active-run checks, retain a documented fallback, and add unit tests for valid, missing, and malformed manifests. |

## Plan correction

The Phase 10 prompt and mega plan previously described cloud "copy/delete" paths returning 501.
The current source has no cloud copy path, implements DELETE, and returns 501 only for listing and
stream retrieval. The plan wording has been corrected to match the source; it does not change the
decision that the configured S3 path is not production-ready.

## Required operator decision

Approve the six recommended dispositions above, or supply a replacement disposition for each row.
For a different choice, specify the intended user-visible contract and owner. No implementation
will begin until this decision is recorded, because it determines whether configuration/UI surfaces
are removed, held behind an experimental contract, or completed as supported products.

## Evidence locations

- SMTP: `Garazyk/Sources/Email/PDSEmailProviderFactory.m`,
  `Garazyk/Sources/Email/PDSSMTPEmailProvider.m`, and
  `Garazyk/Tests/Email/PDSSMTPEmailProviderTests.m`.
- Cloud blobs: `Garazyk/Sources/Blob/PDSCloudStorageBlobProvider.m`,
  `Garazyk/Sources/Blob/PDSBlobProviderFactory.m`, and `Garazyk/Sources/App/PDSApplication.m`.
- STAR: `Garazyk/Sources/Repository/STAR.m`, `Garazyk/Sources/Network/XrpcSyncPack.m`, and
  `Garazyk/Sources/Services/PDS/PDSRepositoryService.m`.
- Skylab: `skylab/static/js/skylab-timeline.js` and `skylab/static/js/skylab-chat.js`.
- Dashboard: `scripts/scenario-dashboard/services/network_manager.ts` and
  `scripts/scenario-dashboard/services/run_manager.ts`.

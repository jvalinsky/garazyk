---
title: Completed Phase Execution Prompts (Archive)
status: archived
last_verified: 2026-08-05
---

# Completed Phase Execution Prompts (Archive)

The 23 phase prompts whose `status:` reached `complete`, moved here from
`docs/plans/prompts/` on 2026-08-05 so the active directory carries only work
that can still be picked up.

**This directory is history, not backlog.** Prompts were always derived
execution text, never a backlog of their own — the mega plan and workstreams are
authoritative, and every phase archived here was verified to have its outcome
recorded in one of them before it was moved. They are kept rather than deleted
because several carry `## Progress` sections that other documents cite by name,
most notably phase-29's, referenced from
[the 2026-07-28 security review](../../../plans/security-review-2026-07-28.md).

| Phase | Focus | Outcome recorded in |
| --- | --- | --- |
| 1 | Browser smoke baseline | Mega plan Phase 0 item 1; workstream 00 B0.2 |
| 2 | Permissioned spaces multi-PDS acceptance | Workstream 06 P6.1 |
| 3 | Truthful XRPC metrics + spec conformance matrix | Mega plan Phase 2 item 3; workstream 01 S3/S6 |
| 4 | Backpressure, adversarial ingress, account lifecycle | Mega plan Phase 2 items 4–5; workstream 01 S5 |
| 6 | Generated NSID constants + CLI/lifecycle adoption | Mega plan Phase 3 items 3–4; workstream 02 A4 |
| 7 | Relay product decision + incremental public sync | Mega plan Phase 4 items 2/7; workstream 02 A5/A6; ADR 0006 |
| 8 | Admin UI accessibility and structural cleanup | Workstream 04 (closed) |
| 9 | Space key rotation, ops readiness, attestation | Workstream 06 P6.2/P6.3/P6.5 |
| 10 | WASM baseline + product-surface dispositions | Mega plan Phase 5 items 1–2; workstream 05 E1/E3; ADR 0010 |
| 11 | Storage and MST optimization remainder | Workstream 07 (closed) |
| 12 | Objective-C god-file decomposition | Workstream 02 A3; mega plan Phase 4 item 3 |
| 13 | Untyped JSON at auth trust boundaries | Workstream 01 S8 |
| 14 | Wire the auth verification cluster | Workstream 01 S8 |
| 15 | Blob lifecycle conformance | Workstream 01 S9; ADR 0013 |
| 16 | Storage pool and MST decoder correctness | Workstream 01 S9 |
| 17 | WebSocket RFC conformance and HTTP framing | Workstream 01 S10 |
| 18 | Outbound egress pinning and SSRF gaps | Workstream 01 S10 |
| 19 | Core decoder bounds and encoder cost | Workstream 01 S11 |
| 20 | Linux secret store encryption and destructive CLI | Workstream 01 S11 |
| 21 | AppView hydration batching and ingest checkpoint | Workstream 07 O7 |
| 22 | MST viewer gating and dead admin cookie removal | Workstream 01 S12 |
| 25 | Registration gate composition and CAPTCHA follow-ups | Workstream 01 S13; ADR 0030 |
| 29 | Refresh-flow regression and parser test debt | Security review 2026-07-28 §P0; workstream 01 S17–S19 |

Workstream 01's own closed detail is archived alongside this directory in
[workstream-01-completed-items.md](../workstream-01-completed-items.md).

Phases 23, 24, and 26–28 are absent because they were deleted outright when
their items closed, before this archive existed; Git history retains them.

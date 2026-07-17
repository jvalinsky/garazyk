---
phase: 3
title: Truthful XRPC metrics and spec conformance matrix
status: complete
agent: claude
depends_on: []
---

# Phase 3: Truthful XRPC metrics and spec conformance matrix

## Mission

Make coverage claims honest at two altitudes: per-endpoint (S3's split
metrics and semantic fixes) and per-spec (S6's conformance matrix), and
produce the assessment that sizes the OAuth Permissions-spec gap.

## Read first

- `docs/plans/workstreams/01-security-and-protocol-correctness.md`
  (S3 and S6 — the authoritative task lists)
- Current coverage tooling:
  `scripts/docs/generate_xrpc_coverage_report.cjs` and the strict CI check
- `Garazyk/Resources/lexicons` (canonical root; 519 lexicons, 392 endpoints)

Use an Explore fan-out first to inventory registration sites, dynamic
AppView routes, and existing scope handling before changing anything.

## Scope

1. **S3 metrics split** (report-only first): registered vs schema-covered
   vs behavior-verified endpoints; static dispatcher vs dynamic AppView
   routes; explicit Garazyk extensions.
2. **S3 semantic fixes**, each an isolated commit:
   `chat.bsky.actor.declaration` phantom query removed or re-namespaced;
   `app.bsky.labeler.getServices` validates `dids` and returns indexed
   services; `com.atproto.admin.getRecord` gets an explicit compatibility
   policy or removal.
3. **S6 matrix**: one row per published spec page (data model, lexicon,
   cryptography, accounts, repository, blobs, labels, XRPC, OAuth,
   permissions, event stream, sync, DID, handle, NSID, TID, record key,
   AT URI) plus did:plc and Proposal 0016 — status, executable proof,
   owning workstream for gaps. Report-only; a red row is a lead, not a
   blocker.
4. **Permissions-spec assessment**: verify the suspected gap (only
   transitional + `space:` scopes found on 2026-07-16), read
   https://atproto.com/specs/permissions, and write a sized implementation
   proposal into workstream 01 as a new lane. Do not implement it in this
   phase.

Out of scope: NSID constant generation (phase 6), implementing granular
scopes.

## Acceptance gate

- Metrics report regenerates deterministically with commit + date; strict
  check still green.
- Semantic fixes have route-level characterization tests.
- Matrix document exists with every "supported" row naming a proof.
- Global gates pass, including AllTests.

## On completion

Update workstream 01 S3/S6 status, mega-plan Phase 2 items 3 and 7; set
`status: complete` here. Phase 6 unblocks.

---
phase: 2
title: Permissioned spaces multi-PDS acceptance
status: in-progress
agent: claude
depends_on: []
---

# Phase 2: Permissioned spaces multi-PDS acceptance

## Mission

Turn the fully implemented Proposal 0016 stack from "type-checked" to
"proven": recorded runtime passes of scenarios 93 and 94 against a real
three-PDS topology, plus the private-blob and pruned-oplog acceptance cases.
This is the top-of-P1 mega-plan item and the gate for every pending
compatibility row.

## Read first

- `docs/plans/workstreams/06-permissioned-spaces.md` (P6.1 — the
  authoritative task list)
- `docs/permissioned-spaces-compatibility.md` (the gate being closed)
- `docs/adr/0004-experimental-permissioned-spaces.md`,
  `docs/adr/0005-space-reconciliation-after-oplog-pruning.md`
- `scripts/scenarios/scenarios/93_permissioned_spaces.ts`,
  `94_space_reconciliation.ts` — note the PDS1 authority / PDS2 writer /
  PDS3 reader layout and that `PDS3_URL` must name an independently
  operated, permissioned-spaces-enabled PDS.

## Scope

1. Stand up the three-PDS topology (PDS3 config and manifest landed in
   `cc063779a`; prefer the `docker/` tooling). Enable
   `permissionedSpacesEnabled` on all three; set
   `permissionedSpacesHostEndpoint` if Docker aliases differ from issuers.
2. Run scenarios 93 and 94 via structured `hamownia agent` output; iterate
   until green. A product-code fix required by a failure is its own
   reviewed, characterization-guarded slice — never a scenario hack.
3. Prove all three recovery paths fire at least once (incremental ops,
   lightweight diff, full CAR import) — extend scenario 94 assertions or a
   test helper around `pruneOplogForSpace:author:keepingRevisions:`.
4. Private blob acceptance: upload via `com.atproto.repo.uploadBlob` with
   the three `X-Atproto-Space*` binding headers, read via
   `com.atproto.space.getBlob` from the remote reader, assert rejection
   through every public repo/sync/blob endpoint.
5. Move the pending compatibility rows to Implemented only with a dated
   structured-run reference.

Out of scope: key rotation, attestation, ops drills (phase 9).

## Blocked on

Three-PDS Docker topology must be running before any scenario work begins.
The scenarios hard-exit if `PDS3_URL` is not set. Specific items needed:

1. **Build the PDS Docker image** from the current source tree. The
   Objective-C PDS binary must compile and run inside a container.
2. **Stand up PDS1, PDS2, and PDS3** using the Docker compose / schemat
   topology config landed in `cc063779a`. All three must have
   `permissionedSpacesEnabled=true`; PDS3 must use an independent issuer
   and signing key (it represents a separately operated PDS).
3. **Set `permissionedSpacesHostEndpoint`** on each PDS if Docker network
   aliases differ from the issuer URLs the scenarios use.
4. **Confirm health** by hitting `/xrpc/_health` on all three before
   running the scenarios.
5. **Provide `PDS3_URL`** as an environment variable when invoking
   `hamownia agent` or the Deno scenario runner.

Once the topology is healthy, unblock this phase and resume the loop.
The first code slice will be: run scenario 93, iterate on any failures.

## Acceptance gate

- Dated structured runs of 93 and 94, green, checked-in summary only.
- Space test suites and AllTests green; `deno task check/lint/test` pass.
- Compatibility doc rows updated with evidence.

## On completion

Update workstream 06 P6.1, mega-plan Phase 2 item 6 and current state; set
`status: complete` here. Phase 9 unblocks.

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

## Next steps (unblocked 2026-07-17)

This phase was briefly held for a Docker topology; **Docker is confirmed
available on this machine** (`docker info` succeeds, version 29.4.0 — see
phase 4's status note), so the topology work below is executable agent
work, not a human checkpoint. Note that phase 4's research confirmed
`--binary` mode has no `"pds3"` case — the three-PDS layout genuinely
needs the Docker path (or a `"pds3"` case added to
`packages/hamownia/binary_services.ts`, which may be the cheaper route;
assess both before building images). The scenarios hard-exit if
`PDS3_URL` is not set. In order:

1. Either add a `"pds3"` case to `binary_services.ts` (independent issuer,
   signing key, and data dir) **or** build the PDS Docker image from the
   current source tree and use the compose/schemat topology from
   `cc063779a`.
2. Stand up PDS1, PDS2, and PDS3 with `permissionedSpacesEnabled=true` on
   all three; PDS3 must use an independent issuer and signing key.
3. Set `permissionedSpacesHostEndpoint` on each PDS if network aliases
   differ from the issuer URLs the scenarios use.
4. Confirm `/xrpc/_health` on all three; provide `PDS3_URL` to the runner.
5. Run scenario 93, iterate on failures; then 94; then the private-blob
   and pruned-oplog cases.

Coordinate with the shared worktree: phases 6 and 7 have uncommitted
changes in the main checkout (including `XrpcSpacePack.m` in the NSID
sweep). Run this phase from a clean worktree or after those commit.

## Acceptance gate

- Dated structured runs of 93 and 94, green, checked-in summary only.
- Space test suites and AllTests green; `deno task check/lint/test` pass.
- Compatibility doc rows updated with evidence.

## On completion

Update workstream 06 P6.1, mega-plan Phase 2 item 6 and current state; set
`status: complete` here. Phase 9 unblocks.

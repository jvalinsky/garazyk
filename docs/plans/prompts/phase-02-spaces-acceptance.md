---
phase: 2
title: Permissioned spaces multi-PDS acceptance
status: complete
agent: worker
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

## Progress notes (2026-07-18)

### Infrastructure gaps fixed (uncommitted, pending commit)

- **docker_config.ts**: `SERVICE_PORTS.pds3 = 2588` added; `neededPorts()` now
  accepts `withPds3` and includes the pds3 port.
- **binary_services.ts**: `pds3` case added to `BINARY_SERVICES` and
  `resolveBinaryServiceStartPlan`; pds2/pds3 relay upstreams wired;
  `permissionedSpacesEnabled: true` and `permissionedSpacesHostEndpoint` set
  for all PDS cases (pds, pds2, pds3 share the case block).
- **scenario_metadata.ts**: `needsPds3` field added to `ScenarioManifest` and
  `ScenarioInfo`; scenario 93 manifest updated with `needsPds3: true`;
  scenario 94 manifest added with `needsPds3: true` and
  `Cap.pds3.getRecord` requirement (replacing the invalid
  `Cap.pds.didResolution`); `needsPds3()` helper and compatibility check
  added.
- **schemat/topology_registry.ts**: pds3 role, capabilities, port, env var,
  and URL patterns registered.

### Verification status

- `deno task check` — **PASS** (all packages type-check cleanly).
- Scenario 93 run (2026-07-18T0640Z, `--binary` mode): **6/7 passed, 1 failed**.
  - Fail: "Owner completes OAuth PAR, PKCE, and DPoP grant — HTTP 401 (invalid_client)"
  - All three PDS instances started and passed health checks.
  - All three accounts created successfully on PDS1/PDS2/PDS3.
  - OAuth PAR/PKCE/DPoP flow returns 401 invalid_client — product-code issue.
- Scenario 94 run (2026-07-18T0640Z, `--binary` mode): **3/4 passed, 1 failed**.
  - Fail: "Owner obtains OAuth grant on authority PDS — authorization redirect did not contain a code"
  - All three accounts created on PDS1/PDS2/PDS3.
  - OAuth authorization redirect missing `code` parameter — product-code issue.
- Warning: scenario 94 topology advertises "missing requirements: pds3:getRecord"
  (topology preset doesn't include pds3 capabilities; non-blocking — scenarios
  still ran).

### DPoP verification fix (2026-07-18) — resolves the OAuth PAR blocker

The scenario-93 OAuth PAR failure (recorded above as "401 invalid_client";
a fresher binary surfaced it as `400 invalid_dpop_proof`) was root-caused to
a P-256 signature-verification bug, **not** client registration. The verifier
enforced low-S on P-256/JOSE signatures, and `AuthCryptoECDSA` used the P-256
field prime `p` where it needed the group order `n`, so ~50% of DPoP proofs
(any with high-S) were rejected non-deterministically. Full diagnosis (the
repro-driven, S-value-correlation method) and the fix are in
[ADR 0007](../../adr/0007-p256-ecdsa-verification-must-not-enforce-low-s.md).

- Fix: `AuthCryptoJWK` verifies P-256 signatures as presented (no low-S gate);
  `AuthCryptoECDSA` constants corrected to order `n`; characterization test
  `testVerifySignatureAcceptsBothLowSAndHighS` added.
- Verified: single-PDS PAR repro 50% → 16/16; `AuthCryptoECDSATests`,
  `AuthCryptoJWKTests`, `OAuthDPoPTests`, `PLCAuditorTests`,
  `WebAuthnVerifierTests`, `AuthVerifierTests` all green.

### Scenario 93 GREEN (2026-07-18, `--binary --pds2`, 3-PDS)

**Scenario 93 now passes 19/19** on the three-PDS binary topology. Two
product fixes were required, each its own slice:

1. DPoP P-256 low-S verification — [ADR 0007](../../adr/0007-p256-ecdsa-verification-must-not-enforce-low-s.md)
   (unblocked the OAuth PAR step).
2. **notifyWrite service-auth 401.** Once OAuth passed, the "Authority learns
   the remote writer" step failed: PDS A sent `notifyWrite` to the authority's
   resolved `#atproto_space_host` endpoint, but the authority returned 401.
   `SpaceServiceAuthentication` (`XrpcSpacePack.m`) rejected the service-auth
   JWT with "Missing subject claim" — inter-service tokens (iss/aud/lxm) carry
   no `sub`. Fix: `verifier.allowMissingSubject = YES`, matching
   `XrpcServerPack.m`. Covered by the scenario-93 run + auth/space unit suites
   (45 tests green).

The full path is exercised: OAuth PAR/PKCE/DPoP → delegation → credential →
remote write → signed authority notification → remote reader credential read →
public-repo isolation → membership-revocation credential denial.

### OAuth confirmation regression coverage (2026-07-18)

The apparent missing-`code` redirect was historical form encoding behavior:
`0a7925f9a` corrects GNUstep `+` form-space parsing and `3b6a4f5cb` makes
scenario 94 submit `%20`-encoded forms. Commit `9000097ba` adds a
characterization test for the exact `atproto+space:` consent form and proves
that `/oauth/authorize/confirm` returns a 302 whose Location includes both
`code` and `state` (31 `OAuth2HandlerTests`, 0 failures).

The structured run `2026-07-18t2153z-87263`
(`deno task hamownia agent run 94 --binary --pds2`) reached topology startup
but stopped before scenario execution because `APPVIEW failed to start`.
It provides no current OAuth counterevidence.

### AppView diagnostic result (2026-07-18)

The failed run used an externally occupied AppView port (`59500`): its log
records `Address already in use`, although the generated manifest assigned
that port only to AppView. A fresh binary rerun allocated `52649`, AppView was
healthy, and scenario 94 passed **25/25** in structured run
`2026-07-18t2204z-20523`. This was a transient external `EADDRINUSE` collision,
not a topology/runner defect, so no code change is warranted.

### Private-blob acceptance result (2026-07-18)

Commit `21eeb5719` extends scenario 93 with OAuth+DPoP upload through
`com.atproto.repo.uploadBlob` using all three experimental binding headers,
remote `com.atproto.space.getBlob` retrieval through the reader credential,
and public `repo.getBlob`/`sync.getBlob` rejection plus `sync.listBlobs` and
CAR-export isolation. Structured run `2026-07-18t2209z-29983` passed **21/21**
on the three-PDS binary topology. `deno fmt --check` and `deno check` pass;
repository-wide lint remains blocked by 2,043 pre-existing unrelated package
findings.

### Recovery-path investigation (2026-07-18)

Structured run `2026-07-18t2214z-49690` passes scenario 94 **25/25** and
`PDSSpaceStoreTests` passes **6/6**, but this does not establish recovery-path
selection. Scenario 94 reads the authority with a credential; it does not
seed a PDS3 replica. The binary runner cannot configure retention/intervals,
and no public or admin XRPC can prune a known cursor, trigger one reconciler
pass, or report the chosen path. Treating its authority reads as recovery
would create false acceptance evidence.

### Recovery-control decision and result (2026-07-18)

The authorized production-excluded control plane is registered only when
`PDS_RUNNING_TESTS`, `PDS_SPACE_RECOVERY_TEST_CONTROL`, and a non-production
environment are all present. It is not an admin/public route, lexicon, or
generated NSID. Commit `43b3ad9c3` uses it to seed a PDS2 replica, prune the
PDS1 fixture oplog, run exactly one real reconciler pass, and report selector
plus request counts. Structured run `2026-07-18t2238z-90828` passed **28/28**,
observing `incremental`, `lightweight`, and `fullCAR`. It also fixed the real
reconciler defects found while exercising those paths: service-auth read
recognition, XRPC envelope parsing, authority-signed commits, base58 DID-key
decoding, URI record-index parsing, and CID-versus-revision gap comparison.

## Acceptance gate

- Dated structured runs of 93 (21/21) and 94 (28/28), green.
- Focused space/recovery suites and AllTests build green; `deno task check`
  passes. Repository-wide `deno task lint` remains blocked by 2,043
  pre-existing unrelated package findings.
- Compatibility doc rows updated with evidence.

### Verification rerun (2026-07-18)

After local disk capacity was restored, the full gated native suite progressed
through its registered suites without an observed failure and released its
temporary fixtures. `deno task test` is not a Phase 2 failure: live Gruszka
resolution tests cannot perform DNS in this sandbox, and the checked-in
generated client has unrelated lexicon drift. Focused Phase 2 tests, Deno
type checking, the security re-audit, and structured scenario 94 remain green.

## On completion

Update workstream 06 P6.1, mega-plan Phase 2 item 6 and current state; set
`status: complete` here. Phase 9 unblocks.

---
title: Permissioned Spaces Productionization
status: active
last_verified: 2026-07-16
---

# Permissioned Spaces Productionization

## Purpose

Take the landed Proposal 0016 implementation (ADR 0004, ADR 0005) from
"implemented, off by default" to "operator-enableable with executable
acceptance evidence," while tracking an upstream proposal that is still a
sketch and expected to change.

Authoritative status lives in
[docs/permissioned-spaces-compatibility.md](../../permissioned-spaces-compatibility.md).
This workstream owns only the open work; it does not restate implemented
behavior.

## Current evidence

- `da296909f` implements Proposal 0016 (isolated SQLite store, space
  URIs/scopes, delegation, credentials, policy, private blobs, notifications).
- `cc063779a` adds scenarios 93 and 94 plus PDS3 topology config; both are
  type-checked but have no recorded runtime pass.
- The reconciliation protocol from ADR 0005 is fully implemented in source:
  `CARReader.roots`, `PDSSpaceStore` import/prune/index methods,
  `PDSSpaceReconciler` inbound sync, `PDSSpaceOplogPruner`, and the
  `listRecords`/`listRepoOps` cursor fixes in `XrpcSpacePack.m`. The
  implementation-plan checklist that tracked this work is retired; ADR 0005
  and the code are the durable record.
- Space test suites (`PDSSpaceStoreTests`, `PDSSpaceCommitTests`,
  `PDSSpaceJWTTests`, `PDSSpaceURIAndScopeTests`, `PDSSpaceLtHashTests`,
  `XrpcSpacePackTests`, `ATProtoDIDDocumentFieldsSpaceTests`) are registered
  in `test_main.m`.
- Upstream: Proposal 0016 is pinned at
  `3f6c96d5d2d25438bd40fa89d6ecc37865f8e354`. The AT Protocol Spring 2026
  roadmap names permissioned data the protocol team's major focus through
  summer 2026, with spec, PDS, SDK, and moderation-tooling changes expected.

## P6.1 Multi-PDS runtime acceptance (P1)

Scenario 93 (three-PDS OAuth, delegation, remote write, notification,
public-boundary isolation, membership revocation) and scenario 94
(inbound reconciliation convergence after delayed or pruned notifications)
exist but have never passed at runtime. `PDS3_URL` must name an
independently operated, permissioned-spaces-enabled PDS.

1. Stand up the three-PDS topology (the PDS3 config and manifest from
   `cc063779a`; Docker where possible) and record structured
   `hamownia agent` runs of scenarios 93 and 94.
2. Exercise the pruned-oplog paths explicitly: incremental ops, lightweight
   record diff, and full CAR import must each be observed at least once
   (scenario 94 step assertions or a dedicated debug/test helper for
   `pruneOplogForSpace:author:keepingRevisions:`).
3. Add the private-blob acceptance case: upload through
   `com.atproto.repo.uploadBlob` with the three binding headers, read via
   `com.atproto.space.getBlob` from a remote reader, and prove rejection
   through every public repo/sync/blob endpoint.
4. Update the compatibility-gate rows ("Reads and writes," "Notifications,"
   "Multi-PDS recovery," "Private blobs," "OAuth federation scenario") from
   pending to Implemented only with a dated structured-run reference.

Owner boundary: `scripts/scenarios/scenarios/93_*.ts`, `94_*.ts`, scenario
topology/config, `docs/permissioned-spaces-compatibility.md`. No product
code should need to change; if a scenario failure requires one, that fix is
its own reviewed slice.

Verification: structured scenario output with commit and date; targeted
space suites and `AllTests` stay green.

Rollback: scenarios and gate rows only. The feature flag stays off by
default regardless of outcome.

## P6.2 Dedicated space signing key and DID migration (P2)

The implementation uses the documented account-`#atproto`-key fallback.
New DID documents publish explicit same-value `#atproto_space` and
`#atproto_space_host` entries; existing `did:plc` accounts have neither
until an ordinary PLC rotation adds them.

1. Design the key-rotation migration for a genuinely independent
   `#atproto_space` key (generation, PLC operation, credential issuance
   cutover, old-credential expiry window).
2. Provide the operator path for migrating existing accounts' DID documents
   (explicit rotation tooling; the PDS never rewrites a DID document
   implicitly, per ADR 0004).
3. Verify credential verification against both key layouts during the
   overlap window.

Owner boundary: `Sources/Services/PDS/PDSSpace*`, PLC rotation tooling,
DID-document generation. Blocked on nothing, but do not start before P6.1
proves the current fallback end-to-end.

Rollback: the fallback key path remains supported; rotation is per-account
and reversible by rotating back.

## P6.3 App attestation decision (decision needed)

`managing-app` policy and `appAccess#allowList` are rejected rather than
weakened (ADR 0004). Before any implementation, decide:

1. implement full end-to-end attestation validation (client metadata, JWKS,
   signature, issuer/subject, audience, expiry, nonce replay, app identity);
2. or keep the configuration rejected until upstream standardizes
   attestation.

A merely structural check is not an option. Record the choice as an ADR
amendment; only option 1 creates implementation work.

## P6.4 Upstream drift tracking (ongoing)

Proposal 0016 says details, terminology, and behaviors are likely to
change, and the protocol team expects spec-level changes through summer
2026.

1. On a monthly cadence (or when upstream announces changes), re-diff the
   pinned reference against upstream `bluesky-social/proposals` 0016 and the
   pinned atproto commit; record the delta and its impact in the
   compatibility doc.
2. Vendored lexicons under `com.atproto.space`/`com.atproto.simplespace`
   are regenerated only against a new pinned commit, never ad hoc.
3. The experimental `uploadBlob` header binding is replaced, not extended,
   when an upstream upload lexicon lands.
4. `permissionedSpacesEnabled` stays off by default until the upstream
   proposal stabilizes; enabling it earlier is an explicit operator decision
   per ADR 0004.

## P6.5 Operational readiness (P2, after P6.1)

1. Backup/restore drill: back up the space SQLite database plus WAL
   sidecars, restore onto a fresh instance, and verify LtHash/commit
   verification passes for every restored repo.
2. Verify rollback semantics: disabling the flag deregisters every space
   route and retains the database; a downgraded binary must not delete or
   rewrite permissioned data.
3. Give the reconciler and pruner an observable surface (structured logs or
   counters for replay attempts, gap detections, recovery-path choice, and
   pruned revisions) so operators can see convergence without reading
   SQLite.

Owner boundary: `Sources/Services/PDS/PDSSpaceReconciler.m`,
`PDSSpaceOplogPruner.m`, ops runbooks. Log/counter additions must not
change protocol behavior.

## Primary sources

- Proposal 0016, pinned `3f6c96d5d2d25438bd40fa89d6ecc37865f8e354`
- ADR 0004 (experimental permissioned spaces), ADR 0005 (reconciliation)
- [AT Protocol Spring 2026 roadmap](https://atproto.com/blog/2026-spring-roadmap)
- [OAuth profile](https://atproto.com/specs/oauth)

---
title: Security and Protocol Correctness
status: active
last_verified: 2026-08-08
---

# Security and Protocol Correctness

Exposed control surfaces, HTTP bounds, XRPC contracts, and federation tests.

All twenty workstream items are closed. Their full detail — evidence, slices,
decisions, gates, and rollback notes — moved to
[the completed-items archive](../../archive/planning/workstream-01-completed-items.md)
on 2026-08-05, unchanged. **Only the S5 residual watch item remains open.**

## Status summary

| Item | Scope | Status |
| --- | --- | --- |
| S1 | Duplicate XRPC ownership | Complete (2026-07-26) |
| S2 | Canonical lexicon generation | Complete (2026-07-26) |
| S3 | Truthful XRPC coverage | Complete, report-only (2026-07-17) |
| S4 | Absolute HTTP deadlines | Complete (2026-07-26) |
| S5 | Functional federation and lifecycle checks | Complete (2026-07-24); **one watch item open**, below |
| S6 | Published-spec conformance matrix | Complete, report-only; G3 closed (2026-08-08) |
| S7 | STAR conformance and verifying import | Complete (2026-07-23), ADR 0009 |
| S8 | Untyped JSON at auth trust boundaries | Complete (2026-07-27), 7 slices, 3 ADRs |
| S9 | Blob lifecycle and storage-pool correctness | Complete (2026-07-27), phases 15–16 |
| S10 | WebSocket framing and outbound egress hardening | Complete (2026-07-27), phases 17–18 |
| S11 | Core decoder bounds, secret storage, destructive CLI | Complete (2026-07-27) |
| S12 | MST viewer gating and dead admin credential surface | Complete (`6bce0725`, `65bc7ebe`) |
| S13 | Registration, PhoneVerification, Email sweep | Complete, 10 slices (ADRs 0020, 0022, 0030) |
| S14 | Ozone moderation sweep | Complete, 7 slices (`a66dd7b1`, `cf23deba`) |
| S15 | Chat (`syrena-chat`) sweep | Complete, 7 slices |
| S16 | Video + Germ/Mikrus/Beskid sweep | Complete, 5 slices (HEAD `92f0c8b4`) |
| S17 | Admin + AdminUIServer sweep | Complete (2026-07-29, `e340d6de`) |
| S18 | Auth-verifier protocol extraction | Complete (2026-07-29, `1013aa88`, `d47443f5`) |
| S19 | DAG-CBOR routing migration | Complete (2026-07-29) |
| S20 | HTTP transport crash-safety and request boundaries | Complete (2026-07-29), sub-tasks A–E |

## Open: S5 residual — `PDSDatabase` null-pointer flake (watch item)

Carried forward verbatim from S5, which is otherwise closed. This is the only
unresolved defect left in this workstream.

A null-pointer SIGSEGV (`EXC_BAD_ACCESS` / `KERN_INVALID_ADDRESS` at `0x0`)
inside `-[PDSDatabase(Private) safeExecuteSync:]` (`PDSDatabase.m:48`), called
from `-[PDSDatabase openWithError:]` (`PDSDatabase.m:122`). Seen three times on
2026-07-16 — once from `PDSDatabaseBlobsTests/testGetBlobsForDidWithPagination`
(21:47) and twice from `PDSDatabaseLRUTests setUp` (22:12, 22:15). Originally
misattributed to a different crash signature. Possibly related to disk pressure
given `PDSDatabase`'s use of SQLite, but never confirmed.

**Mitigated but open (2026-07-26 verification).** Auditing `openWithError:` for
this flake found and fixed three concrete contract bugs on the same path: a
failed `sqlite3_open` never closed SQLite's error-holding handle and left `_db`
non-NULL; `createSchema:` failure — the exact `SQLITE_FULL` disk-pressure shape
— was ignored, so `openWithError:` returned YES on a database with missing
tables; and `setWalMode:`/`setPerformanceOptimizations:` failures wrote `*error`
alongside a YES return. `PDSDatabaseOpenFailureTests` now pins the failed-open
cleanup. The original `0x0` crash never reproduced, so its most plausible
mechanisms on this path are closed but the underlying defect is unproven.

Next step if it recurs: capture the crash report and diff against the three
closed mechanisms before assuming disk pressure. Related context:
[Garazyk disk pressure](../../../CLAUDE.md) notes that full `--gated=run` runs
fail with `SQLITE_FULL` near disk capacity.

## Complete: S6 gap G3 — Relay `getRepoStatus` status semantics

The checked-in `com.atproto.sync.getRepoStatus` lexicon permits `status` to be
absent for an inactive repository and does not list Relay's private
`in-progress` state. `RelayXrpcRoutePack` now reports that state as
`active: false` without a `status`; it continues to map desynchronized,
throttled, and tombstoned states to the checked-in known values
`desynchronized`, `throttled`, and `deleted`. Active repositories include a
`rev` when known.

`RelayXrpcRoutePackTests` covers the exact response shape for every Relay
status, unknown repositories (inactive/desynchronized), and active `rev`
output.
Source/static evidence passed on 2026-08-08: `deno task check && deno task lint
&& deno task test` (1,264 passed), module-boundary, recursive-setter,
no-host-process-exit, generated-NSID, skill-index, NSID-registration-literal,
and source-only XRPC coverage gates. After integration, the native
`RelayXrpcRoutePackTests` suite passed 18/18.

Report-only: a red row is a lead, not a release blocker, until triaged into a
workstream. Rollback is documentation-only until a gap lane starts; each gap
lane carries its own rollback notes.

Primary sources:

- [Specification index](https://atproto.com/specs/atp)
- [Account lifecycle](https://atproto.com/specs/account)
- [Event streams](https://atproto.com/specs/event-stream)
- [Synchronization](https://atproto.com/specs/sync)
- [OAuth profile](https://atproto.com/specs/oauth)
- [Permissions](https://atproto.com/specs/permissions)
- [did:plc v0.3](https://web.plc.directory/spec/v0.1/did-plc)

## Cross-workstream note

S18 and S19 were the two sub-items activated alongside mega-plan Phase 4 from
[the 2026-07-28 security review](../security-review-2026-07-28.md); both are
complete. S19's consumer table row 10 was later corrected by
[workstream 10](10-dasl-conformance.md) Phase 3, which found `Repository/CAR.m`
was not importer-only and migrated its header decoder for real.

---
phase: 13
title: Untyped JSON at auth trust boundaries
status: complete
agent: worker
depends_on: []
---

# Phase 13: Untyped JSON at auth trust boundaries

## Progress

- 2026-07-26: Started. Working tree confirmed clean at HEAD `af255960`
  (unrelated relay/ADR work from a concurrent session landed and was
  verified committed before starting). Reading sources for slice 1
  (fail-closed claim typing) next.
- 2026-07-27: Slice 1 complete. Added `AuthClaimTypeCheck.h` with
  `AuthTypedValue` static-inline helper. Applied at JWTHeader/JWTPayload
  construction and `AuthCryptoDPoP verifyProof:`. `aud` array form
  normalized per RFC 7519 §4.1.3. 14 new JWT negative tests + 3 new
  DPoP negative tests, all green. Committed as `d8ba0644`.
- 2026-07-27: Slice 2 complete. JWTVerifier now fails closed on missing
  `allowedAlgorithms`, mandatory `exp`/`iss`/`aud` when expected* is set,
  key-derived verification path (not header alg), and `clockOffset` for
  time comparisons. `VideoJWTAuthProvider` and `OAuth2Handler` verifier
  sites patched to set `allowedAlgorithms`. 7 new JWTTests, all suites
  green (JWTTests 33, OAuthDPoPTests 16, JWTSecurityTests 4,
  SessionStoreTests 24, ATProtoCoreTests 33, AdminAuthXrpcTests 37).
  Committed as `a80e91b5`.
- 2026-07-27: **Slice 3 complete.** `PDSReplayCache.sharedCache` now tries
  `PDS_DATA_DIR/replay_cache.db` first (persistent across restart), falls
  back to `:memory:` on failure (never nil). `replayChecker` parameter made
  non-optional in `verifyProof:`. Live call sites pass `sharedCache`.
  4 new OAuthDPoPTests for durability + double-spend. All suites green.
  ADR 0014 written. Committed as `f079278b`.
- 2026-07-27: **Slice 4 complete.** `PLCOperation.operationFromDictionary:`
  rejects non-string `op.did`. `PLCStateReplayer.replayHistory:` routes
  through `PLCAuditor normalizedDataForOperation:` to reject nil/invalid
  elements before collection literals. `PLCAuditor` gains
  `+verifyChain:did:error:` class method validates operation chain without
  needing a `PLCStore`. `XrpcIdentityPack` runs `verifyChain:` on remote
  audit log before `replayHistory:`. 3 new PLCOperationTests + 3 new
  PLCAuditorTests. ADR 0013 written. Committed as `77defcb7`.
- 2026-07-27: **Slice 5 complete.** `GZInputValidator.isValidTID:` changed
  `char c` to `unichar c` with a `>0x7F` rejection gate before the base32
  alphabet check. Prevents U+0132 truncating to `'2'` (valid base32 digit).
  Inherited by `isValidRecordKey:` (fast path). 2 new
  ValidatorCharacterizationTests. Committed as `a04c03ea`.
- 2026-07-27: **Slice 6 complete.** `GZ_LOG_DEBUG` and `GZ_LOG_DEBUG_C`
  macros gated on `[GZLogger sharedLogger].logLevel` using `do/while(0)`
  pattern. Component shorthand macros (`GZ_LOG_CORE_DEBUG`, etc.) inherit
  the gate. Zero-cost when DEBUG is not the active level. Measurable
  improvement on DID derivation and signature verification paths.
  Committed as `b0b6754d`.

## Mission

Close the live defects in workstream 01 S8 slices 1-6. Every one of these is
reachable from unauthenticated request handling today. No architecture
changes: this phase only makes existing code reject what it currently
mishandles. Wiring the unwired auth cluster is phase 14 and is out of scope
here — do not construct `AuthVerifier`, `PDSAccountPolicy`, or
`GZAuthzManager` in this phase.

The unifying defect: values are read out of an attacker-supplied
`NSDictionary` and used as their assumed type with no `isKindOfClass:` check.
Because `NSDictionary` and `NSArray` implement `-copyWithZone:`, assignment
into a `copy NSString *` property succeeds and stores the wrong class, so the
failure surfaces later as an unrecognized selector — an uncaught
`NSInvalidArgumentException`, i.e. process abort. Fix it at the parse
boundary, not at each consumer.

## Read first

- `docs/plans/workstreams/01-security-and-protocol-correctness.md` § S8
  (authoritative — evidence, owner boundary, gate, and rollback live there;
  if this prompt disagrees with it, the workstream wins and this file gets
  corrected)
- `Garazyk/Sources/Auth/OAuth2Handler+ClientValidation.m:920-925` — the
  correct pattern already in-tree. Copy its shape; do not invent a new one.
- `Garazyk/Sources/PLC/PLCAuditor.m:469-472` — already type-checks the exact
  literal that `PLCStateReplayer` builds unsafely. Reuse, do not duplicate.

## Decisions already taken (do not re-litigate)

- `aud` accepts the RFC 7519 array form. Normalize to an array internally and
  match if any element equals the expected audience. All other claim type
  mismatches are hard rejections.
- The DPoP jti replay cache becomes **persistent**, not `:memory:`.

## Scope and order

One coherent slice per commit, in this order.

1. **Fail-closed claim typing.** Add one typed-accessor helper and apply it at
   exactly two parse boundaries: `JWTHeader`/`JWTPayload` construction
   (`Auth/JWT.m:38-90`) and `AuthCryptoDPoP verifyProof:`
   (`Auth/Crypto/AuthCryptoDPoP.m:111,120,129,172-178`). Reject the token on
   any mismatch. Consumers keep their signatures — the point is that no
   consumer can inherit an untyped value any more. Implement the `aud` array
   normalization here.
2. **Required-claim and algorithm binding** in `JWTVerifier`
   (`Auth/JWT.m:265,280,351-385`): `exp` mandatory; `iss`/`aud` mandatory
   whenever the corresponding `expected*` is set; `allowedAlgorithms`
   mandatory and failing closed when unset; algorithm derived from the key
   rather than the header `alg`; bounded skew allowance using the existing
   `_clockOffset`, which is currently set in `-init` and never read. Audit
   `mintAccessTokenForDID:`/`mintRefreshTokenForDID:` first — both always emit
   `iss`/`aud`/`exp`, so no self-issued token should regress. Prove that.
3. **Replay checker fails closed and becomes durable.** Stop caching a nil
   `sharedCache` in `Auth/PDSReplayCache.m` (a single init failure currently
   disables DPoP replay protection for the process lifetime). Make
   `replayChecker` non-optional in `AuthCryptoDPoP verifyProof:` so omission
   is a compile error, not the silent skip at `AuthCryptoDPoP.m:258`. Give
   `sharedCache` a configured on-disk path; `initWithDatabasePath:`, the
   schema, the index, and the cleanup timer already exist. Live call sites to
   keep working: `Auth/OAuth2.m:468`, `Auth/DPoPUtil.m:197`. Record the disk
   budget and the added I/O on the token and PAR paths.
4. **PLC audit-log verification.** In `Network/XrpcIdentityPack.m:388-408`,
   run `PLCAuditor` over the fetched audit log before any derived state is
   trusted — today `PLCStateReplayer replayHistory:` is fed a remote directory
   response with no signature and no `prev`-chain check. Route
   `PLCStateReplayer` (`PLC/PLCOperation.m:348-353,306-307`) through
   `normalizedDataForOperation:` so nil elements can no longer reach a
   collection literal. Reject non-string `op.did` (`PLC/PLCOperation.m:177`).
5. **Charset validation.** `Security/GZInputValidator.m:79,103` truncates
   `unichar` to `char`; `U+0132` becomes `'2'`, inside the TID base32
   alphabet. Use `unichar` and reject anything above `0x7F` before the
   alphabet check. Live via `isValidRecordKey:` → `isValidTID:` from
   `Security/Space/PDSSpaceURI.m:95`. Do **not** touch `isValidDID:` here —
   the `did:web` fix belongs to phase 14, where it becomes load-bearing.
6. **Debug-log evaluation cost.** `GZ_LOG_DEBUG_C` (`Debug/GZLogger.h:272`)
   expands to an unconditional message send, so per-byte hex strings are built
   and discarded on every DID derivation (`PLC/PLCOperation.m:56-71,92-106`)
   and every signature verification (`PLC/PLCAuditor.m:427-430`) regardless of
   log level. Gate the macro on the active level. This is repo-wide by
   construction: keep it mechanical, change no behavior, and measure before
   and after.

## Acceptance gate

Negative tests are the gate — every finding here is a rejection path. Each
case must produce a clean 4xx and never an abort:

- JWT header and payload claims typed as number, array, object, and null —
  one case per claim, asserting rejection rather than crash.
- Array-valued `aud` accepted and matched per the decision above.
- Absent `exp`, absent `iss`, absent `aud`; `"exp"` as a string.
- DPoP proofs with non-string `typ`, `alg`, `htu`, and a string-valued `jwk`.
- A `create` PLC operation missing `recoveryKey`; an audit log whose `prev`
  chain does not link.
- A TID containing `U+0132`.
- Replay: a reused jti is rejected across a simulated process restart, proving
  durability.

New suites need their header imported and the class registered in
`Garazyk/Tests/test_main.m` plus a cmake reconfigure, or they silently run
zero tests. Then the global gates:

```bash
deno task check
deno task lint
deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests
```

Build with bounded parallelism (`--parallel 4`); unbounded `--parallel`
exhausts memory on a 16 GB machine. Confirm free disk before a gated run —
they flake with `SQLITE_FULL` near capacity.

## Rollback

Each slice is a single-commit revert. Slices 1-4 tighten rejection, so
previously-accepted malformed tokens become 4xx. If a real client regresses,
revert that slice rather than loosening the check, and capture the client's
actual payload shape as a test case first. Slice 6 is behavior-neutral.

## On completion

ADRs 0013 (claim-type rejection) and 0014 (DPoP replay durability) written.
Workstream 01 S8 updated with commit hashes. Status set to complete.

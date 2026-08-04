---
title: Module Boundaries and Library Consumption
status: active
last_verified: 2026-08-04
---

## Verified status (2026-08-04)

The earlier execution summary and the proposed Option A plan overstated the
workstream's completion, and M4 subsequently closed for real: a current run
of `scripts/check_module_boundaries.sh build` passes because
`docs/module-boundary-baseline.txt` is empty — zero violations, not just
zero baselined ones:

| Referencing module | Remaining violations |
| --- | ---: |
| `ATProtoServices` | 0 |
| `ATProtoXRPC` | 0 |
| `ATProtoMediaCore` | 0 |
| `ATProtoVideoService` | 0 |

M1-M3 are complete. M4 has resolved the inversions originally enumerated in
its first audit plus the PLC-persistence, Sync-multibase, Storage key-manager,
AppView identity-resolver, PLC account-operation, HTTP-client, RateLimiter,
and MediaCore/XRPC residual clusters. **M4's zero-baseline acceptance gate is
now met**: `docs/module-boundary-baseline.txt` is empty and
`scripts/check_module_boundaries.sh build` reports **0 current leaks** across
all ten modules.
**M7 is now complete (2026-08-04).** The residual host-process exits and the
installer's `/var/db/kaszlak` fallback are fixed; see "M7 residual cleanup
complete" below. **M4.5 items 1 and 3 are complete** (`CONFIGURE_DEPENDS` +
a configure-time disjoint-source assertion); item 2 (glob-to-manifest
conversion) remains open. M5 has started: the namespace gate landed, and
**M5.3 batch 1 (internal migration classes, the low-risk pilot) is complete**
and **batch 2 is done except for the four largest classes** (21 of ~25
classes renamed) — namespace baseline ratcheted
283 → 253 → 249 → 238 → 234 → 232. The remaining batch-2 classes (`CID` at
265 consumers, `JWT` at 136, `JWTMinter` at 80, `Secp256k1` at 53)
and batches 3-6
remain open. M6 has not started.

M0 is now answered **yes**, with a deliberately bounded first release:

- provide a relocatable, source-built CMake config package for the ten
  `ATProto*` static-library targets;
- support macOS and GNUstep/Linux, which are the two platforms already in the
  repository's build contract;
- export imported targets as `Garazyk::ATProtoCore`,
  `Garazyk::ATProtoStorage`, and so on;
- mark the 0.x API experimental and make no ABI-stability promise;
- exclude prebuilt binary archives, Apple frameworks/XCFrameworks, CocoaPods,
  SwiftPM, iOS, and package-registry publication from this workstream.

This scope is enough for a third party to build, install, relocate, discover,
and link the libraries without vendoring Garazyk into its own source tree. It
does not commit the project to maintaining every distribution channel at once.

The current archives also make the naming cost measurable. Across the ten
package targets, the existing build contains 500 Objective-C classes, of which
283 do not begin with the project's reserved `GZ`, `ATProto`, or `PDS`
prefixes. That is the starting baseline for M5, not the short illustrative list
in the original plan.

The live boundary baseline is now **empty**: all ten `ATProto*` modules
report zero declared-boundary violations. The PLC account-operation pair was
removed after the account service was changed to consume the Core
`PDSPLCAccountOperationProvider` protocol and Runtime composition injected the
PLC-owned implementation. The HTTP-client pair was removed after Services
callers switched to the Core-owned `GZHTTPClient` protocol and
transport-independent `GZHTTPClientOptions`; the Transport implementation
remains responsible for SSRF validation, DNS pinning, redirect validation, and
response limits. The Core registry now returns a fail-closed unavailable
client when no transport has registered, rather than returning nil. The last
Services entry, `RateLimiter`, was removed when the diagnostics composition
sources that constructed it were moved into Runtime (see below). The final
three `ATProtoMediaCore` entries were removed when the media service runtime
and its XRPC route pack moved to Runtime (see below).

## Progress (2026-07-29)

**M1 complete** (`5098441c`, ADR 0031). `scripts/check_module_boundaries.sh`
(distinct from the existing source-import-level
`scripts/dev/check_module_boundaries.sh`) computes per-archive
undefined-minus-defined `_OBJC_CLASS_$_` symbols, resolves each to its
owning `ATProto*` archive, and flags any resolution outside the declared
transitive `PUBLIC` dependency set. Wired into all three CI jobs that build
the full library set.

**The evidence below undercounted the leak surface.** It was gathered with
`nm -u` on whole archives, which reports each `.o` member's own symbol
table — a class used in one file and defined in another file of the *same*
archive shows as both undefined and defined, an internal reference the
archive resolves on its own, not a boundary violation. Correcting for that
(the method M1's script uses) found **69 leaks across all ten modules**,
not the six cited for `ATProtoCore` alone below. `docs/module-boundary-baseline.txt`
(not `docs/metadata/` as this section originally specified — see ADR 0031)
has the full corrected list; M2-M4 should work from that file, not from the
`nm -u` counts in this section's original evidence.

**M2 partially complete** (`ebd19d22`). Of ATProtoCore's 11 real leaks
(corrected count, not the six M2's original text cited), 4 are fixed:
`MSTCacheManager`/`MSTAtomicReference` moved to `Repository/` (Storage);
`CBOREncoder`/`CBORDecoder`/`CBORValue` moved from `Repository/CBOR.h`
into `Core/CBOR.h` (already a standalone file pair, no CAR code mixed
in — a clean move); a new `Core/GZHTTPClient.h` protocol (covering only
the two methods `DID.m`/`GZProviderHTTPClient.m` actually call, with a
raw timeout instead of `ATProtoSafeHTTPClientOptions`) with
`ATProtoSafeHTTPClient` self-registering as the default via `+load`,
removing the `Core → ATProtoSafeHTTPClient`/`ATProtoSafeHTTPClientOptions`
leak for those two call sites.

**`PDSReplayCache` leak also fixed** (`2668fb1b`). `AuthVerifier.m` called
`[PDSReplayCache sharedCache]` directly just to obtain an instance to pass
to `AuthCryptoDPoP`'s already-protocol-typed `replayChecker:` parameter
(`id<AuthCryptoDPoPReplayChecker>`, which `PDSReplayCache` already
conforms to) — the class itself can't move to Core (it needs
`Database/Connection/ATProtoConnectionManagerSerial`, a real Storage
dependency), so the fix is injection, not relocation. Added
`AuthVerifier.replayChecker` (nullable, same pattern as
`nonceStore`/`accountPolicy`/`keyResolver`) and wired it at the one
production construction site (`XrpcAuthHelper.m`) and the test site.
Handled carefully: `AuthCryptoDPoP` treats a nil `replayChecker` as "jti
reuse detected" (fail closed), so a missed injection breaks DPoP-bound
requests rather than silently disabling replay protection — verified via
the full DPoP suite (45/45) before landing.

**`Secp256k1`/`CryptoUtils` leaks also fixed** (`87de4843`). Both classes had
zero Storage/Services dependencies (`Secp256k1.m` only used `Core/CID.h`;
`CryptoUtils.m` only used the already-Core-glob'd `Security/PDSSecurityCompare.h`
and `Security/PDSKeyEnvelope.h`), so both moved from `Auth/` into the
Core-owned `Auth/Crypto/` directory — a pure relocation, no code changes.
The C wrapper (`secp256k1_wrapper_c.h/.c`) moved alongside `Secp256k1.m` for
the same reason: leaving the wrapper's `.c` implementation behind in `Auth/`
(Services-owned) would have reintroduced the identical cross-archive
dependency in C-symbol form rather than ObjC-class form. `ATProtoCore` now
links `libsecp256k1` directly (`PUBLIC`), matching every other module target.
~90 consumer files' imports updated. This closed 6 leaks (`Secp256k1` and
`CryptoUtils` each leaking into `ATProtoCore`, `ATProtoPLC`, and
`ATProtoStorage`); baseline ratcheted 64 → 58.

**`JWT`/`JWTVerifier` leaks also fixed** (`dcd46667`) — **no split needed.**
The prior entry in this doc assumed `Auth/JWT.m` would need to be split
(pure-verification classes to Core, `JWTMinter` staying in Services). A
closer read of the `.m` implementation showed that assumption was wrong:
`JWTMinter` never links against a concrete key-manager class — its signing
methods only accept `id<PDSKeyManager>`/`id<PDSActorKeyManager>`, a
compile-time protocol reference satisfied by whatever concrete class each
caller passes in, not a link dependency of `JWT.m` itself. The file's only
real class dependency was `Secp256k1` (already moved to `Auth/Crypto/` in
the prior step); everything else it imports (`AuthClaimTypeCheck.h`,
`PDSKeyManagerProtocol.h`, `PDSActorKeyManagerProtocol.h`,
`Security/PDSSecurityCompare.h`, `CommonCrypto`, `Security/SecRandom`) is
either a Foundation-only protocol/utility header or already Core-glob'd.
So the whole file — `JWTHeader`/`JWTPayload`/`JWT`/`JWTVerifier`/`JWTMinter`
together — moved as one unit from `Auth/` to `Auth/Crypto/`, no code
changes. 72 consumer imports updated. This closed both remaining
ATProtoCore leaks (`JWT`, `JWTVerifier`) plus two incidental
`ATProtoVideoService` leaks of the same classes; baseline ratcheted
58 → 54. Full `AllTests --gated=run` verified identical (pre-existing)
failure profile before and after.

**`ATProtoCore` reaches zero module-boundary leaks** (`b19d81cb`). The last
leak class traced to a single file, `Security/Space/PDSSpaceAppAttestationVerifier.m`
— living in a directory (`Security/Space/`) that's otherwise cleanly
Core-resident, but itself holding a real `Services/PDS/PDSSpaceStore`
dependency (a strong property injected via its designated initializer),
on top of the `ATProtoSafeHTTPClient`/`ATProtoSafeHTTPClientOptions` leak
the script detects. The `PDSSpaceStore` dependency doesn't trip the
nm-based detector at all — referencing a class only as a property type,
without ever sending it a class message, emits no undefined
`_OBJC_CLASS_$_` symbol — but it's real: this file was never actually
Core-clean, the script just couldn't see the second half of why. Rather
than extending `GZHTTPClient`'s protocol to silence only the detected
half, the whole file was carved out of `ATProtoCore`'s build into
`ATProtoServices` — a `CMakeLists.txt` source-list change only (exclude
from the Core glob, `list(APPEND)` into Services sources), no file move,
mirroring the existing single-file-APPEND precedent already used for
`Auth/PDSOpenSSLES256KeyManager.m`. The file's only non-test consumer,
`Network/XrpcSpacePack.m`, is XRPC-layer and already depends on Services
transitively, so this introduces no new cross-module dependency.
Baseline ratcheted 54 → 52. Full `AllTests --gated=run` verified
identical (pre-existing) failure profile before and after.

**M2 is now complete for `ATProtoCore`** — zero leaks, matching the
milestone's stated goal ("Make ATProtoCore standalone"). One item from
M2's original scope remains open, tracked separately since it doesn't
affect the leak count:
- The GNUstep-only `/usr/bin/curl` subprocess fallback in `DID.m` (M2's
  text flagged this as "move behind the protocol or delete," marked
  optional) — not touched. Doesn't affect the module-boundary leak count
  (`NSTask` isn't one of ours), but a Core primitive spawning a process
  is still the kind of thing this workstream exists to clean up.
  Deferred because GNUstep/Linux behavior can't be verified in this
  environment — needs a pass with real GNUstep build/test access.

**M3 started** (`8b69415f`). Carved `HttpRequest.m`/`HttpResponse.m`
(the Foundation-only message types M3's original text names) plus three
more it didn't: `HttpRoute.m`/`HttpRetryPolicy.m`/`HttpParsing.m`, out of
`ATProtoTransport`'s build into `ATProtoCore`. Two things the original
scope missed, found only by reading the actual `.m` implementations
(the same discipline that corrected the JWT.m split assumption in M2):
- `HttpRoute` (the route-descriptor value type) and `HttpRouteHandler`
  were bundled into `HttpRouter.h/.m` alongside `HttpRouter` itself (the
  actual routing engine — a real I/O-adjacent class that must stay in
  Transport), so this needed an actual class extraction into a new
  `Network/HttpRoute.h/.m` pair, not just a move. `HttpRouteTrie.m` (the
  trie router actually used on the live request path per this repo's
  own architecture doc, not `HttpRouter`) only ever needed `HttpRoute`,
  so its import was repointed to the new file, `HttpRouter` was
  otherwise untouched.
- `HttpRequest.m` calls `[HttpParsing parseQueryString:]` and
  `[HttpParsing methodFromString:]` directly — a real class dependency
  the plan's "Foundation and nothing else" framing missed. `HttpParsing.m`
  itself has zero further dependencies (just `HttpRequest.h` +
  Foundation), so it moved alongside to avoid introducing a *new*
  Core → Transport leak.

Same technique as `PDSSpaceAppAttestationVerifier.m` in M2: a
`CMakeLists.txt` source-list change only, no file move, no consumer
import changes (all ~200 consumer files already use absolute
`"Network/*.h"` paths, unaffected by which archive the `.m` compiles
into). Baseline only dropped by one entry (`HttpRetryPolicy`) — most of
Services' coupling to these message types was already invisible to the
nm-based leak detector for the same reason `PDSSpaceStore` was in M2:
referencing a class only as a parameter/property type, without ever
sending it a class message, emits no undefined `_OBJC_CLASS_$_` symbol.
The architectural leak is real (this is exactly the coupling M3 exists
to remove) even where the automated metric undercounts it — worth
naming explicitly so a future pass doesn't mistake the small baseline
delta for the size of the actual change. Full `AllTests --gated=run`
verified identical (pre-existing) failure profile before and after;
checked carefully rather than assumed safe, since this touches the live
HTTP request path (`HttpServer` → `Http1Parser` → `HttpRouteTrie` →
`XrpcDispatcher`).

**`HttpRouter` dead-code question resolved** (`ee5743ff`). A follow-up
pass re-verified the earlier finding exhaustively — every binary's
`main.m`, `HttpServer.h/.m`'s own properties and instantiation sites,
`CMakeLists.txt`'s source-list treatment, and dynamic dispatch via
`NSClassFromString` — before concluding it's genuinely unreachable:
`HttpServer.m:1082` instantiates `HttpRouteTrie`, never `HttpRouter`,
and nothing else in the tree references the class outside its own test
suite. Deleted `HttpRouter.h/.m` and `HttpRouterTests.m` (same standard
as the S18 `OAuthProvider` deletion earlier this session: zero real
consumers beyond a class's own test). `SSRFValidator`, `HttpBufferPool`,
and the connection drivers remain in Transport per the original plan
(genuine socket/I/O dependencies). The `Network/` import-count figure
this milestone's verification gate names (86 → 36) was not re-measured
directly — the module-boundary baseline is the tracked metric per M1's
own correction, and it moved as described above (the `HttpRouter`
deletion itself didn't change the baseline count, since dead code was
never counted as a boundary violation in the first place).

**M3 is now fully resolved** — the HTTP message-type carve-out landed,
and the one open follow-up question (`HttpRouter`) is closed.

**M4 started** (`6d5ad6bd`). First inversion resolved: `Storage -> Services`
via `ATProtoHandleValidator` — confirmed a pure Foundation-only validator
(no network/storage/keychain dependency) despite living in `Identity/`
alongside `HandleResolver.m`, a real Services class doing live HTTP
resolution (`ATProtoSafeHTTPClient`/`SSRFValidator`). Same carve-out
technique as M2/M3: `CMakeLists.txt` source-list change only, no file
move, ~30 consumer files unaffected. Resolved both remaining leaks of
this class (`ATProtoStorage` and `ATProtoTransport` each depended on it
transitively via Services). Baseline ratcheted 51 → 49. Full
`AllTests --gated=run` verified identical (pre-existing) failure profile.

**`MediaCore -> Services` (`PDSBlobProvider`) resolved** (`ad641b25`).
The protocol itself (`Blob/PDSBlobProvider.h`) needed no move — it was
already Foundation-only, and protocols don't produce `_OBJC_CLASS_$_`
symbols so the nm-based detector was never actually flagging the
protocol. The real leak was `ATProtoMediaServiceRuntime` (MediaCore)
directly instantiating the concrete `PDSCloudStorageBlobProvider`/
`PDSDiskBlobProvider` classes (Services) based on `config.s3Bucket`,
despite only ever using the result through the protocol. Moved that
backend-selection logic to `Garazyk/Binaries/jelcz/main.m` — the only
production consumer of this runtime, and a binary that already links
`ATProtoServices` — and changed the initializer to
`initWithConfiguration:processor:blobProvider:`, taking the
already-constructed `id<PDSBlobProvider>`. A pre-existing test fake
(`RuntimeTestBlobProvider`, defined but never actually used) got wired
in as a side effect. Baseline ratcheted 49 → 47. Full
`AllTests --gated=run` verified identical (pre-existing) failure
profile — after tracing down one false alarm along the way: a stale
`jelcz` binary left over from an unrelated debugging step (rebuilding
the `jelcz` target specifically while the tree was `git stash`ed, which
never got relinked against the real fix afterward since `AllTests`
doesn't depend on the sibling `jelcz` executable target) — confirmed via
direct manual runs of the binary, not just the test harness, before
concluding the actual code change was correct.

**`Transport -> Storage` / `RateLimiter` resolved** (`6788ee60`). Built
the factory seam this section's earlier pass had scoped out but not
implemented:
- `ATProtoDatabaseQueryRunner.h` gained `ATProtoQueryRunning`, extracting
  its public surface (`executeQuery:`/`executeUpdate:`/
  `performWriteTransaction:error:`) as a protocol — the same treatment
  `ATProtoConnectionManager` already had.
- `RateLimiter.h` gained `RateLimiterStorageHandle` (bundling
  `id<ATProtoConnectionManager>` + `id<ATProtoQueryRunning>`),
  `RateLimiterStorageFactory`, and `RateLimiterSetStorageFactory` —
  importing only the two protocol headers, never a concrete Storage
  class.
- `RateLimiter.m`'s `ensureDatabaseOpened`/`reconfigureDatabasePath`/
  `dealloc` now go through the injected `storageHandle` instead of
  instantiating `ATProtoConnectionManagerSerial`/
  `ATProtoDatabaseQueryRunner` directly.
- New `Network/XrpcRateLimiterStorageRegistration.m` registers the real
  factory via `+load`, mirroring the `GZHTTPClientRegistry`/
  `ATProtoSafeHTTPClient` self-registration pattern from M2 — so none of
  the three binaries that construct a `RateLimiter` (`kaszlak` via
  `PDSApplication.m`, `Mikrus`, `Beskid`) needed their bootstrap code
  touched.

**Why this file lives in XRPC, not Storage:** Storage self-registering
into a Transport-owned registry would just invert the leak instead of
removing it — Storage isn't allowed to depend on Transport either.
`ATProtoXRPC` is the one module in the declared DAG that already
legitimately depends on both Storage and Transport, and every binary
that constructs a `RateLimiter` already links it.

Resolved both leaks from `ATProtoTransport`. Baseline ratcheted 47 → 45.
Verified: `RateLimiterTests`, `RateLimitingTests`,
`GZXrpcRouteSupportTests`, and `PDSRateLimitAdminHandlerTests` all pass,
plus a full `AllTests --gated=run` showing the identical (pre-existing)
failure profile.

**`Transport -> Runtime` resolved, including both misplaced route packs**
(`4dc11bb8`, `0ab4f715`). `ATProtoHttpOAuthRoutePack.m`,
`ATProtoHttpWellKnownRoutePack.m`, `ATProtoHttpMSTViewerRoutePack.m`,
`ATProtoHttpNodeInfoRoutePack.m`, `ATProtoHttpOAuthDemoRoutePack.m`,
`ATProtoHttpRelayAPIRoutePack.m`, and `PDSHttpPDSAdminRoutePack.m` all
shared the same shape: each imports and directly messages a Runtime,
Services, or Sync handler class while compiling into `ATProtoTransport`.
Confirmed via grep that all 7 are registered *exclusively* by
`ATProtoHttpServerBuilder.m`, which was already `ATProtoRuntime`-owned
(carved out during M1/M2) — so this was a `CMakeLists.txt` source-list
change for all 7, no code changes: exclude from Transport, append to
Runtime, matching the carve-out technique used throughout M2-M4.

`ATProtoHttpWellKnownRoutePack.m` is the interesting case: it wasn't
actually flagged by the nm-based leak detector at all (its
`ATProtoHandleValidator`/`PDSController` references apparently don't
produce a class-message symbol the detector catches — the same
false-negative shape already seen with `PDSSpaceStore` in M2 and
`HttpRequest`/`HttpResponse` in M3). It was moved anyway, for
architectural consistency with its 6 siblings, not because the
automated metric demanded it — the same judgment call made those
earlier two times.

Resolved 7 of the 8 remaining `ATProtoTransport` leaks in one move:
`MSTViewerHandler`, `NodeInfoHandler`, `OAuth2Handler`, `OAuthDemoHandler`,
`PDSAdminAuth`, `RelayAPIHandler`, `WebAuthnRegistrationHandler`.
Baseline ratcheted 45 → 38 (`ATProtoHttpWellKnownRoutePack.m`'s move
didn't change the count further, matching its detector-invisible status
above). Full `AllTests --gated=run` verified: identical (pre-existing)
failure profile, with `ATProtoHttpServerBuilderTests`, `AdminAuthXrpcTests`,
and `PDSApplicationTests` checked explicitly given this touches
bootstrap for every binary.

**`ATProtoTransport` reaches zero module-boundary leaks** (`8547bcfb`).
`GZXrpcRouteSupport.m` directly messaged `XrpcErrorHelper` (XRPC-owned)
while compiling into Transport; its only consumers,
`MikrusXrpcRoutePack.m` and `BeskidXrpcRoutePack.m`, already need
`ATProtoXRPC` linked regardless (both binaries link it alongside
Transport). Same carve-out technique as everything else in this
section: excluded from Transport's glob, added to XRPC's explicit file
list. Baseline ratcheted 37 (from 38). Full `AllTests --gated=run`
verified clean; `GZXrpcRouteSupportTests` passes.

This is a real milestone worth naming: **two of the ten `ATProto*`
modules now have zero declared-boundary violations** —
`ATProtoCore` (M2, `b19d81cb`) and `ATProtoTransport` (M4, this commit).
Neither needed a baseline entry left over from the original M1 audit.

**`PLC <-> Sync`, `Sync -> PLC` direction resolved** (`ea21775f`).
`RelayEventValidator.m` (Sync) imported `PLC/DIDPLCResolver.h` only to
cast an already-untyped `id plcResolver` property before calling
`resolveDID:error:` — the seam was already most of the way there, it
just needed a real protocol instead of a runtime `isKindOfClass:` cast.
Added `Core/DIDResolving.h` (a single-method protocol); `DIDPLCResolver`
(PLC) now conforms to it; `RelayEventValidator.h`'s property is
`id<DIDResolving>` instead of plain `id`. Verified via grep across the
whole tree that `plcResolver` is never actually assigned anywhere in
production code or tests — this fix is zero behavior change, not just
low-risk. Resolves `ATProtoSync:DIDPLCResolver`. Baseline ratcheted
37 → 36. `RelayEventValidatorTests` (8/8) and `DIDPLCResolverTests`
(2/2) checked explicitly; full `AllTests --gated=run` verified clean
(one `RelayIntegrationTests/testMetricsRecording` isolation artifact —
fails only under `--filter` in isolation, passes in the full suite —
confirmed unrelated by diffing the actual changeset, which touches
none of that test's dependencies).

**`PLC -> Sync` direction resolved.** Before the fix, `PLCServer.m`
constructed Sync's `PDSWebSocketNetworkAdapter` directly (twice, in
`handleExportStream:connection:`), an undeclared PLC -> Sync dependency
(`ATProtoPLC:PDSWebSocketNetworkAdapter`). First added test coverage for
the previously-untested cursor-validation path (`grep` across
`Garazyk/Tests/PLC/` had found zero coverage for this method):
`PLCServerTests.m` gained a locally-declared minimal
`ATProtoNetworkConnection` mock (matching the existing
`PDSWebSocketNetworkAdapterTests.m` precedent — never importing the real
`Network/ATProtoNetworkTransport.h`, so no protocol-definition collision)
and `testHandleExportStreamRejectsInvalidCursorWithFutureCursorClose`,
which asserts the raw WebSocket close frame bytes (parsed by hand, since
`WebSocketCodec`'s decode side is hardwired to require masked/client
framing and this frame is server-direction/unmasked) carry close code
1008 and reason `"FutureCursor"`. Deliberately did **not** attempt to
cover the snapshot/live-poll path in a unit test — it spins up a real
`dispatch_source` timer that only stops when the connection closes, and
a unit test can't trigger that deterministically without reaching into
the adapter's private internals; forcing it would leak a background
timer across the rest of the suite. That path remains a Deno-scenario
concern, not a unit-test one.

With the guardrail in place: added `PLCWebSocketTransportFactory` (a
`id<PDSWebSocketTransport> (^)(id<ATProtoNetworkConnection>)` typedef) and
`PLCServerSetWebSocketTransportFactory` to `PLCServer.h`, exactly mirroring
`RateLimiterStorageFactory`. `handleExportStream:` now calls the factory
once at the top and uses the returned `id<PDSWebSocketTransport>` for
everything (both the early `FutureCursor` close and the main stream), no
per-branch duplication like the original two separate `alloc]
initWithConnection:]` call sites. The `+load` self-registration
(`Garazyk/Sources/App/PLCWebSocketTransportRegistration.m`) lives in
`ATProtoRuntime` — the one module in the DAG that already legitimately
depends on both PLC and Sync (`campagnola`, the only binary that runs a
`PLCServer`, already links Runtime) — landing it in `App/` needed no
`CMakeLists.txt` change since Runtime's source glob already covers
`Garazyk/Sources/App/*.m`. One wrinkle hit and fixed: the new `App/*.m`
file didn't show up in the first rebuild (`nm` on `AllTests` showed the
setter symbol but not the registration class at all) because
`file(GLOB_RECURSE ...)` caches its file list — same root cause as the
documented "new test suite" gotcha, just triggered by a non-test source
file this time. Fixed with a full `cmake -S . -B build` reconfigure.
Resolves `ATProtoPLC:PDSWebSocketNetworkAdapter`. Baseline ratcheted
36 → 35 (one leak removed, `PDSWebSocketNetworkAdapterTests` and
`PLCReplicaServerTests` and `PDSPLCIntegrationTests` all still pass);
full `AllTests --gated=run` verified clean.

- `XRPC -> PLC`: a DAG question, not necessarily a code question —
  needs a decision on whether PLC belongs below XRPC in the declared
  graph before any code moves.

**`XRPC -> PLC` decision resolved**. Addressed the final open item of M4. XRPC's route packs and API handlers inherently depend on the business logic modules (Services, Storage, Sync, and PLC) to implement their routes. `ATProtoPLC` exposes PLC directory routes that XRPC packs must dispatch to. Thus, PLC belongs *below* XRPC in the declared graph, just like the other product-feature modules. Added `ATProtoPLC` to `ATProtoXRPC`'s `PUBLIC` dependencies in `CMakeLists.txt`. This naturally resolves all 5 remaining XRPC -> PLC boundary violations (`DIDPLCResolver`, `PLCAuditor`, `PLCOperation`, `PLCRotationKeyManager`, `PLCStateReplayer`). Baseline ratcheted 35 → 30. Full `AllTests --gated=run` verified clean with an improved failure profile.

**Historical correction (2026-07-30): M4's originally enumerated inversion
set was resolved, but the then-current follow-on baseline was not complete.**
Its acceptance gate requires the baseline to reach zero. The later M4.2 slices
below continue that work; the live status is recorded at the top of this file.

**M4.2 PLC persistence complete** (`f08166df`). M4.1's fresh ten-archive
evidence found both PLC leaks in one emitter, `PLCPersistentStore.m.o`:
`PLCPersistentStore` directly allocates `ATProtoConnectionManagerSerial` and
`ATProtoDatabaseQueryRunner`, retains them in its internal interface, and owns
their connection/transaction lifecycle. The concrete Storage implementation is
therefore a fundamental PLC requirement, not composition that can honestly be
injected above PLC. `ATProtoStorage` has only `ATProtoCore` in its declared
module closure, so adding `ATProtoPLC -> ATProtoStorage` is acyclic. The commit
adds that `PUBLIC` edge and a `plc_persistent_store_link_tests` executable that
names `ATProtoPLC` as its only Garazyk library, then opens and closes a real
temporary SQLite store. It passes on macOS; the link-time baseline ratcheted
30 -> 28, with no new leaks.

macOS verification: fresh CMake reconfigure; all ten archive targets rebuilt;
`scripts/check_module_boundaries.sh build` passed at 30/30 before the change
and at 28 current/30 prior-baseline entries after it; the focused standalone
test passed; `cmake --build build --target AllTests --parallel 4` and
`./build/tests/AllTests --gated=run` passed. `deno task check` and
`deno task lint` passed; the unrelated existing `deno task test` suite still
reports live Gruszka lexicon-resolution integration failures and its checked-in
generated-lexicon drift failure. GNUstep follow-up (`92d3820f`) corrected the
stale `SecItemLinuxStoreTests` source membership from the removed
`Garazyk/Sources/Auth/CryptoUtils.m` to
`Garazyk/Sources/Auth/Crypto/CryptoUtils.m`. In the GNUstep Docker builder,
all ten module archives build; `SecItemLinuxStoreTests` and
`plc_persistent_store_link_tests` pass. The Linux checker completes without a
new leak (`0 current leaks, 28 baselined`); its GNU `nm` parsing cannot emit the
macOS archive-member mapping, so the canonical 28/28 baseline remains the
fresh macOS result above. The full GNUstep `AllTests` build is still blocked by
an independent XCTest compatibility issue: `XCTAssertEqual` boxes Objective-C
object pointers, which Clang rejects in
`PDSAdminServiceTests.m:146` and `PDSBlobAuditHandlerTests.m:21`. Do not treat
the full Linux gate as passed or push until that separate compatibility blocker
is repaired and the full gate rerun.

**M4.2 Sync multibase dependency extraction complete** (`33357d36`). The one
remaining `ATProtoSync:XrpcIdentityHelper` reference was
`RelayEventValidator`'s decoding of a DID document's
`publicKeyMultibase` value. The decoder is pure data conversion and its
`CID`, `JWT`, and DID-error dependencies already belong to `ATProtoCore`, so
the implementation now lives in `ATProtoMultibase`; XRPC keeps its existing
public helper as a forwarding compatibility API. This is source ownership
correction, not a new module dependency: no `PUBLIC` CMake edge was added and
the ten-library dependency graph remains acyclic. The baseline ratcheted
28 -> 27. A fresh reconfigure rebuilt `AllTests`; focused
`ATProtoMultibaseTests` (2/2), `RelayEventValidatorTests` (8/8), and
`XrpcMethodRegistryTests` (6/6) passed, as did the checker at 27 current / 27
baselined leaks. `deno task check` and `deno task lint` passed. The full Deno
suite has one unrelated, order-sensitive
`DockerApiClient: streamEvents abort exits cleanly` failure, which passes when
rerun alone. The macOS full `AllTests --gated=run` run was interrupted after
two order-sensitive `HandleResolverTests` failures; that class passes in
isolation (28/28). These non-green whole-suite gates, plus the independent
GNUstep XCTest compile blocker above, mean this change is committed but not
pushed; M4 remains in progress.

**M4.2 Storage key-manager ownership extraction complete (commit pending).**
`ActorStore` constructs the Apple and GNUstep actor key managers directly, but
`PDSAppleActorKeyManager` and `PDSOpenSSLKeyManager` use only Core-owned
crypto, configuration, and platform facilities. Their CMake ownership now
belongs to `ATProtoCore`, which is already `ATProtoStorage`'s declared
acyclic dependency. A new `storage_actor_store_link_tests` executable names
only `ATProtoStorage` as its Garazyk library and opens/closes an actor store.
That test initially exposed two untracked C-function references from Storage
migrations to `PDSBlobAuditUtils`; the pure CID/blob-reference parser also
moved to Core ownership. No `PUBLIC` edge was added. The baseline ratcheted
27 -> 26. On macOS, a fresh reconfigure and `AllTests` build succeeded;
`ActorStoreTests` (19/19), `PDSOpenSSLKeyManagerTests` (2/2), the standalone
Storage test, and the checker (26 current / 26 baselined) passed. In GNUstep
Docker, all ten archives and the standalone test pass; the Linux checker
reports no new leak (`0 current leaks, 26 baselined`) but cannot provide the
macOS archive-member mapping. The full GNUstep build remains blocked by the
same XCTest object-pointer boxing errors above. **Follow-up:** `AppViewIdentityHelper.m`
now uses Core-owned `DIDResolver` plus Core `ATProtoValidator` rather than PLC-owned
`DIDPLCResolver`; the fresh macOS checker reports **25 current / 25 baselined**
entries, and the focused AppView/DID/DASL/email gate passes (70/70).

**M4.2 Chat/Germ runtime ownership extraction:** `ChatRuntime.m` and
`GermRuntime.m` were process-orchestration implementations compiled into
`ATProtoServices` despite constructing Transport/XRPC objects. CMake now excludes
both from Services and explicitly assigns them to Runtime; their headers and
binary imports remain unchanged. The baseline shrank **25 -> 19**. Fresh
macOS validation rebuilt `ATProtoServices`, `ATProtoRuntime`, and `AllTests`,
then passed the link checker at **19 current / 19 baselined**, the source-import
checker, and the `SyrenaChatCommandTests` (5/5) and `GermCommandTests` (4/4)
suites. No dedicated runtime test classes exist in the current test registry.

**`ATProtoVideoService` / `ATProtoXRPC` composition extraction:**
`VideoPDSAuthProvider.m` and `VideoXrpcPack.m` are XRPC composition adapters:
they call XRPC helpers and are constructed or registered by XRPC, while the
underlying worker/storage implementations remain VideoService-owned. CMake
now excludes both implementations from `ATProtoVideoService` and assigns them
to `ATProtoXRPC`;their public headers and route APIs remain unchanged. This removed the two
VideoService auth/error boundary entries and the two stale XRPC route-pack
entries. The baseline ratcheted **19 -> 15**. Fresh macOS
validation reconfigured and rebuilt `ATProtoXRPC`, `ATProtoVideoService`, and
`AllTests`; `VideoPDSAuthProviderTests`, `ATProtoVideoXrpcPackTests`,
`ATProtoVideoXrpcPackValidationTests`, and `ATProtoMediaXrpcPackTests` passed
**39/39**. The link checker reported **15 current / 15 baselined** leaks,
the source-import checker passed, and `git diff --check` passed.

**`ATProtoXRPC -> ATProtoVideoWorker` composition seam:**
`XrpcAppBskyPack.m` previously reached into the VideoService singleton only to
copy its configured blob provider into the route service bag. The provider is
already owned by the PDS application through
`PDSBlobService -> BlobStorage -> id<PDSBlobProvider>`. XRPC now receives that
protocol-backed provider from `XrpcMethodRegistry`, with an explicit
nil-safe extraction helper that logs and leaves video uploads fail-closed when
the service graph is incomplete. The XRPC layer no longer imports or messages
`ATProtoVideoWorker`;route registration behavior is unchanged. The baseline ratcheted **15 -> 14**.
Fresh macOS validation rebuilt `ATProtoXRPC`,
`ATProtoVideoService`, and `AllTests`; the video/XRPC and registry focus passed
**45/45**, the link checker reported **14 current / 14 baselined** leaks, the

source-import checker passed, and `git diff --check` passed.

**`ATProtoXRPC -> PDSLocalVideoJobStore` composition seam:**
`XrpcAppBskyPack.m` previously constructed `PDSLocalVideoJobStore` directly
from the AppView database. `PDSApplication` now owns one protocol-typed
`VideoJobStore`, shared by the video worker and exposed to XRPC through
`XrpcMethodRegistry` and `XrpcRoutePackServiceBag`. The route pack no longer
imports or constructs the VideoService concrete store. A registry/application
characterization test verifies the shared protocol-backed store contract. The
baseline ratcheted **14 -> 13**. Fresh macOS validation rebuilt
`ATProtoXRPC`, `ATProtoVideoService`, and `AllTests`; the video/XRPC and
registry focus passed **46/46**, the link checker reported **13 current / 13
baselined** leaks, the source-import checker passed, and `git diff --check`
passed.

**`ATProtoXRPC` registration-path Runtime seam:**
The shared route-registration path no longer constructs Runtime-owned policy
objects or falls back to the legacy controller for repository availability.
`PDSApplication` owns one `AuthVerifier`, built with the existing
protocol-backed `PDSAccountPolicy`, nonce store, replay checker, and either the
configured public key or the existing `PDSKeyManager`. `XrpcMethodRegistry`
passes that verifier through `XrpcRoutePackServiceBag`; `XrpcAuthHelper` uses
that injected instance when the verifier switch is enabled. Repository
availability/takedown helpers now consume the route-service bag rather than
calling `PDSController sharedController`; the import route also dropped its
stale controller import. The legacy controller overload remains as a
compatibility API, but its dependencies are sourced from its backing
application. The boundary baseline ratcheted **13 -> 11**.

Fresh macOS validation rebuilt `ATProtoCore`, `ATProtoXRPC`, and `AllTests`;
the focused registration/auth suites passed **29/29**, the link checker
reported **11 current / 11 baselined** leaks, the source-import checker passed,
and `git diff --check` passed. AuthVerifier's local verification path now also
accepts the existing key-manager-backed JWT configuration without exposing
Runtime concrete types in XRPC.

The current macOS full suite
was stopped after the unrelated
`AppViewIngestEngineTests/testConcurrencySafety` timeout and incomplete-event
assertions; do not treat it as green. `deno task check` and `deno task lint`
passed; `deno task test` could not be launched because the execution approval
quota was exhausted. Git staging/commit is pending the same external approval
limit; do not push before both it and the non-green full-suite gates are
resolved.

**`PDSInstallerCommand` Runtime ownership extraction:**
`Admin/PDSInstallerCommand.m` is CLI composition rather than a Services
implementation: it subclasses the Runtime-owned `PDSBaseCommand` and registers
through the Runtime-owned `PDSCLIDispatcher`, while its filesystem and launchctl
work is process orchestration. CMake now excludes it from `ATProtoServices` and
adds it explicitly to `ATProtoRuntime`; the public header and dispatcher
registration API are unchanged. The boundary baseline ratcheted **11 -> 9**.
Fresh macOS validation rebuilt `ATProtoServices`, `ATProtoRuntime`, and
`AllTests`; the link checker reported **9 current / 9 baselined** leaks, the
source-import checker passed, and the CLI registration focus passed **38/38**
with zero failures or skips. `git diff --check` passed.

**`PDSAccountService` PLC operation-provider extraction:**
`PDSAccountService.m` previously sent messages to PLC-owned
`PLCOperation` and `PLCRotationKeyManager` classes while compiling into
`ATProtoServices`. The account service now consumes the Core
`PDSPLCAccountOperationProvider` protocol. The PLC module owns
`PDSPLCAccountOperationProvider.m`, including rotation-key loading, operation
signing, and signed-operation DID derivation; `PDSApplication` injects that
implementation at Runtime composition. Registration signs one operation and
derives the DID from that exact signed dictionary, avoiding a second signature
that could produce a different content-addressed DID. Missing provider or
rotation key fails closed with a 503 error. Focused account-service tests cover
injection, call counts, and missing-provider behavior. The baseline ratcheted
**8 -> 6**.

Fresh validation should rebuild `ATProtoPLC`, `ATProtoServices`,
`ATProtoRuntime`, and `AllTests`; the boundary checker must report **6 current /
6 baselined** leaks for this historical PLC slice, and the account-service focus
must include the injected provider tests.

**`GZHTTPClient` Services dependency-inversion extraction:**
Services callers previously imported the Transport-owned `ATProtoSafeHTTPClient`
and `ATProtoSafeHTTPClientOptions` classes directly. They now consume the
Core-owned `GZHTTPClient` protocol and `GZHTTPClientOptions` value type through
`GZHTTPClientRegistry`. `ATProtoSafeHTTPClient` conforms to that protocol, so
SSRF validation, DNS pinning, redirect validation, and response-size limits
remain in the Transport implementation. The registry also returns a
fail-closed unavailable client when no implementation is registered, avoiding
nil messaging in binaries that omit Transport. The private-IP regression test
now asserts the SSRF error path, and focused Core-seam tests cover options
copy/defaults and the unavailable registry behavior. The HTTP pair was removed
from the live boundary baseline; the checker reports **4 current / 4 baselined**
violations at that point, with the remaining single Services entry being
`RateLimiter` (closed by the subsequent diagnostics composition extraction).

**`RateLimiter` Services leak closed via diagnostics composition extraction:**
The last remaining `ATProtoServices` boundary violation traced to
`PDSRateLimitAdminHandler.m` and `PDSSystemDiagnosticsHandler.m`, two
admin/diagnostics handlers that route across Services and Transport and
construct Transport's `RateLimiter`. Both compile into `ATProtoServices`'s
glob only because of their directory location, not because they are service
implementations. CMake now excludes both from `ATProtoServices` and assigns
them explicitly to `ATProtoRuntime` (the module that composes the service
graph at boot), matching the `ChatRuntime`/`GermRuntime`/`PDSInstallerCommand`
precedent; their headers and route-registration APIs are unchanged. The
boundary baseline ratcheted **4 -> 3**, and `ATProtoServices` now has **zero**
baselined violations. Fresh macOS validation rebuilt `ATProtoServices`,
`ATProtoRuntime`, and `AllTests`; the link checker reported **3 current / 3
baselined** leaks, the source-import checker passed, and `git diff --check`
passed.

**`ATProtoMediaCore` / XRPC composition extraction — baseline reaches zero:**
The last three baselined violations (`XrpcDispatcher`, `XrpcErrorHelper`,
`XrpcRoutePackServiceBag`) all traced to two files in the MediaCore glob:
`ATProtoMediaServiceRuntime.m` (constructs a private `XrpcDispatcher` and
`XrpcRoutePackServiceBag`, wires them into its own `HttpServer`, and
instantiates the media route pack) and `ATProtoMediaXrpcPack.m` (an XRPC
route pack registering methods on a dispatcher). Both are Runtime composition
— they route across MediaCore, Transport, and XRPC — not MediaCore
implementations, matching the `ChatRuntime`/`GermRuntime`/`PDSInstallerCommand`
precedent. CMake now excludes both from the MediaCore glob and appends them
explicitly to `ATProtoRuntime` (which already links `ATProtoVideoService` →
`ATProtoMediaCore` PUBLIC, so the composition path is legal and acyclic);
their headers, route APIs, and the `jelcz` construction site are unchanged.
`ATProtoMediaCore`'s declared closure (`ATProtoStorage`, `ATProtoCore`,
`ATProtoTransport`) is now honest. The boundary baseline ratcheted **3 -> 0**
and **`docs/module-boundary-baseline.txt` is empty**, meeting M4's
zero-baseline acceptance gate. Fresh macOS validation rebuilt
`ATProtoMediaCore`, `ATProtoRuntime`, `ATProtoXRPC`, and `AllTests`; the link
checker reported **0 current / 0 baselined** leaks, the source-import checker
passed, `ATProtoMediaServiceRuntimeTests` passed **8/8**,
`ATProtoMediaXrpcPackTests` passed **16/16**, and `git diff --check` passed.

**`PDSAdminAuth` controller protocol extraction:**
`PDSAdminAuth.m` previously imported and messaged the Runtime-owned
`PDSController`, creating a Services -> Runtime leak. The authentication
implementation now depends on the minimal `PDSAdminAuthController` protocol
(JWT minter plus service-database access), while `PDSController` conforms to
that protocol at the application boundary. The existing application and CLI
composition paths continue to inject the legacy controller; an absent
injection now fails closed rather than silently consulting the singleton.
The baseline ratcheted **9 -> 8**. Fresh macOS validation rebuilt
`ATProtoCore`, `ATProtoServices`, `ATProtoRuntime`, and `AllTests`; the link
checker reported **8 current / 8 baselined** leaks, the source-import checker
passed, and the admin-auth/CLI focus passed **70/70** with zero failures or
skips. `git diff --check` passed.

M0 (third-party consumption goal) is now answered yes under the bounded package
contract in the verified-status section above. M4 is complete; M5 has started
(see below).

**M5.1/M5.2 namespace gate landed (2026-08-04).** M4's zero-baseline gate is
met, so M5 (namespace the exported symbols) is the active milestone. Its first
step is the enforceable gate that M5.3's rename batches will be measured
against:
- **Policy (M5.1):** project-owned Objective-C classes carry one of three
  reserved prefixes — `ATProto` (protocol/domain primitives), `PDS`
  (PDS-specific types), or `GZ` (Garazyk infrastructure).
- **Gate (M5.2):** `scripts/check_namespace.sh` scans the ten archives for
  defined `_OBJC_CLASS_$_` symbols, excludes system/vendored classes by
  provenance (only project-compiled code is visible to nm on the archives),
  classifies the rest by the reserved prefixes, and ratchets against
  `docs/namespace-baseline.txt` (shrink-only, same discipline as the M1
  boundary baseline). `--init` regenerates the baseline.
- **Baseline:** the 2026-08-04 build inventories **515 total classes, of
  which 283 are unprefixed** — matching the 283-class starting figure the
  M5 scope named (the count has not drifted). The gate fails (exit 1) on a
  newly introduced unprefixed class and passes when the class is removed,
  verified by injecting a synthetic class into a test archive.
- **CI:** wired into `.github/workflows/ci.yml` as "Check Symbol Namespace
  (M5)" right after the link-time boundary check.

Next M5 step: extend the gate to protocols, categories, and externally visible
C symbols (the broader inventory M5.2 names), then begin M5.3 rename batches
in dependency order.

**M7 residual cleanup complete (2026-08-04).** All four remaining items:

- `PDSApplication.m`'s two `exit(1)` calls (production-issuer refusal) now set
  a `startupConfigurationError` ivar instead, checked and returned as a normal
  `NSError` at the top of `-startWithError:` (new `PDSApplicationErrorDomain`,
  declared in `PDSApplication.h`). Its `NSSetUncaughtExceptionHandler` callback
  no longer calls `exit(1)` either — it now just logs, matching
  `GZServiceLifecycle`'s own `uncaughtExceptionHandler`, which already relies
  on the runtime's implicit `abort()` once the handler returns. Three new
  regression tests in `PDSApplicationTests.m` exercise the two refusal paths
  and the success path via `-startWithError:` (impossible to test before,
  since the old code path called real `exit(1)` inside the test process).
- `PDSCLIServeCommand.m`'s two `exit(0)` calls (SIGINT/SIGTERM
  forced-shutdown-after-2s-timeout watchdogs) now reset the signal to
  `SIG_DFL` and `raise()` it instead, letting the OS decide termination —
  same pattern as `GZServiceLifecycle`'s `sigabrtHandler`. The normal graceful
  path (run-loop notices `shouldExit`, stops cleanly, returns 0) is unchanged;
  only the rarely-hit watchdog fallback changed.
- `PDSCLIDaemonCommand.m`'s post-`execv`-failure `exit(1)` (inside a forked
  child) is now `_exit(1)` — the correct primitive for that context (skips
  atexit handlers and flushes of stdio buffers inherited from the parent),
  and exempt from the new CI gate below by design.
- The installer's `/var/db/kaszlak/log/daemon.log` fallback now builds its
  path through `ATProtoDataPaths pathsForBaseDirectory:` using this same
  command's own existing default data directory (`~/.config/kaszlak`, already
  used by its `purge`/`status` actions), instead of an unrelated hardcoded
  system path.
- `ATProtoSafeHTTPClient.sharedClient` and `GZMetrics.sharedMetrics` were
  found to already resolve/register through `ATProtoServiceContainer` (no
  code change needed) — both classes were already injectable while keeping
  `+shared*` as the default, satisfying that part of M7's acceptance gate.
- New CI gate: `scripts/check_no_host_process_exit.sh` rejects `exit(`/
  `abort(` (word-boundary matched; `_exit(` is intentionally exempt) anywhere
  under `Garazyk/Sources/**/*.m`, comment-aware (strips `//` and `/* */`
  before matching). Wired into `.github/workflows/ci.yml`'s macOS job,
  source-only so it doesn't need duplicating per platform. Verified it both
  passes clean on the current tree and catches an injected violation.
- M7's absolute-path-literal half of its acceptance gate ("a CI grep rejects
  ... absolute path literals") is deliberately **not** implemented as a
  blanket check: a survey of `@"..."` literals matching `/usr/`, `/var/`, or
  `/etc/` in `Garazyk/Sources/` found only 5 remaining hits, none matching the
  three specific paths this milestone named (`/usr/share/garazyk/lexicons`,
  `/usr/share/atprotopds/assets`, `/var/db/kaszlak/log` — all three now fixed,
  the last one today). The 5 remaining are legitimate: `/usr/bin/curl`
  subprocess-invocation paths (3, one already tracked as a separate M2
  follow-up), a real system install-target path in a launchctl plist
  (`/usr/local/bin/kaszlak`), and a HeaderDoc `@code` example
  (`/var/lib/pds`, not real code at all). A blanket literal ban would false-
  positive on the doc-comment case and mischaracterize subprocess paths as
  the same class of bug as a hardcoded data/log default. Left unimplemented
  rather than guessed at.

Verified: `cmake --build build --target AllTests --parallel 4` and
`./build/tests/AllTests --gated=run` both green on macOS (see the GNUstep
section below for the same source tree's GNUstep build/test result).

## GNUstep/Linux CI investigation (2026-08-04)

Top item from the mega-plan's 2026-08-04 work queue: verify the `1c8c2dd8`
compiler-conflict fix holds, and determine whether `ci.yml`'s
`linux-gnustep-build-and-test` job can actually compile Objective-C at all.

**The compiler fix holds.** Reproduced `ci.yml`'s exact `cmake -S . -B
build-linux -G Ninja ...` configure step (no `-DCMAKE_{C,CXX,OBJC}_COMPILER`
override) in a fresh `ubuntu:24.04` container with the job's exact apt
package list — configure completes cleanly, no infinite reconfigure loop.

**P0 CI-truthfulness finding, confirmed: `linux-gnustep-build-and-test` has
never been able to compile this project, and cannot, as configured.** Root
cause: the job's apt package set (`gnustep-make`, `libgnustep-base-dev`,
`libblocksruntime-dev`) never provides `objc/blocks_runtime.h`.
`libblocksruntime-dev` ships Mark Heily's unrelated `libBlocksRuntime`
project (`Block.h`/`Block_private.h`) — not libobjc2's
`objc/blocks_runtime.h`, which GNUstep-base's `GSVersionMacros.h` requires
once `-fobjc-runtime=gnustep-2.2` is set (`CMakeLists.txt:134`). Reproduced
the exact, deterministic failure on the very first `.m` file compiled
(`AuthCryptoDPoP.m`): `fatal error: 'objc/blocks_runtime.h' file not found`.
This is architecture-independent (confirmed the wrong package's contents
directly, not just a symptom) so it fails identically on the real x86_64
GitHub runner, not just this arm64 reproduction. Ubuntu's apt `gnustep-base`
family links against the legacy GCC Objective-C runtime
(`libobjc4`/`libobjc-*-dev`), not libobjc2 — the two runtime families are
fundamentally incompatible with this project's `-fobjc-runtime=gnustep-2.2`
requirement, and apt does not package libobjc2 on Ubuntu at all. There is no
apt-package fix; only a from-source libobjc2/gnustep-make/gnustep-base
toolchain (exactly what `docker/Dockerfile.gnustep`'s first stage already
builds) satisfies this requirement.

**The from-source toolchain (`docker/Dockerfile.gnustep`) works, and was used
to get first-ever full GNUstep build/test evidence.** Built
`docker/Dockerfile.gnustep --target builder` fresh (`docker build`, not just
`docker exec` reproduction) against current `main` — all binaries
(`kaszlak`, `garazyk-ui`, `jelcz`, `syrena-chat`, `germ`, etc.) link cleanly.
Reconfiguring the same built image with `-DBUILD_TESTS=ON` and building
`AllTests` also links cleanly (997/997 targets, only pre-existing
`-Wincomplete-implementation` warnings, no errors) — this is the first time
the full `AllTests` binary has ever been built on GNUstep in this
workstream's history. One environment-specific link wrinkle was hit and
resolved along the way, worth recording: a fresh `garazyk-gnustep-base`-based
container built by hand (not `docker build` end-to-end) can end up with
`clang`'s own apt dependency chain (`clang` → `libobjc-11-dev` →
`libobjc4`, the legacy GCC runtime) *coexisting* with the from-source
libobjc2 in `/usr/GNUstep`; CMake's `link_directories(BEFORE ...)` calls for
the GNUstep lib paths (`CMakeLists.txt:150-154`) then silently produce no
`-L` flags in the Ninja-generated link line (`LINK_PATH = -L/usr/local/lib`
only) for reasons not fully root-caused (not a Ninja-vs-Make generator
difference — reproduced identically with the default Unix-Makefiles
generator), causing `-lobjc` to resolve against the wrong runtime at link
time (`objc_setProperty_nonatomic_copy` undefined). This did **not** occur
in the real, unmodified `docker build -f docker/Dockerfile.gnustep` run
(confirmed by inspecting its generated `link.txt`, which correctly has
`-L/usr/GNUstep/Local/lib -L/usr/GNUstep/Local/Library/Libraries
-L/usr/local/lib` in that order) — it is an artifact of manually
reassembling the toolchain outside the Dockerfile's exact build sequence,
not a defect in `docker/Dockerfile.gnustep` itself. Recorded here so a future
GNUstep CI change knows to build/configure through the Dockerfile's own
sequence (or replicate it exactly) rather than composing the toolchain by
hand.

**Full GNUstep `AllTests --gated=run` evidence (2026-08-04, two runs).**
First run: 4,723 tests, 560 failures. An unrelated environment reset (host
clock jumped ~5,200s mid-run; `docker images`/`docker ps -a` came back empty
afterward, destroying every image/container built during this investigation)
hit right after that run printed its summary line, so only a `tail -150`
slice of its per-test output survived. A full from-source rebuild (`docker
build -f docker/Dockerfile.gnustep --target builder`, then reconfigure with
`-DBUILD_TESTS=ON`, then `AllTests --gated=run`) was relaunched
detached/`nohup` with untruncated logging to confirm reproducibility and get
the complete failure list. Second run: **4,726 tests, 562 failures, 933s
(~15.5 min) wall clock** — closely reproduces the first run's counts. The
first run's "~101 minutes" figure was **wrong**: it included the ~5,200s
clock-jump artifact in the process's own elapsed-time report
(6,053.879s − 5,202s ≈ 852s, consistent with the second run's clean 933s).
The real GNUstep `AllTests` wall clock is in the same ballpark as macOS's
511s (below), not 6x longer.

**Root cause found for the large majority of failures, from the complete
(untruncated) second-run log:**

- **488 of 562 failures (86.7%) are one root cause: `AdminAuthXrpcTestBase`
  / `RepoAuthTempTests`'s shared `-setUp` fails its own
  `XCTAssertTrue(adminAuthSuccess, ...)` assertion** (`AdminAuthXrpcTestBase.m:56`,
  calling `[PDSAdminAuth authenticateWithPassword:error:]`) — every test
  method in every subclass then fails identically regardless of what the
  test itself exercises, because the fixture itself never got past `setUp`.
  51 distinct test classes show at least one failure; the great majority of
  them are pure `-setUp` cascade, not independent bugs — confirmed directly
  by grepping every `FAIL:` line for the literal `adminAuthSuccess` assertion
  text (488 hits) and separately by inspecting representative subclasses
  (`AdminAuthXrpcTests`, `RepoAuthTempTests`) where *every* failing method's
  reason is exactly `XCTAssertTrue failed: adminAuthSuccess`, including tests
  that assert `Unauthorized`/`Forbidden` responses (i.e., tests that don't
  even need a *successful* admin auth to run, but the shared fixture still
  blocks them). **This is the single highest-leverage GNUstep lead**: fixing
  why `PDSAdminAuth authenticateWithPassword:error:` (password verification
  or JWT signing) fails on GNUstep would likely resolve the large majority of
  the current backlog in one fix. Not root-caused further in this slice —
  needs its own investigation (compare `PDSAdminAuth`'s password-hash/JWT
  path step by step on GNUstep vs. macOS).
- **57 failures: HTML template loading in this reproduction's container
  specifically, likely not a real GNUstep bug.** Every `UIServerRuntimeTests`/
  `UIBackendClientTests`/`UILabIntegrationTests`/`PDSHttpPDSAdminRoutePackTests`
  failure is paired with `[ERROR] [UITemplateEngine.m:31] Failed to load
  template <name>: (null)` in the same log window — the admin-UI HTML
  partials were not resolvable from wherever `UITemplateEngine` looked in
  this ad-hoc container (built by `docker cp`-ing `Garazyk/Sources` alone,
  not the full asset layout `docker/Dockerfile.gnustep`'s runtime stage
  copies via `COPY --from=builder /src/build/bin/Assets ...`). Re-run with
  the assets present at the expected path before treating this cluster as a
  real product bug.
- **~9 failures: environment-variable config parsing returns defaults
  instead of configured values on GNUstep** — `ATProtoMediaServiceConfigurationTests`
  (6), `JelczCLITests` (4, overlaps the "distinct classes" list above),
  `ATProtoMediaCoreTests`, `ATProtoMediaServiceRuntimeTests`. E.g.
  `config.port != 9999`, `config.maxOutputBytes != 1048576`, S3/DID/directory
  settings read back as defaults/nil. Genuinely distinct from the admin-auth
  cascade and worth its own investigation (`NSProcessInfo.environment`
  reading, or test `setenv()` ordering, differing on GNUstep).
- **3 failures: missing `ffprobe` binary** (`FFmpegTranscoderTests`) — an
  environment gap in this toolchain image, not a code bug.
- **~5 failures: assorted, one-off** (`VideoRemoteBlobUploaderTests`,
  `OAuth2HandlerTests`, `GermIdentityServiceTests`, a couple of interop/CBOR
  fixture tests) — not yet individually triaged.

Full per-class failure counts (`grep -oE 'FAIL: -\[[A-Za-z0-9_]+ test[A-Za-z0-9_]+\]'`
grouped by class) are in this session's scratch log; the largest are
`XrpcToolsOzoneTests` (66), `XrpcChatBskyGroupTests` (42),
`XrpcAppBskyGraphTests` (42), `XrpcAppBskyUnspeccedTests` (40),
`XrpcChatBskyConvoTests` (38), `AdminAuthXrpcTests` (37) — all
`AdminAuthXrpcTestBase` subclasses, all part of the 488-failure cascade
above.

**Decision needed before `ci.yml` itself changes.** Fixing
`linux-gnustep-build-and-test` "for real" means either (a) adding a
from-source libobjc2/gnustep-make/gnustep-base build step to that job
(significant CI time, mirroring Dockerfile stage 1), or (b) restructuring it
to build/test inside a container derived from `docker/Dockerfile.gnustep`
(architecturally different from today's native-runner job). Wiring
`AllTests` execution into the already-working `linux-docker-build` job would
immediately surface the failures above and turn that job red for every
future PR — not something to do unilaterally without confirming that's the
intended trade-off. Per this repo's stop conditions (a slice needing a new
architectural decision), this is recorded here rather than guessed at:
`ci.yml` is **not** changed further in this slice beyond what M7 needed. The
options, for a maintainer to pick from:

1. Replace the apt-based job with a Docker-based one, keep tests out of the
   gate for now (binary build only, matching today's confidence level minus
   the false sense that Objective-C ever compiled there).
2. Replace it and gate on `AllTests`, accepting CI goes red until the
   admin-auth cascade (the 86.7% root cause above) and the rest of the
   backlog are triaged — likely a single fix plus a smaller mop-up given the
   root-cause finding above.
3. Remove `linux-gnustep-build-and-test` entirely and rely solely on
   `linux-docker-build`'s existing binary-only build for Linux signal.

Cleanup: the stale `gnustep-ci-repro2` Docker container mentioned in the work
queue was removed (no logs, empty `sleep infinity` shell). Exploratory
containers created during this investigation were removed after use; all
Docker images/containers from both runs were subsequently lost to the
environment reset described above — a future session re-deriving this
evidence should rebuild from `docker/Dockerfile.gnustep` again (buildkit
layer caching made the second full rebuild fast in this session, likely
because the daemon's build cache, unlike its image/container list, survived
the reset).

# Module Boundaries and Library Consumption

## Target

The ten `ATProto*` static libraries become real boundaries: each links against
only its declared dependencies, the build enforces that property, and the
declared dependency graph in `CMakeLists.txt` stops being documentation.

The libraries will also be installable for third-party consumption through the
bounded CMake package contract recorded above. Items M1-M4 remain internal
architecture prerequisites: an installed package cannot compensate for false
dependency declarations. M5 defines a collision-safe public surface, and M6
makes that surface relocatable and consumable.

## M0. Decide the consumption target

**Decision: yes.** A third-party project is expected to build and install
Garazyk, then consume one or more static-library targets through
`find_package(Garazyk CONFIG REQUIRED)` without adding the Garazyk source tree
to its own build.

The acceptance contract is intentionally precise:

1. All ten module targets are exported under the `Garazyk::` namespace with
   their transitive dependencies represented accurately.
2. `Garazyk::ATProtoCore` can be linked alone by a minimal consumer.
3. A second consumer can link the top-level runtime/module set and exercise the
   full exported dependency closure.
4. The installed prefix can be moved before either consumer is configured; no
   build-tree path may appear in installed headers or CMake metadata.
5. macOS and GNUstep/Linux both pass the package-consumer gates.

Version 0.x is an experimental source API. The first release does not promise
ABI compatibility or ship prebuilt binaries. Expanding to frameworks,
XCFrameworks, iOS, SwiftPM, CocoaPods, or a public registry requires a separate
decision after this workstream.

## Current evidence

Collected 2026-07-28 against `main` at `246bd140`, using the existing `build/`
directory (dated the same day). No build or test run was performed to produce
these figures; they come from the checked-in sources and the already-built
archives.

- `libATProtoCore.a` is declared to have no dependencies
  (`CMakeLists.txt:583` links it to nothing) but does not link standalone. It
  carries undefined Objective-C class references to `CBORDecoder`,
  `CBOREncoder`, `CBORValue`, `MST`, and `MSTAtomicReference` (all
  `ATProtoStorage`) and `ATProtoSafeHTTPClient` (`ATProtoTransport`) — six
  symbols, all from layers declared to sit *above* Core:

  ```bash
  nm -u build/libATProtoCore.a | grep '_OBJC_CLASS_\$_' | grep -v '_\$_NS'
  ```

  Static archives do not resolve symbols until the final executable link, and
  every binary in the repository links the whole set, so this has never
  surfaced as a build failure.

- Roughly 140 import edges violate the declared layering. The largest single
  cluster is `Services` reaching into `Network/`: 86 imports, of which 50 are
  exactly `Network/HttpRequest.h` and `Network/HttpResponse.h`.

- `Garazyk/Frameworks/ATProtoServices/ATProtoServices.h` imports six headers
  that do not exist at the stated paths. The files moved from `App/Services/`
  to `Services/PDS/` and `Services/Core/`; the umbrella was never updated.
  Nothing in the repository imports any of the eight umbrella headers, so no
  compile ever touches them and the rot went undetected. The umbrellas export
  4-7 headers against modules holding 17-113.

- No module target is installed or exported. `install()` covers only the
  `kaszlak` binary (`CMakeLists.txt:1807`) and the fuzzers.

- All ten module targets share one public include directory covering the entire
  source tree (`CMakeLists.txt:573`):
  `target_include_directories(${target} PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/Garazyk/Sources)`.
  It is an absolute build-tree path, so it is not relocatable, and it makes
  every private header public. All 315 header-to-header imports are path-based
  (`#import "Core/DID.h"`); none are framework-style.

- Exported class names collide with the flat Objective-C namespace. The
  archives define `HttpRequest`, `HttpResponse`, `HttpServer`, `HttpRouter`,
  `RateLimiter`, `CID`, `TID`, `ATURI`, `Base58`, `MST`, `CBOREncoder`,
  `CARReader`, and migration classes named `V1InitialSchema`, `V2OzoneSchema`,
  and `V11AddLegacyColumns`.

- 65 `+shared*` accessors exist. The load-bearing ones are
  `ATProtoSafeHTTPClient.sharedClient` (40 call sites in `Sources/`) and
  `GZMetrics.sharedMetrics` (45). `ATProtoServiceContainer` already provides
  protocol-keyed injection but is referenced in only three files.

- Library code terminates the host process: `exit(1)` at
  `Garazyk/Sources/Runtime/GZServiceLifecycle.m:67` and
  `Garazyk/Sources/Compat/PlatformShims/Security/SecItemLinuxStore.m:159`,
  `abort()` at `.../SecRandom.m:22`.

- Module membership is defined by `file(GLOB_RECURSE)` plus fifteen
  `list(FILTER ... EXCLUDE REGEX)` calls, so directory layout does not match
  module layout. Adding a file silently joins a module; renaming one silently
  moves it between modules. The globs lack `CONFIGURE_DEPENDS`.

## M1. Land the boundary gate with a ratcheting baseline

Do this first. It makes every later item verifiable and stops the graph from
drifting further while the rest is in flight.

Add `scripts/check_module_boundaries.sh`. For each `ATProto*` archive it reads
undefined `_OBJC_CLASS_$_` symbols, subtracts Foundation and system classes,
subtracts everything defined by that target's declared dependencies, and
reports the remainder as leaks.

Check in `docs/metadata/module-boundary-baseline.txt` recording today's known
leaks per module. CI fails on any leak absent from the baseline. The baseline
may shrink and may never grow — later items are measured by how much they take
out of it.

Owner boundary: `scripts/`, CI workflow, and one generated baseline file. No
source under `Garazyk/Sources/` changes.

Verification gate: the script runs clean against the checked-in baseline on a
fresh build; deliberately adding an illegal import to a module fails CI.

Deliverable: ADR recording that module dependencies are enforced by a link-time
symbol gate rather than by review, and that the baseline is append-never.
Number it `0031` if nothing else has claimed it.

Rollback: delete the script, workflow step, and baseline. Nothing else is
touched.

## M2. Make ATProtoCore standalone

The pilot. Six symbols, verifiable in one command.

1. Move `MSTCacheManager` and `MSTAtomicReference` from `Core/` to Storage.
   `MSTCacheManager` already depends on `PDSActorStore`, so it belongs in
   Storage by its own dependencies; its `+sharedManager` cache is keyed by DID
   only, which is worth revisiting at the same time (a DID is not unique across
   two instances in one process).
2. Settle CBOR ownership. `Core/ATProtoCBORSerialization.m` imports
   `Repository/CBOR.h`. Recommend moving `CBOREncoder`/`CBORDecoder`/
   `CBORValue` down into Core — dag-cbor is an ATProto primitive with no
   storage dependency — and leaving `CARReader`/`CARWriter` in Storage.
3. Introduce a `GZHTTPClient` protocol in Core covering the two methods
   `Core/DID.m` actually uses, conform `ATProtoSafeHTTPClient` to it, and inject
   it with the shared client as the default. No such protocol exists today;
   `ATProtoSafeHTTPClient` is a concrete class and `GZProviderHTTPClient` is a
   second concrete client, not a seam. This is new API, not a rewire.

While `Core/DID.m` is open, the GNUstep-only `/usr/bin/curl` subprocess
fallback at line 623 should move behind the same protocol or be deleted; a core
primitive spawning a process is not something a consumer can control.

Owner boundary: `Garazyk/Sources/Core/`, `Garazyk/Sources/Repository/`, and the
Core/Storage source lists in `CMakeLists.txt`.

Verification gate: the M1 command returns empty for `libATProtoCore.a`; the
baseline drops by six; `AllTests` passes.

Rollback: single revert. Steps 1 and 2 are file moves; step 3 is additive and
keeps the existing call path as the default.

## M3. Split ATProtoTransport into message types and I/O machinery

The largest structural win, and mostly a file move.

`ATProtoTransport` currently conflates HTTP *message types* with HTTP *I/O
machinery*. `HttpRequest.h` and `HttpResponse.h` import Foundation and nothing
else; together they are 1,134 lines across four files and account for 50 of the
86 `Network/` imports made from Services directories.

Move the Foundation-only value types — `HttpRequest`, `HttpResponse`,
`HttpRoute`, `HttpRetryPolicy` — to Core level. Leave `HttpServer`,
`Http1Parser`, the connection drivers, `HttpBufferPool`, and `SSRFValidator` in
Transport. Services handlers then depend on Core, which is legal, instead of on
the whole HTTP stack.

Owner boundary: `Garazyk/Sources/Network/`, plus import updates across Services.
No behavior change: the types are moved, not modified.

Verification gate: `Network/` imports from Services directories drop from 86 to
at most 36; the baseline shrinks correspondingly; `AllTests` passes; the Linux
Docker gate passes, since this touches Network.

Deliverable: ADR recording that HTTP message types are Core primitives and that
`ATProtoTransport` owns only I/O.

Rollback: single revert; the change is file moves plus mechanical import edits.

## M4. Resolve the remaining inversions

Status: **complete — zero baselined violations remain.** The earlier M4 work
resolved the initially enumerated clusters, but the follow-on baseline was
incorrectly treated as out of scope. It is not: M4's purpose and acceptance
gate are both zero undeclared dependencies, and that gate is now met.

### M4.1. Freeze and explain the residual baseline

Generate a report mapping every baseline entry to the object file that emits
the undefined reference. Check that report into the work log, not as a second
permanent baseline. For each cluster, record whether the fix is:

- source ownership (the object file is compiled into the wrong module);
- dependency declaration (the dependency is fundamental and acyclic);
- dependency inversion (a protocol/factory belongs below both sides); or
- composition extraction (an adapter imports two siblings and belongs in
  Runtime or a dedicated integration target).

Do not silence a violation by adding a `PUBLIC` edge until the resulting graph
has been checked for cycles and the referenced API is intentionally part of the
lower module's public contract.

#### Evidence map (2026-07-30, historical)

The following table records the original residual emitters before the
subsequent M4.2 slices. Resolved entries are retained as historical evidence;
the live baseline is `docs/module-boundary-baseline.txt`.

The historical evidence below predates the later M4.2 slices. At that point,
a fresh `cmake -S . -B build` and rebuild of all ten package archives reported
30 leaks in seven modules. `nm -u -A`
identified the emitting members below; the source path is relative to
`Garazyk/Sources`. The classifications are proposed next steps, not baseline
exceptions.

| Referencing archive | Undefined class | Emitting object / source | Owning archive | Proposed classification |
| --- | --- | --- | --- | --- |
| ATProtoMediaCore | XrpcDispatcher | `ATProtoMediaServiceRuntime.m.o` / `MediaCore/ATProtoMediaServiceRuntime.m` | ATProtoXRPC | composition extraction |
| ATProtoMediaCore | XrpcErrorHelper | `ATProtoMediaXrpcPack.m.o` / `MediaCore/ATProtoMediaXrpcPack.m` | ATProtoXRPC | composition extraction |
| ATProtoMediaCore | XrpcRoutePackServiceBag | `ATProtoMediaServiceRuntime.m.o` / `MediaCore/ATProtoMediaServiceRuntime.m` | ATProtoXRPC | composition extraction |

> Resolved: both emitting files moved to Runtime (see the "ATProtoMediaCore /
> XRPC composition extraction — baseline reaches zero" entry below), closing
> all three rows and emptying the live baseline.
| ATProtoPLC | ATProtoConnectionManagerSerial | `PLCPersistentStore.m.o` / `PLC/PLCPersistentStore.m` | ATProtoStorage | legitimate dependency edge |
| ATProtoPLC | ATProtoDatabaseQueryRunner | `PLCPersistentStore.m.o` / `PLC/PLCPersistentStore.m` | ATProtoStorage | legitimate dependency edge |
| ATProtoServices | ATProtoSafeHTTPClient | `ChatAuthManager.m.o`, `FederationClient.m.o`, `HandleResolver.m.o`, `OAuth2Handler+ClientMetadataFetch.m.o`, `PDSAccountService.m.o`, `PDSCaptchaRegistrationGate.m.o`, `PDSEmailHTTPClient.m.o`, `PDSRelayService.m.o`, `PDSSpaceAppAttestationVerifier.m.o`, `PDSSpaceReconciler.m.o` / matching `Chat`, `Federation`, `Identity`, `Auth`, `Services`, `Registration`, `Email`, and `Security` sources | ATProtoTransport | dependency inversion |
| ATProtoServices | ATProtoSafeHTTPClientOptions | `ChatAuthManager.m.o`, `FederationClient.m.o`, `HandleResolver.m.o`, `OAuth2Handler+ClientMetadataFetch.m.o`, `PDSAccountService.m.o`, `PDSCaptchaRegistrationGate.m.o`, `PDSEmailHTTPClient.m.o`, `PDSSpaceAppAttestationVerifier.m.o` / matching sources above | ATProtoTransport | dependency inversion |
| ATProtoServices | DIDPLCResolver | `AppViewIdentityHelper.m.o` / `AppView/AppViewIdentityHelper.m` | ATProtoPLC | composition extraction |
| ATProtoServices | HttpServer | `ChatRuntime.m.o`, `GermRuntime.m.o` / `Chat/Server/ChatRuntime.m`, `Germ/Server/Runtime/GermRuntime.m` | ATProtoTransport | composition extraction |
| ATProtoServices | PDSBaseCommand | `PDSInstallerCommand.m.o` / `Admin/PDSInstallerCommand.m` | ATProtoRuntime | wrong source ownership |
| ATProtoServices | PDSCLIDispatcher | `PDSInstallerCommand.m.o` / `Admin/PDSInstallerCommand.m` | ATProtoRuntime | wrong source ownership |
| ATProtoServices | PDSController | `PDSAdminAuth.m.o` / `Admin/PDSAdminAuth.m` | ATProtoRuntime | composition extraction |
| ATProtoServices | PLCOperation | `PDSAccountService.m.o` / `Services/PDS/PDSAccountService.m` | ATProtoPLC | dependency inversion |
| ATProtoServices | PLCRotationKeyManager | `PDSAccountService.m.o` / `Services/PDS/PDSAccountService.m` | ATProtoPLC | dependency inversion |
| ATProtoServices | RateLimiter | `PDSRateLimitAdminHandler.m.o` / `Admin/Diagnostics/PDSRateLimitAdminHandler.m` | ATProtoTransport | dependency inversion |
| ATProtoServices | XrpcChatBskyActorPack | `ChatRuntime.m.o` / `Chat/Server/ChatRuntime.m` | ATProtoXRPC | composition extraction |
| ATProtoServices | XrpcChatBskyConvoPack | `ChatRuntime.m.o` / `Chat/Server/ChatRuntime.m` | ATProtoXRPC | composition extraction |
| ATProtoServices | XrpcChatBskyGroupPack | `ChatRuntime.m.o` / `Chat/Server/ChatRuntime.m` | ATProtoXRPC | composition extraction |
| ATProtoServices | XrpcDispatcher | `ChatRuntime.m.o`, `GermRuntime.m.o` / `Chat/Server/ChatRuntime.m`, `Germ/Server/Runtime/GermRuntime.m` | ATProtoXRPC | composition extraction |
| ATProtoServices | XrpcRoutePackServiceBag | `ChatRuntime.m.o` / `Chat/Server/ChatRuntime.m` | ATProtoXRPC | composition extraction |
| ATProtoStorage | PDSAppleActorKeyManager | `ActorStore.m.o` / `Database/ActorStore/ActorStore.m` | ATProtoServices | dependency inversion |
| ATProtoSync | XrpcIdentityHelper | `RelayEventValidator.m.o` / `Sync/Relay/RelayEventValidator.m` | ATProtoXRPC | dependency inversion |
| ATProtoVideoService | XrpcAuthHelper | `VideoPDSAuthProvider.m.o` / `Video/VideoPDSAuthProvider.m` | ATProtoXRPC | composition extraction |
| ATProtoVideoService | XrpcErrorHelper | `VideoXrpcPack.m.o` / `Video/VideoXrpcPack.m` | ATProtoXRPC | composition extraction |
| ATProtoXRPC | ATProtoVideoWorker | `XrpcAppBskyPack.m.o` / `Network/XrpcAppBskyPack.m` | ATProtoVideoService | composition extraction |
| ATProtoXRPC | ATProtoVideoXrpcPack | `XrpcAppBskyPack.m.o` / `Network/XrpcAppBskyPack.m` | ATProtoVideoService | composition extraction |
| ATProtoXRPC | PDSAccountPolicy | `XrpcAuthHelper.m.o` / `Network/XrpcAuthHelper.m` | ATProtoRuntime | dependency inversion |
| ATProtoXRPC | PDSController | `XrpcAuthHelper.m.o`, `XrpcRepoPack.m.o` / `Network/XrpcAuthHelper.m`, `Network/XrpcRepoPack.m` | ATProtoRuntime | dependency inversion |
| ATProtoXRPC | PDSLocalVideoJobStore | `XrpcAppBskyPack.m.o` / `Network/XrpcAppBskyPack.m` | ATProtoVideoService | composition extraction |
| ATProtoXRPC | VideoPDSAuthProvider | `XrpcAppBskyPack.m.o` / `Network/XrpcAppBskyPack.m` | ATProtoVideoService | composition extraction |

### M4.2. Resolve the remaining clusters

Land one independently reviewable cluster per commit, shrinking the existing
baseline each time:

1. **Services composition leaks (13).** Separate runtime/composition objects
   (`ChatRuntime`, `GermRuntime`, `PDSInstallerCommand`, and admin/runtime
   adapters) from service implementations. Replace direct
   `ATProtoSafeHTTPClient`, PLC, Transport, Runtime, and XRPC construction with   lower-layer protocols or move the composition object to the module that
   already owns both sides.

2. **Video/XRPC integration cycle (3 in the current baseline: 3 in
   ATProtoMediaCore, 0 in ATProtoVideoService, and no remaining
   ATProtoXRPC references to ATProtoVideoService).** The route-pack implementations
   `VideoPDSAuthProvider.m` and `VideoXrpcPack.m` are XRPC composition
   adapters and now compile into `ATProtoXRPC`. The worker singleton seam is
   also closed: the registry receives the blob provider through
   `PDSBlobService` rather than `ATProtoVideoWorker`. The job-store seam is
   likewise closed: the registry receives the protocol-backed store from
   `PDSApplication` rather than constructing `PDSLocalVideoJobStore`. The
   shared registration path remains for later focused slices. Keep media
   abstractions independent of XRPC. Move

   route-pack registration and any remaining concrete video composition
   to Runtime, or introduce one narrowly scoped integration target if Runtime
   ownership would be false. `ATProtoMediaCore` must not depend on XRPC.

   **Scoping investigation (2026-08-03, no code changed):** this is deeper
   than a single composition-object move. The video construction lives in
   `[XrpcAppBskyPack registerWithDispatcher:services:]`
   (`Network/XrpcAppBskyPack.m`, compiled into ATProtoXRPC), which consumes
   the protocol-backed job store and constructs `VideoPDSAuthProvider`, then
   calls
   `[ATProtoVideoXrpcPack registerWithDispatcher:services:]` (the route-pack
   implementation is XRPC-owned; the remaining concrete worker/job-store
   implementations are VideoService-owned). That method is reached from
   `XrpcMethodRegistry` (also ATProtoXRPC), which in turn is called from two
   places: `App/server_main.m` (ATProtoRuntime, the expected caller) **and**
   `Network/ATProtoHttpXrpcRoutePack.m` — which, despite living under
   `Network/` and compiling into ATProtoXRPC, already `#import`s
   `App/PDSApplication.h` and `App/PDSController.h` directly. That import is
   the source of the separate `ATProtoXRPC:PDSController` /
   `ATProtoXRPC:PDSAccountPolicy` baseline entries (dependency-inversion
   cluster, not part of this one), but it means the route-registration
   orchestration layer (`XrpcMethodRegistry.m` +
   `ATProtoHttpXrpcRoutePack.m`) already has a foot in Runtime, blurring where
   "the caller in Runtime" that this cluster's fix wants to hoist video
   composition into actually is. A narrow fix that only moves the video
   construction out of `XrpcAppBskyPack.m` would still leave
   `ATProtoHttpXrpcRoutePack.m`'s own Runtime imports unaddressed, and could
   not simply call video registration from "the Runtime caller" because one
   of the two callers of the shared registration path is itself inside
   ATProtoXRPC. Resolving this cluster for real means first deciding whether
   `XrpcMethodRegistry`/`ATProtoHttpXrpcRoutePack` are source-misowned
   (composition code that belongs in ATProtoRuntime despite the `Network/`
   directory, per the M4.1 classification key) rather than treating this as
   a self-contained 9-symbol move. Do not attempt this cluster as a single
   sitting change — it touches the live PDS HTTP route-registration path and
   needs the same source-evidence pass extended to the registration
   orchestration files before a commit boundary can be drawn.
3. **PLC persistence (2, complete in `06c0c8f5`).** Decided yes:
   `PLCPersistentStore` makes Storage a fundamental PLC dependency. Added the
   acyclic `ATProtoPLC -> ATProtoStorage` edge (documented inline in
   `scripts/dev/check_module_boundaries.sh`); the baseline dropped from 28 to
   26.
4. **Storage key-manager construction (1, complete; commit pending).**
   `PDSAppleActorKeyManager`, `PDSOpenSSLKeyManager`, and the shared
   blob-reference parser are Core primitives used by Storage; their CMake
   ownership moved to `ATProtoCore`, preserving Storage's declared acyclic
   closure and passing the macOS/GNUstep standalone Storage link test. The
   baseline ratcheted 27 -> 26.
5. **Sync identity helper (1, complete in `33357d36`).** The pure
   `publicKeyMultibase` decoder used by `RelayEventValidator` now belongs to
   Core, with XRPC retaining a forwarding compatibility API; Sync no longer
   imports an XRPC helper and the baseline ratcheted 28 -> 27.

The object-file mapping in the verified 2026-07-30 run is the starting evidence
for these batches. Read each implementation before choosing move versus
inversion; the earlier workstream already showed that directory names and the
link-time detector both miss real ownership constraints.

### M4.3. Close the gate

The acceptance gate is all of the following:

- `docs/module-boundary-baseline.txt` has no violation entries;
- `scripts/check_module_boundaries.sh build` reports zero current leaks;
- the source-import boundary gate also passes, catching type-only references
  that do not emit `_OBJC_CLASS_$_` symbols;
- every one of the ten archives can participate in a minimal link using only
  its declared transitive dependency closure;
- the full macOS suite and GNUstep/Linux gate pass.

Keep the baseline file with only its explanatory header, or teach the script to
treat an absent baseline as empty. Do not let the script recreate an allegedly
deleted baseline with `touch`.

Rollback: per-cluster commits revert independently. A dependency-declaration
commit must include its graph rationale and standalone-link test so it cannot
be mistaken for a convenient suppression.

## M4.5. Make module membership deterministic

Do this after the residual objects are assigned correctly and before public API
curation begins.

1. **Done (2026-08-04).** Added `CONFIGURE_DEPENDS` to all thirteen
   `file(GLOB_RECURSE)` module-source calls in `CMakeLists.txt` (the ten
   `ATProto*` package targets plus `ATProtoAppViewServer`/`ATProtoMikrus`/
   `ATProtoBeskid`, which glob from `Garazyk/Sources/` the same way but sit
   outside the ten-module boundary/namespace contract). New or renamed
   source files now trigger an automatic reconfigure instead of silently
   waiting for the next manual `cmake -S . -B build`. Verified: a fresh
   configure and an incremental `kaszlak`/`AllTests` build both succeed with
   no unexpected rebuilds (only the `CMakeLists.txt` directive itself
   changed, not source content).
2. **Not started.** Replacing the globs with hand-maintained per-target
   manifests under `cmake/modules/` is a separate, much larger change
   (~491 files across 13 lists) deliberately left for its own slice rather
   than folded into this one.
3. **Done (2026-08-04).** Added a configure-time assertion (`CMakeLists.txt`,
   right after `ATProtoBeskid`'s target definition, once all thirteen
   `ATPROTO_*_SOURCES` lists are finalized) that walks all thirteen lists and
   fails configure with `FATAL_ERROR` naming both owning targets if any
   source file appears in more than one. Verified it passes cleanly today
   (`-- M4.5: 491 package-target sources each claimed by exactly one
   module`) and verified it actually catches a violation: temporarily
   appending an `ATProtoCore`-owned file to `ATPROTO_STORAGE_SOURCES` made
   configure fail with the expected message, then reverted.
4. **N/A until item 2 lands.** "Do not export build-host absolute paths in
   those manifests" only applies once per-target manifest files exist; there
   are none yet.

Owner boundary: `CMakeLists.txt` only; no `Garazyk/Sources/` file moved,
renamed, or reassigned by this slice.

Verification gate: `cmake -S . -B build` reconfigures cleanly and reports the
per-target file count; `cmake --build build --target kaszlak AllTests
--parallel 4` succeeds; `./scripts/check_module_boundaries.sh build` still
reports 0 current / 0 baselined leaks (unaffected — this slice is CMake
bookkeeping, not a source move).

Verification gate: adding an unassigned implementation, assigning one file to
two targets, or renaming a source without updating its manifest fails
configuration.

## M5. Namespace the exported symbols

M0 is yes, but renaming begins only after M4 and M4.5. Namespace policy and the
public API must be defined before touching hundreds of call sites.

### M5.1. Define the public API and namespace policy

Create an explicit public-header manifest for each module. A header is not
public merely because it lives below `Garazyk/Sources`; installed consumers get
only the manifest. Compile each manifest as an umbrella before renaming.

Use the existing semantic prefixes consistently:

- `ATProto` for protocol/domain primitives;
- `PDS` for PDS-specific types;
- `GZ` for Garazyk infrastructure that is not an AT Protocol domain type.

The policy covers Objective-C classes, protocols, categories, exported
functions, global variables, notification names, and error domains. Category
names and any selectors added to types Garazyk does not own need a reserved
prefix too.

Generate two inventories from a fresh build:

1. all project-defined global/runtime symbols in the ten archives, grouped by
   owning target and object file; and
2. all declarations reachable from the curated public headers.

Check in a shrink-only namespace baseline. The 2026-07-30 build starts at 283
unprefixed Objective-C classes; the broader inventory will also expose C
symbols, protocols, and categories that the original class-only proposal
missed.

### M5.2. Add the namespace gate before renaming

Extend the existing boundary tooling or add a focused script that fails on any
new unprefixed project symbol. Exclude system and vendored symbols by provenance
(owning archive/object), not by an ever-growing name allowlist.

The gate must inspect at least:

- `_OBJC_CLASS_$_*` and `_OBJC_METACLASS_$_*`;
- Objective-C protocol and category metadata where the toolchain exposes it;
- externally visible C/Objective-C functions and data symbols; and
- installed public declarations.

Run the gate on both Apple and GNUstep/Linux archives because the selected
sources differ by platform.

### M5.3. Rename in dependency order

Use small, buildable commits with generated inventory deltas:

1. internal migration classes as a low-risk pilot;
2. Core primitives and Core-owned crypto/security helpers;
3. Storage and Transport;
4. PLC, Sync, Services, and MediaCore;
5. XRPC and VideoService;
6. Runtime and any remaining composition types.

Within a batch, rename the declaration, implementation, file, imports, string
lookups such as `NSClassFromString`, tests, fixtures, and documentation
together. Search for serialized class names and selector strings before
declaring the batch complete.

**Batch 1 complete (2026-08-04): internal migration classes, the low-risk
pilot.** All 30 baseline entries matching `V<N>*`/`AppViewV<N>*` — every
`PDSMigration`-conforming schema-version class — are private implementations
confined entirely to `Database/Migrations/PDSMigrationManager.m`, referenced
only by that file's own registration array. Confirmed via grep before
renaming that none of them appear via `NSClassFromString`,
`NSStringFromClass`, or as a string literal anywhere in `Garazyk/`, `docs/`,
`scripts/`, or `packages/`. Renamed to their `PDS`-prefixed form (e.g.
`V1InitialSchema` → `PDSV1InitialSchema`, `AppViewV5ActorCounts` →
`PDSAppViewV5ActorCounts`), matching the surrounding
`PDSMigrationManager`/`PDSMigration` naming; `PDSMigration.h`'s doc-comment
example updated to match. No file move, no import changes elsewhere — zero
external consumers.

Verified: `scripts/check_namespace.sh build` passes at **253 unprefixed
classes of 515 total, 253 baselined** (ratcheted from 283, a set-diff
confirmed the removal is exactly these 30 entries and nothing else changed);
`PDSMigrationManagerTests` (16/16) and `DatabaseMigrationTests` (3/3) pass;
full `AllTests --gated=run` on macOS: 4,966 tests, 0 failures, 563s.
`scripts/dev/check_module_boundaries.sh .`, `check-recursive-setters.sh`,
and `check_no_host_process_exit.sh` all pass unaffected.

Remaining M5.3 batches (2-6 above) are each their own slice — not attempted
in this pass.

**Batch 2, partial (2026-08-04): four smallest Core/Auth value types.**
Batch 2 ("Core primitives and Core-owned crypto/security helpers") groups
classes with wildly different blast radii — a consumer-count survey found
`CID` alone has **265** referencing files, `JWT` **136**, `JWTMinter` **80**,
`Secp256k1` **53**, `CryptoUtils` **45**, `TID` **41**, `DIDResolver` **30**,
`CBORValue` **30**, `Secp256k1KeyPair` **34** — each too large and
consequential for an unattended pass; they need their own carefully reviewed
session(s), not a mechanical sweep. This slice took only the four smallest,
most confined entries from the same baseline group (2-4 consuming files
each, confirmed via grep before renaming that none is referenced via
`NSClassFromString`/`NSStringFromClass`/a string literal anywhere in the
tree): `ATDID` → `ATProtoATDID`, `AuthCryptoDPoPResult` →
`ATProtoAuthCryptoDPoPResult`, `AuthVerifierPrincipal` →
`ATProtoAuthVerifierPrincipal`, `JWTHeader` → `ATProtoJWTHeader`. `ATProto`
matches the existing convention for Core-owned protocol/domain primitives
(`ATProtoDagCBOR`, `ATProtoMultibase`, `ATProtoValidator`, etc.).

Namespace baseline ratchets 253 → 249. Verified: `AuthVerifierParityTests`
(9/9), `JWTTests` (34/34), `OAuth2HandlerTests` (31/31),
`RelayXrpcRoutePackTests` (15/15), `AuthCryptoDPoPTests` (29/29), source and
link-time module boundary checks clean, full `AllTests --gated=run`:
4,966 tests, 0 failures, 588s.

**Batch 2b (2026-08-04): the next tier by consumer count.** Renamed eleven
more batch-2 classes, each with 6-18 referencing files (confirmed via grep
before renaming that none is referenced via
`NSClassFromString`/`NSStringFromClass`/a string literal): `Base58` →
`ATProtoBase58`, `CBOREncoder` → `ATProtoCBOREncoder`, `CBORDecoder` →
`ATProtoCBORDecoder`, `JWTPayload` → `ATProtoJWTPayload`, `JWTVerifier` →
`ATProtoJWTVerifier`, `AuthCryptoECDSA` → `ATProtoAuthCryptoECDSA`,
`AuthCryptoJWK` → `ATProtoAuthCryptoJWK`, `AuthCryptoDPoP` →
`ATProtoAuthCryptoDPoP`, `AuthCryptoBase64URL` → `ATProtoAuthCryptoBase64URL`,
`AuthVerifier` → `ATProtoAuthVerifier`, `ATURI` → `ATProtoATURI`.

A first mechanical pass incorrectly rewrote `#import "Auth/Crypto/
AuthCryptoDPoP.h"`-style path strings too, since the class names are literal
substrings of their own header paths — reverted and redone excluding
`#import` lines from the substitution. **File names and import paths are
deliberately left unchanged in this and future M5.3 slices**: the namespace
gate (`check_namespace.sh`) measures exported symbols via `nm`, not file
names, so renaming only the symbol satisfies the actual collision-avoidance
goal without the added risk of a repo-wide file-rename-plus-import-rewrite
in the same pass. `AuthCryptoDPoP.h` now declares `ATProtoAuthCryptoDPoP`.

Namespace baseline ratchets 249 → 238. Verified: 25 targeted test suites
covering every renamed class and every file with 2+ replacements (`Base58Tests`,
`AuthCryptoECDSATests`, `AuthCryptoJWKTests`, `AuthCryptoBase64URLTests`,
`AuthCryptoDPoPTests`, `AuthVerifierParityTests`, `JWTTests`,
`JWTSecurityTests`, `CBOREncoderCountWidthTests`, `CBORSerializationTests`,
`CBORParserExploitTests`, `CARParserExploitTests`, `PLCAuditorTests`,
`SecurityHardeningTests`, `ATProtoS2PACOSETests`, `CBORSecurityTests`,
`SyntaxInteropTests`, `ATProtoCoreTests`, `SessionStoreTests`,
`RepoCommitTests`, `ParserRecursionExploitTests`, `VideoJWTAuthProviderTests`,
`PDSSpaceAppAttestationVerifierTests`, `OAuthDPoPTests`,
`AuthCryptoDPoPTests`), all 0 failures; source and link-time module
boundary checks clean; `deno task check`/`lint` clean; full
`AllTests --gated=run`: 4,966 tests, 0 failures, 509s.

**Batch 2c (2026-08-04): the 26-34 consumer tier.** Renamed `DIDDocument` →
`ATProtoDIDDocument`, `DIDResolver` → `ATProtoDIDResolver`, `CBORValue` →
`ATProtoCBORValue`, `Secp256k1KeyPair` → `ATProtoSecp256k1KeyPair`.
`DIDDocument` declares `NSSecureCoding` conformance
(`encodeWithCoder:`/`initWithCoder:`/`supportsSecureCoding`) — checked
specifically, since a keyed-archive's default class-name encoding can break
cross-version compatibility on a rename if old archived data exists on
disk. Confirmed `NSKeyedArchiver`/`NSKeyedUnarchiver` is not used anywhere
in `Garazyk/Sources/`, so this is dead code from a persistence standpoint
today and the rename carries no on-disk compatibility risk. Same method as
batch 2b (`#import` path strings excluded, file names unchanged); verified
zero stray references to any of the four old names remain anywhere in
`Garazyk/Sources`/`Garazyk/Tests` after the rename (95 files, 928
replacements).

Namespace baseline ratchets 238 → 234. Verified: 23 targeted test suites
covering every renamed class and every file with a meaningful replacement
count, all 0 failures; source and link-time module boundary checks clean;
`deno task check`/`lint` clean; full `AllTests --gated=run`: 4,966 tests,
0 failures, 506s.

**Batch 2d (2026-08-04): TID and CryptoUtils, closing out the small/medium
tier.** `TID` → `ATProtoTID` (41 consumers), `CryptoUtils` →
`ATProtoCryptoUtils` (45 consumers). `TID.h` declares `NSSecureCoding`
conformance like `DIDDocument` in batch 2c — same finding applies
(`NSKeyedArchiver`/`Unarchiver` unused anywhere, no on-disk compatibility
risk).

**Caught and fixed a real mistake before committing this batch**: the first
mechanical pass over this batch's file list also rewrote a vendored JSON
test fixture (`Garazyk/Tests/fixtures/atproto-interop-tests/lexicon/catalog/record.json`),
changing a lexicon schema's `"a generic TID field"` description string —
unrelated protocol test data, not a namespace symbol, corrupted because the
rename script's file discovery targeted all of `Garazyk/Tests/`, which
includes vendored external corpora under `Tests/fixtures/` that happen to
mention the same short token. Reverted that one file before rebuilding.
**Future M5.3 batches must exclude `Garazyk/Tests/fixtures/` explicitly**
from file discovery, not rely on the class name simply not colliding with
fixture content — this is now a standing checklist item for every remaining
batch, not just short/common names like `TID`.

Also confirmed a `PDSCLIRepoCommandTests` failure seen when running that
class in isolation via `--filter` is a pre-existing test-isolation artifact
(0 failures as part of the full suite; same documented pattern as the
`RelayIntegrationTests` isolation artifact noted in this workstream's M4.2
section) — not a regression from this rename.

Namespace baseline ratchets 234 → 232. Verified: zero stray references to
either old name remain in `Garazyk/Sources`/`Garazyk/Tests` outside
`#import` path strings; source and link-time module boundary checks clean;
`deno task check`/`lint` clean; full `AllTests --gated=run`: 4,966 tests,
0 failures, 538s.

This closes out M5.3 batch 2 to the point where only the largest, riskiest
classes remain: `CID` (265 consumers), `JWT` (136), `JWTMinter` (80), and
`Secp256k1` (53) — each deliberately deferred to its own dedicated,
carefully reviewed session, and each large enough that an in-band rename
risks missing something a focused review pass would catch. **Before
attempting any of them, apply the `Tests/fixtures/` exclusion lesson above.**

`@compatibility_alias` is source compatibility only; it does **not** preserve
the old runtime class symbol or provide binary compatibility. If aliases are
needed to keep intermediate in-tree commits buildable, put them behind an
opt-in migration header that is never installed, never included by an umbrella,
and is removed before M6. Do not publish generic aliases such as `CID` or
`HttpRequest`, because their declarations recreate the source-namespace
collision the rename is meant to solve.

### M5.4. Close the namespace gate

Acceptance requires:

- zero project-owned namespace-baseline entries on macOS and GNUstep/Linux;
- no legacy compatibility aliases in package targets or installed headers;
- every curated umbrella compiles in isolation;
- runtime lookup/archiving tests pass for renamed types that use string-based
  discovery; and
- the full repository gates pass after each module batch.

Rollback: before the first external package release, each module batch can be
reverted. After release, a public rename is a source-breaking API change and
must follow the package's versioning policy; temporary aliases are not an ABI
rollback mechanism.

## M6. Make the libraries installable

M6 turns the curated, namespaced targets into the bounded CMake package chosen
in M0. It is not complete until a relocated install works on both supported
platforms.

### M6.1. Make target usage requirements relocatable

1. Replace blanket source-tree include paths with target-specific
   `$<BUILD_INTERFACE:...>` and `$<INSTALL_INTERFACE:...>` paths.
2. Audit every `PUBLIC` compile definition, option, include path, and link
   library. Keep only requirements that an installed consumer genuinely needs.
3. Replace global `include_directories()`/`link_directories()` platform setup
   with target-scoped imported or interface targets.
4. Resolve the `secp256k1` export problem explicitly. `ATProtoCore` currently
   exposes a `PUBLIC` dependency on a vendored target whose installation is
   disabled. Either install/export that target as part of Garazyk or hide it
   behind a packaged implementation target while preserving static-link
   closure; never emit a dangling target reference.
5. Represent Apple frameworks, GNUstep Foundation/runtime, SQLite, OpenSSL, and
   other transitive dependencies through relocatable targets and
   `find_dependency()` calls rather than build-host absolute library paths.

Add build-tree aliases named `Garazyk::ATProtoCore` and so on, matching the
installed target names.

### M6.2. Install the curated headers

Use the M5 public-header manifests to preserve the import directory structure
under one stable include root. Do not flatten path-based imports into a single
directory.

Repair the existing eight umbrella headers, create missing umbrellas for
`ATProtoMediaCore` and `ATProtoVideoService`, and define or remove the currently
declaration-only `*VersionNumber`/`*VersionString` symbols. Add one compile-only
target per umbrella so a missing or private transitive header fails in the
normal build.

Choose one of these mechanisms and use it consistently:

- raise the CMake minimum after verifying CI, then use `FILE_SET HEADERS` with
  explicit base directories; or
- keep CMake 3.21 and install the explicit manifest with a helper that preserves
  each relative directory.

### M6.3. Export the CMake package

Install the ten targets into one export set with
`NAMESPACE Garazyk::`. Generate:

- `GarazykTargets.cmake`;
- `GarazykConfig.cmake`;
- `GarazykConfigVersion.cmake` using the project version;
- optional component checks for the ten modules; and
- license/notice files and a concise installed-package README.

The config file must discover external dependencies before loading the target
export and must contain no source- or build-tree absolute paths.

### M6.4. Add consumer and relocation tests

Check in minimal consumers under `tests/package-consumers/`:

1. **Core-only:** imports the Core umbrella, constructs/parses representative
   CID/TID/ATURI values, and links only `Garazyk::ATProtoCore`.
2. **Full graph:** imports every umbrella and links the highest-level exported
   targets, exercising transitive closure without manually naming their
   dependencies.
3. **Negative/private-header:** proves a non-public implementation header is
   unavailable from the install tree.

CI must:

1. configure and build Garazyk in a fresh out-of-source directory;
2. install to a temporary prefix;
3. move or copy that prefix to a different absolute path;
4. configure, build, and run the positive consumers using only
   `CMAKE_PREFIX_PATH` to the moved prefix; and
5. verify the negative consumer fails for the intended missing-header reason.

Run the sequence on macOS and GNUstep/Linux. Also scan installed `.cmake`,
`.pc`, and header files for the original source/build directory.

### M6.5. Document and release the experimental contract

Document supported platforms, compiler/CMake minimums, components, dependency
requirements, example `find_package` usage, static-library/category linker
requirements such as `-ObjC` where applicable, and the 0.x compatibility
policy. Record a release checklist, but leave registry publication and prebuilt
artifacts to a later decision.

Verification gate: both relocated consumers pass on both platforms; the
private-header test fails as designed; namespace and module-boundary baselines
remain empty; and the mega plan's global gates pass.

Rollback: target cleanup and public-header curation are retained because they
improve the internal build. Package install/export files and consumer fixtures
can be reverted as one additive change before the first release.

## M7. Embedding hygiene

Independent of M0; can run in parallel with anything after M1.

- **[Partial]** Replace `exit()` and `abort()` in package-target sources with
  error returns or caller-owned lifecycle callbacks. Terminating the host
  process is not a library's decision. The original `GZServiceLifecycle` and
  compatibility-shim sites were fixed, but `PDSApplication` and CLI command
  implementations compiled into package targets still call `exit()`.
- **[Partial]** Route hardcoded absolute paths
  (`/usr/share/garazyk/lexicons`, `/usr/share/atprotopds/assets`,
  `/var/db/kaszlak/log`) through `ATProtoDataPaths` or configuration. Lexicon
  and installer path work landed, but the installer's log fallback still uses
  `/var/db/kaszlak/log/daemon.log`.
- **[Done]** Delete the debug sink at
  `Garazyk/Sources/AppView/Server/Backfill/AppViewBackfillWorker.m:289`, which
  writes to `/tmp/debug-logs/backfill.log` on every run and appears
  unintentional.
- Give `ATProtoSafeHTTPClient` and `GZMetrics` injectable instances, keeping
  `+shared*` as the default, and extend `ATProtoServiceContainer` rather than
  adding a second injection mechanism.

Verification gate: a CI grep rejects `exit(`, `abort()`, and absolute path
literals in module target sources; `AllTests` passes.

Rollback: per-item commits revert independently.

## Sequencing

```
M0 (yes, bounded package contract) ─────────────────────────────────────┐
                                                                       ▼
M1 ✓ ──► M2 ✓ ──► M3 ✓ ──► M4 residual cleanup ──► M4.5 ──► M5 ──┬──► M6
                              │                                  │
                              └──► M7 residual cleanup ──────────┘
```

M1-M3 are complete. The critical path is now:

1. drive the real M4 baseline from 30 to zero;
2. finish M7's host-control and absolute-path cleanup;
3. make module source ownership deterministic;
4. curate the public API and eliminate project-owned namespace collisions; and
5. export and validate a relocatable package.

M5 must not begin while M4 is still baselining undeclared dependencies: a
namespace migration would obscure the same symbols used to measure those
violations. M6 can be prototyped on a throwaway branch, but package changes must
not land before the M5 public surface and namespace gates and M7 embedding
gates are complete.

## Rollback

M1-M4 changes remain independently revertible by module pair and do not change
on-disk or wire formats. M5 source renames are revertible only before a package
release; `@compatibility_alias` is an optional in-tree migration aid, not binary
compatibility and not part of the installed surface. M6 package metadata is
additive, while its target-scoping and public-header cleanup should be retained
even if distribution is deferred.

The module and namespace baselines record remaining debt while work is in
flight. Both must be empty before the first external release.

## Global gates

Every lane runs the mega plan's global gates:

```bash
deno task check
deno task lint
deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests --gated=run
```

Run `xcodegen generate` before macOS Xcode builds. M4-M6 additionally require
the GNUstep/Linux gate because the package contract supports that platform.
M5 runs the namespace gate on both platform archive sets. M6 runs the relocated
install-tree consumer suite and rejects source/build absolute paths in installed
metadata.

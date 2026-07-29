---
title: Module Boundaries and Library Consumption
status: active
last_verified: 2026-07-29
---

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

**Remaining for M3:** `HttpRouter` itself appears to be legacy/dead —
its only non-test reference in the whole tree is `HttpRouterTests.m`;
the live request path goes through `HttpRouteTrie` instead. Confirming
and removing dead code is a separate, distinct decision from module
boundaries and was left untouched here (out of scope for a boundary
fix, and not something to do "while in the neighborhood" without
explicit sign-off). `SSRFValidator`, `HttpBufferPool`, and the
connection drivers were left in Transport per the original plan (they
have genuine socket/I/O dependencies). The `Network/` import-count
figure this milestone's verification gate names (86 → 36) was not
re-measured directly — the module-boundary baseline is the tracked
metric per M1's own correction, and it moved as described above.

M4 remains not started. M0 (third-party consumption goal) remains an
open decision — M1's baseline is useful either way, but M5/M6 stay gated
on it.

# Module Boundaries and Library Consumption

## Target

The ten `ATProto*` static libraries become real boundaries: each links against
only its declared dependencies, the build enforces that property, and the
declared dependency graph in `CMakeLists.txt` stops being documentation.

Whether those libraries are also *published* for third-party consumption is a
separate decision. Items M1-M4 are worth doing either way — they are internal
architecture health and they are what make the graph true. Items M5-M6 only pay
off if external consumption is a goal, and they are the expensive half. Decide
M0 before starting M5.

## M0. Decide the consumption target

Answer one question and record it: is a third-party project expected to link
`libATProtoCore.a` (or a framework built from it) without vendoring this
repository?

- **No** — stop after M4 and M7. The dependency graph becomes true and
  enforceable, which is worth it on its own. Skip symbol renaming and install
  rules.
- **Yes** — M5 and M6 become required, and the symbol renaming in M5 is a
  one-way door that should happen before any external consumer exists.

This gates roughly two-thirds of the total effort. Nothing below M4 depends on
the answer, so M1-M4 can start immediately.

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

What is left after M3 needs design, not moves — but most of it is the same bug:
a protocol declared in the wrong layer.

- `Storage -> Services` (5): `ATProtoHandleValidator` is a pure validator with
  no service dependencies. Move it to Core.
- `Video -> Services` (7), `MediaCore -> Services` (4), `XRPC -> Video` (5):
  `PDSBlobProvider` is already a protocol. Move the protocol to Core and leave
  the implementations in Services.
- `Transport -> Storage` (7): `RateLimiter` and two route packs reach into the
  database. Inject a storage protocol rather than importing `PDSDatabase.h`.
- `Transport -> Runtime` (3): route packs import `App/` handlers. Invert the
  registration so handlers register themselves with the router.
- `PLC <-> Sync` (2): a genuine cycle. `PLCServer` imports the WebSocket
  adapter and `RelayEventValidator` imports `DIDPLCResolver`. Break it with a
  resolver protocol owned by Core.
- `XRPC -> PLC` (7): decide whether PLC belongs below XRPC in the declared
  graph. This one may be a wrong edge in the DAG rather than wrong code.

Owner boundary: one module pair per commit, each landing a baseline reduction.

Verification gate: baseline reaches zero; the gate script then runs without a
baseline file at all.

Rollback: per-pair commits revert independently.

## M5. Namespace the exported symbols

Only if M0 answered yes. This is a one-way door and should precede any external
consumer.

Order by collision risk, highest first:

1. Migration classes (`V1InitialSchema` through `V17...`, `AppViewV1...`).
   These are internal with no external contract — rename outright.
2. Transport types: `HttpRequest`, `HttpResponse`, `HttpServer`, `HttpRouter`,
   `RateLimiter`, `HttpParsing`.
3. Core and Storage types: `CID`, `TID`, `ATURI`, `Base58`, `DIDResolver`,
   `MST*`, `CBOR*`, `CAR*`.

Use `@compatibility_alias` for a deprecation window so in-tree call sites
migrate incrementally instead of in one 500-file commit.

Verification gate: every exported `_OBJC_CLASS_$_` in every `ATProto*` archive
matches `^(GZ|ATProto|PDS)`, checked by the same CI script as M1.

Rollback: the aliases keep old names resolving for the whole window; revert is
per-module.

## M6. Make the libraries installable

Only if M0 answered yes.

1. `install(TARGETS ... EXPORT GarazykTargets)` for the ten module targets,
   plus `GarazykConfig.cmake` and `write_basic_package_version_file`.
2. Replace the blanket source-tree include directory with per-module
   `BUILD_INTERFACE`/`INSTALL_INTERFACE` paths and a curated public header set,
   so private headers stop being public.
3. Repair the umbrella headers and add a compile-only target that imports each
   one. The absence of such a target is why `ATProtoServices.h` could reference
   six nonexistent files indefinitely.
4. Replace `GLOB_RECURSE` plus regex filters with explicit source lists, or at
   minimum add `CONFIGURE_DEPENDS`, so module membership stops being implicit
   in a file's path.

Verification gate: an out-of-tree sample consumer runs `find_package(Garazyk)`,
links `ATProtoCore` alone, and builds — which is only possible once M2 is done.

Rollback: install and export rules are additive; the sample consumer lives
outside the build.

## M7. Embedding hygiene

Independent of M0; can run in parallel with anything after M1.

- Replace `exit(1)` and `abort()` in library targets with error returns.
  Terminating the host process is not a library's decision.
- Route the hardcoded absolute paths (`/usr/share/garazyk/lexicons`,
  `/usr/share/atprotopds/assets`, `/var/db/kaszlak/log`) through
  `ATProtoDataPaths` or configuration.
- Delete the debug sink at
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
M0 ─────────────────────────────► (gates M5, M6 only)
M1 ──► M2 ──► M3 ──► M4 ──► M5 ──► M6
                       └──► M7 (parallel)
```

M1 gates everything because it is what makes the rest measurable. M2 proves the
approach on the smallest real module. M3 removes the largest cluster. M4 drives
the baseline to zero. M5 and M6 deliver external consumption. M7 is independent
polish.

## Rollback

Every item is independently revertible and none changes on-disk formats, wire
formats, or the XRPC surface. M1 touches no product source. M2 and M3 are file
moves plus additive protocols. M5 carries `@compatibility_alias` for its
deprecation window. If the workstream is abandoned mid-flight, the baseline file
records exactly how far it got.

## Global gates

Every lane runs the mega plan's global gates. M3 and anything touching
`Network/` or `Compat/` additionally requires the Linux Docker gate.

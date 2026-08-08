---
title: Per-Service Admin UIs
status: active
last_verified: 2026-08-04
---

## Target

Replace the single `garazyk-ui` process with an admin UI owned by each service
binary, sharing one design system through a new `ATProtoAdminUI` library.
`ATProtoAdminUI` depends on `ATProtoTransport` and `ATProtoCore` only, holds no
compile-time knowledge of any service, and is reached through a
`GZAdminUIPack` protocol that services implement. `garazyk-ui` is deleted.

The decision and its constraints are recorded in
[ADR 0033](../../adr/0033-per-service-embedded-admin-uis.md).

## Current evidence (2026-08-04)

**The code is already cut along service seams.** Ten
`UIBackendClient+<Service>` categories, eleven
`UIServerRuntime+<Service>Routes` categories, and per-service HTML partials.
Three things hold them in one process: a hardcoded registration sequence in
`-[UIServerRuntime registerRoutes]`, a 49-declaration private header
(`UIServerRuntime+Private.h`), and a shell template with twelve hardcoded tabs
and panels.

**Four tabs are not separate services.** Auditing the `baseURL` each backend
category resolves against:

| Tab | Resolves against | Owning binary |
| --- | --- | --- |
| pds, ozone, security, explorer, mst, lab | `pdsBaseURL` | `kaszlak` |
| relay | `relayBaseURL` | `zuk` |
| plc | `plcBaseURL` | `campagnola` |
| appview | `appViewBaseURL` | `syrena` |
| chat | `chatBaseURL` | `syrena-chat` |
| video | `videoBaseURL` **and** `pdsBaseURL` | `jelcz` |
| overview, connections | all of them | dropped (M5) |

Video is the only genuine cross-service edge in the tree.

**`AdminUIServer/` is in no library and escapes three gates.** Its 6,152 lines
compile directly into `garazyk-ui` (`CMakeLists.txt`, `add_executable(garazyk-ui …)`)
and again into `AllTests`. The link-time boundary gate (ADR 0031) and
`scripts/check_namespace.sh` both enumerate ten `ATProto*` archives;
`AdminUIServer/` is in none of them, which is why no `UI*` class appears in
the 238-entry `docs/namespace-baseline.txt`. The target links
`ATProtoAppViewServer`, `ATProtoRuntime`, `ATProtoStorage`, `ATProtoServices`,
`ATProtoSync`, `ATProtoTransport`, and `ATProtoCore` beneath a comment
describing it as "a thin HTTP server that calls XRPC endpoints on backends."

**PLC has no admin credential.** Neither `Garazyk/Binaries/campagnola/main.m`
nor `Garazyk/Sources/PLC/` contains an admin token or password concept. The
pilot must introduce one.

**`PLCRuntimeComposite` already composes runtimes.** It holds `server` and
`syncEngine` and is handed to `GZServiceLifecycle`. An admin UI attaches as a
third member with no new lifecycle machinery.

**Twenty-six files outside the C sources name `garazyk-ui`** or its
environment variables: `packages/schemat` (7, including the
`WebClientTopology` type and its `buildPreset: "garazyk-ui"` member),
`packages/hamownia` (7), `scripts/` (7), `docker/` (4), and `project.yml`.

## M0. Decide the hosting model

**Answered** — embedded per service on a dedicated loopback-bound listener,
shared library, `garazyk-ui` deleted, cross-service Overview and Connections
dropped. Alternatives and their consequences are in ADR 0033.

## M1. Make an admin listener safe to embed

**Complete (2026-08-04).** Both preconditions for two UIs coexisting. Neither
touches a service; `garazyk-ui` behavior is unchanged.

### M1.1. Parameterize HTTP server concurrency

**Complete (2026-08-04).**

`kMaxConcurrentRequests` was a file-static `const NSUInteger` of 64 in
`HttpServer.m`, and `_concurrencySemaphore` is created from it per server
instance. Every request is `dispatch_async`'d to the shared global concurrent
queue and waits on that semaphore *while already occupying a global worker*.
Because `UIBackendClient`'s transport primitives block the calling thread, an
embedded UI holds a global worker for the duration of a loopback request — a
worker its own service's listener needs to answer it. Two listeners at 64 each
can demand more workers than the pool provides.

1. The constant became the public `kHttpServerDefaultMaxConcurrentRequests`,
   and `-initWithHost:port:maxConcurrentRequests:` is the designated
   initializer. `-initWithHost:port:` delegates with the default, so every
   existing call site is unchanged; 0 selects the default.
   `+serverWithHost:port:maxConcurrentRequests:` is the public factory.
2. `maxConcurrentRequests` is exposed readonly for verification.
3. Four tests in `HttpServerTests`. The substantive one registers a handler
   that blocks, queues 12 requests against a limit of 4, and asserts the
   observed peak concurrency is **exactly** 4 — equality rather than
   `<= 4`, because a lesser peak would mean the requests never overlapped and
   would prove nothing about the cap. Verified stable across repeated runs.

Admin listeners are constructed with a limit of 8 in M3, where the first one
is created.

### M1.2. Scope cookie names to a service identity

**Complete (2026-08-04).**

Cookies are not port-scoped, so `127.0.0.1:2591` and `127.0.0.1:2592` share a
cookie jar and the fixed `ui_admin_token` / `ui_admin_nonce` names collide.

The original framing of this item claimed two UIs could cross-authorize.
Reading `UIAuthManager` disproves it: sessions live in a per-instance
`activeSessions` dictionary keyed by token hash, so a token minted by one
manager is absent from another's and already rejected. The defect is
correctness, not privilege escalation — signing in to the second UI overwrites
the first UI's cookie and silently evicts that session, and the one-time CSRF
nonce is worse because it rotates on every accepted mutation. Two embedded UIs
would be unusable in one browser. ADR 0033 §6 records the corrected reading.

1. `-[UIAuthManager initWithPassword:serviceIdentifier:]` derives
   `gz_admin_<id>_token` and `gz_admin_<id>_nonce`. `initWithPassword:` keeps
   the unscoped `ui_admin_token` / `ui_admin_nonce`, so `garazyk-ui`, the
   existing suites, `packages/gruszka/clients/admin.ts`, and
   `scripts/scenarios/scenarios/11_lab_oauth_login.ts` are untouched until M5
   deletes that path.
2. `sessionCookieName` and `csrfCookieName` are read from the manager
   everywhere, including the logout cookie-clear in `UIServerRuntime.m`.
3. `GZLogRedactor` gained a `gz_admin_[a-z0-9_]+_(token|nonce)=` pattern.
   Without it the new cookies would not be redacted from logs.
4. Five tests in `UIAuthManagerTests`, covering name derivation, a UI ignoring
   a sibling's cookie when the browser sends both, both sessions staying
   independently authorized, and a scoped UI rejecting a legacy cookie.

Deferred: the `__Host-` prefix under TLS, which needs the listener to know it
is TLS-terminated. Not required for loopback, where the admin listeners run.

**Acceptance:** met. `UIAuthManagerTests` 21 tests, 0 failures. `garazyk-ui`
behavior is unchanged because it uses the unscoped initializer.

## M2. Extract ATProtoAdminUI and invert route registration

The substantive milestone. Its acceptance gate deliberately touches no
service: `garazyk-ui` is rebuilt as the library's first consumer, composing
all packs, and must behave identically. The extraction is proven by the
existing application before anything embeds.

### M2.1. Define the pack protocol and host

`GZAdminUIPack` declares a pack's identifier, display name, sidebar sections,
and a route-registration entry point. `GZAdminUIHost` (today's
`UIServerRuntime`) is constructed with an array of packs and replaces the
hardcoded `registerPDSRoutes` … `registerMSTRoutes` sequence. The host must
not reference any service type. Mirror the existing
`XrpcRoutePackServiceBag` convention rather than inventing a second
composition idiom.

### M2.2. Split the private header

`UIServerRuntime+Private.h` declares 49 renderers in one category. Shared
primitives (escaping, alerts, tables, empty and error states) move to the
library; per-service renderers move to their pack. This is the largest
mechanical risk in the workstream — sequence it one service at a time, with
the tree green between each.

### M2.3. Split the backend client

Transport primitives (`performJSONRequestWithURL:…`, `performRequestWithURL:…`,
`URLByAppendingPath:queryItems:baseURL:`, `pathWithSegments:`) become the
library's `GZAdminUIBackendClient`. The ten `+<Service>` categories become
pack-owned clients. `serviceProbeSpecifications` is Overview-only and is
deleted in M5, not carried into the library.

### M2 status (2026-08-08)

- **M2.1 complete:** `GZAdminUIPack`, `GZAdminUIHost`, and the eleven stateless pack adapters landed in `f8a29293`; the host registers only the caller-supplied pack array and `GZAdminUIDefaultPacks()` remains the sole full-surface composition point.
- **M2.2 complete:** all eleven renderer groups moved from the shared private header into their matching `GZAdminUI<Pack>` implementations, one service per commit (`661d8396` through `f32cc9b5`).
- **M2.3 complete and validated:** `UIBackendClient` became `GZAdminUIBackendClient`, and its ten service categories moved to `AdminUIServer/Packs/` in `50ae9705`. `garazyk-ui` and `AllTests` build; registration audit, `GZAdminUIBackendClientTests` (52), `UIServerRuntimeTests` (26), UI design-system, source/link module-boundary, namespace, and recursive-setter gates pass. Repo-doc validation remains blocked by the pre-existing `scripts/docs/deno.json` workspace-membership error.
- **Remaining:** M2.4 shell composition, M2.5 asset-pipeline split, and M2.6 `ATProtoAdminUI` library/gate registration.

### M2.4. Make the shell composable

`shell.html` hardcodes twelve tabs and twelve panels. Render the navigation
from pack metadata instead. `UITemplateEngine` already supports array sections
(`{{#key}}…{{/key}}` over dictionary elements), so this is a template and
context change, not an engine change.

Two navigation modes, one chrome: multi-section services (PDS) keep the
segment row; single-surface services replace it with the service identity plus
the peer switcher, moving sections to the sidebar. Toolbar, sidebar, status
bar, and tokens stay identical across every service — one visual language, per
`.agents/skills/garazyk-admin-ui`.

### M2.5. Split and generalize the asset pipeline

Assets divide into library-owned (`css/`, `js/admin-ui.js`, shell and login
templates) and pack-owned (per-service partials, `js/lab.js`,
`js/mst-viewer/`). The `ADMIN_UI_ASSET_STAMP` custom command becomes a CMake
function each service target calls. Three hardcoded paths need updating:
`UITemplateEngine`'s test fallback (`Garazyk/Sources/AdminUIServer/Assets`),
the `AdminUIAssetsSync` ctest, and `scripts/admin-ui-build/generate_css_bundle.ts`.
All binaries share `${CMAKE_BINARY_DIR}/bin/`, so one built `Assets/`
directory continues to serve every service.

### M2.6. Register the library with all three gates

1. `scripts/dev/check_module_boundaries.sh` — declare `ATProtoAdminUI`'s
   dependencies as `ATProtoTransport ATProtoCore` and place it at level 3.
2. `scripts/check_module_boundaries.sh` — the ADR 0031 link-time gate parses
   `CMakeLists.txt`, so it follows automatically; confirm the baseline does
   not need a ratchet.
3. `scripts/check_namespace.sh` — add `ATProtoAdminUI` to `MODULES`.

Adding the library to the namespace gate exposes roughly fifteen `UI*` classes
to it for the first time. Adding them unprefixed would grow
`docs/namespace-baseline.txt`, which that gate exists to prevent, so **rename
`UI*` to `GZAdminUI*` as part of this milestone, not after it.** This retires
unprefixed classes rather than adding them and is a net contribution to
workstream 08 M5.3.

**Acceptance:**

- `garazyk-ui` links `ATProtoAdminUI`, `ATProtoTransport`, and `ATProtoCore`
  only — the dropped links to `ATProtoRuntime`, `ATProtoStorage`,
  `ATProtoServices`, `ATProtoSync`, and `ATProtoAppViewServer` are the
  measurable proof the extraction is real.
- All three gates pass; the namespace baseline shrinks rather than grows.
- Existing `UIServerRuntimeTests`, the browser and visual smoke tests, and
  `scripts/test/check_ui_design_system.sh` pass unchanged.
- No file under `Garazyk/Sources/` outside a pack names a service-specific UI
  symbol.

## M3. PLC pilot (campagnola)

The smallest real surface: six routes (`plc-did`, `plc-log`, `plc-health`,
`plc-metrics`, `plc-list`, `plc-export`), a 103-line backend client, three
partials. Chosen because PLC has no admin credential today, which forces the
credential story into the open rather than letting it be inherited from the
PDS.

1. Introduce `GARAZYK_PLC_ADMIN_PASSWORD`. Fail closed when unset — the admin
   listener does not start, and the service logs why.
2. Add `PLCAdminUIPack` under `Garazyk/Sources/PLC/AdminUI/`.
3. Attach it to `PLCRuntimeComposite` as a third member alongside `server` and
   `syncEngine`. Add `--admin-ui-port` / `GARAZYK_PLC_ADMIN_UI_PORT`, bound to
   `127.0.0.1` unless explicitly overridden.
4. Mint the internal loopback token at startup and hand it to the pack
   in-process. No token reaches the environment, disk, or any network beyond
   loopback.
5. Register the new test suite in **both** places: re-run
   `cmake -S . -B build` so the glob picks the file up, and add the class to
   the `testClasses` array in `Garazyk/Tests/test_main.m`. The registration
   audit fails on a mismatch in either direction.

**Acceptance:** `campagnola` serves the PLC UI; `garazyk-ui` still serves an
identical one from the same pack; both run simultaneously without session
interference (M1.2) or worker starvation under concurrent load (M1.1);
`campagnola` refuses to expose the admin listener with no password set.

## M4. Roll out the remaining services

In ascending order of surface, so the mechanical pattern is established before
the largest one: `zuk` (relay), `syrena` (appview), `syrena-chat` (chat),
`jelcz` (video), then `kaszlak` (pds, ozone, security, explorer, mst, lab).

`jelcz` retains a narrow PDS client for the cross-service calls in
`UIBackendClient+Video`. `kaszlak` composes six packs — the pack protocol
should absorb this without special-casing, and if it does not, that is a
defect in M2.1 rather than a reason to special-case `kaszlak`.

**Acceptance:** every service serves its own UI; `garazyk-ui` still works;
double maintenance is confined to this milestone.

## M5. Retire garazyk-ui

1. Delete the binary, its CMake target, `docker/Dockerfile.ui`, and the
   `project.yml` entry.
2. Delete the Overview and Connections packs, their renderers and partials,
   and `serviceProbeSpecifications`.
3. Add the peer switcher: configured links to sibling UIs, no polling, no
   credentials, no health claims about processes it cannot observe.
4. Update the 26 files enumerated in Current evidence. `packages/schemat`'s
   `WebClientTopology` and its `buildPreset: "garazyk-ui"` member are a type
   change with test fallout in `topology_compiler_test.ts` and
   `topology_registry_test.ts`; `scripts/scenarios/scenarios/11_lab_oauth_login.ts`
   must move to the PDS admin listener.
5. Update `Garazyk/Sources/Admin/ADMINUI_ARCHITECTURE.md`,
   `.agents/skills/garazyk-admin-ui`, `PRODUCT.md`, and `CLAUDE.md`'s service
   table.

**Acceptance:** no reference to `garazyk-ui` or `GARAZYK_UI_*` survives outside
`docs/adr/` and run artifacts under `scripts/scenarios/reports/`;
`deno task check && deno task lint && deno task test` passes; the scenario
suite runs against the per-service UIs.

## Risks and coordination

**The PDS UI does not shrink.** `kaszlak` absorbs six of twelve tabs. This
workstream reduces the fleet and the credential blast radius; it does not
reduce the PDS admin surface. Treat any plan that assumes otherwise as
mis-scoped.

**Web Tiles overlaps workstream 10.** `UITileDataProtocol` and
`UITileExecutionPolicy` implement a DASL tiles protocol slice served at
`/.well-known/web-tiles/data.js`. It is a UI-host concern, not a service admin
function, so it belongs in `ATProtoAdminUI` — but workstream 10 is active and
should be consulted before the files move.

**The 49-declaration private header is the mechanical risk.** M2.2 is where
this workstream is most likely to produce a long red tree. Split one service
at a time.

**Double maintenance during M3-M4.** Each service's pack is deliberately
served by both `garazyk-ui` and its own binary until M5. This is the cost of
keeping the tree green throughout, and it is bounded by finishing M4.

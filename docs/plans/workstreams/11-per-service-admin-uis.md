---
title: Per-Service Admin UIs
status: active
last_verified: 2026-08-12
---

## Target

Replace the single the former monolithic admin UI process with an admin UI owned by each service
binary, sharing one design system through a new `ATProtoAdminUI` library.
`ATProtoAdminUI` depends on `ATProtoTransport` and `ATProtoCore` only, holds no
compile-time knowledge of any service, and is reached through a
`GZAdminUIPack` protocol that services implement. the former monolithic admin UI is deleted.

The decision and its constraints are recorded in
[ADR 0033](../../adr/0033-per-service-embedded-admin-uis.md).

Service-specific execution detail lives in the subordinate
[per-service brief index](service-admin-uis/README.md). Those briefs do not
create a separate backlog: this workstream owns their scope and status.

## Current evidence (2026-08-11)

The deployable-service inventory was rechecked after the Relay operations
dashboard landed. `zuk` now supplies the concrete overall/per-upstream
information model and browser-session boundary. Existing packs cover PLC,
AppView, Chat, Video, and the six PDS-owned surfaces; Mikrus, Beskid, and Germ
have no packs. All nine service binaries and the missing-pack work are now
accounted for in the [service brief index](service-admin-uis/README.md).

M2.6 is complete on `main` (merge `8b45c6d9`): `ATProtoAdminUI` is a static
library with only `ATProtoTransport` and `ATProtoCore` dependencies,
the former monolithic admin UI is its compatibility consumer, and the three boundary/namespace
gates include the new target. Phase 30 closed on 2026-08-11 after a complete
gated suite, live browser and visual smokes, design-system, and asset-sync
evidence; the exact closeout evidence is recorded in the M2.6 entry below.

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
compile directly into the former monolithic admin UI (`CMakeLists.txt`, `add_executable(<retired admin UI> …)`)
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

**Twenty-six files outside the C sources name the former monolithic admin UI** or its
environment variables: `packages/schemat` (7, including the
`WebClientTopology` type and its `buildPreset: "social-app"` member),
`packages/hamownia` (7), `scripts/` (7), `docker/` (4), and `project.yml`.

## M0. Decide the hosting model

**Answered** — embedded per service on a dedicated loopback-bound listener,
shared library, the former monolithic admin UI deleted, cross-service Overview and Connections
dropped. Alternatives and their consequences are in ADR 0033.

## M1. Make an admin listener safe to embed

**Complete (2026-08-04).** Both preconditions for two UIs coexisting. Neither
touches a service; the former monolithic admin UI behavior is unchanged.

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
   the unscoped `ui_admin_token` / `ui_admin_nonce`, so the former monolithic admin UI, the
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

**Acceptance:** met. `UIAuthManagerTests` 21 tests, 0 failures. the former monolithic admin UI
behavior is unchanged because it uses the unscoped initializer.

## M2. Extract ATProtoAdminUI and invert route registration

The substantive milestone. Its acceptance gate deliberately touches no
service: the former monolithic admin UI is rebuilt as the library's first consumer, composing
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
- **M2.3 complete and validated:** `UIBackendClient` became `GZAdminUIBackendClient`, and its ten service categories moved to `AdminUIServer/Packs/` in `b3bc45e6`. the former monolithic admin UI and `AllTests` build; registration audit, `GZAdminUIBackendClientTests` (52), `UIServerRuntimeTests` (26), UI design-system, source/link module-boundary, namespace, and recursive-setter gates pass. After integration with current `main`, internal-strict repo-doc validation also passes.
- **M2.4 complete and validated (2026-08-08):** pack metadata now generates the existing shell's twelve tabs in the pre-extraction visual order, with the original panels retained until M2.5 owns their asset relocation. One-section compositions use a sidebar tablist and service identity, plus a presentation-only empty peer-switcher; no discovery, polling, credentials, or health claims were added. `UIServerRuntimeTests` adds default-composition ARIA/order coverage and a relay-only sidebar/peer-empty-state test. After initializing the previously absent `vendor/secp256k1` submodule in this worktree, `cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug`, `cmake --build build --target AllTests --parallel 4`, and `./build/tests/AllTests --filter UIServerRuntimeTests --gated=run` passed (28 tests, 0 failures). `node --check`, `git diff --check`, source/link module-boundary, recursive-setter, and host-process-exit gates passed. `check_ui_design_system.sh` could not run because `rg` is absent; `test_static_files.sh` remains a pre-existing unrelated failure because current `kaszlak` returns 404 for its stale `/explore` target.
- **M2.5 complete and validated (2026-08-08):** library-owned CSS, shared templates/scripts, and pack-owned partials/scripts now live in separate `Assets/library/` and `Assets/packs/<pack>/` source trees. A reusable `add_admin_ui_assets()` CMake function overlays both trees into the single shared `${CMAKE_BINARY_DIR}/bin/Assets/` directory, with one generalized `ADMIN_UI_ASSET_STAMP` and pack-safe `AdminUIAssetsSync` inventory/hash checking. `UITemplateEngine` resolves library templates and searches pack partials in the source-tree fallback; the CSS bundle generator follows the relocated library CSS. Verified with `cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug`, `cmake --build build --target AllTests --parallel 4`, `UIServerRuntimeTests` (28 tests, 0 failures), `GZAdminUIBackendClientTests` (52 tests, 0 failures), `AdminUIAssetsSync`, CSS bundle drift, JavaScript syntax, `check_ui_design_system.sh`, and `git diff --check`. The full-suite baseline required by Phase 30 was run before edits and returned exit 1; its redirected rerun was intentionally interrupted after 11m43s without a final summary. `test_static_files.sh` and `test_page_load.sh` remain unrelated stale `/explore`/legacy resource checks and fail against current `kaszlak` routes.
- **M2.6 implementation complete, acceptance blocked (2026-08-08):** added `ATProtoAdminUI` as a static target with only `ATProtoTransport` and `ATProtoCore` library dependencies; registered it with source, link-time, and namespace gates; rebuilt the former monolithic admin UI as the compatibility consumer; moved service route categories under `AdminUIServer/Packs/`; and completed the post-WS08 HTTP handoff using `ATProtoHttp*` symbols. Exposed UI symbols were renamed to `GZAdminUIAuthManager`, `GZAdminUIServiceConfig`, `GZAdminUITemplateEngine`, `GZAdminUITileDataProtocol*`, `GZAdminUITileExecution*`, `GZAdminUIBackendClient`, `GZAdminUIHost`, and `GZAdminUIHost` helpers. The shared `Assets/` output remains a single directory. Native configure and `cmake --build build --target AllTests --parallel 4` passed. The bounded UI/security suites passed: `UIAuthManagerTests` 21, `GZAdminUIBackendClientTests` 52, `UIServerRuntimeTests` 28, `UITileExecutionPolicyTests` 5, `GarazykUICommandTests` 7, `UILabAuthTests` 21, `UILabIntegrationTests` 16, and `Phase2SecurityIntegrationTests` 36 (186 total, 0 failures). Source boundaries, link-time boundaries, namespace, recursive-setter, host-process-exit, NSID, literal-registration, skill-index, design-system, and `AdminUIAssetsSync` gates passed; the namespace check remained at 175 baselined classes with no new leaks. The required global `AllTests --gated=run` was started but interrupted after reaching `RepoAuthRepoTests`, with no final summary; it is not a pass. `test_static_files.sh` failed because the legacy `/explore` route returned 404, and `test_page_load.sh` failed because the same legacy HTML/CSS/JS/API resources were 404/undersized. Browser and visual smokes were attempted but both stopped at missing `npm:playwright@1.52.0` installation. These are named blockers for Phase 30 closeout; no service rollout or M3 work was started.
- **Post-merge integration evidence (2026-08-08):** after the WS08 M4.5 manifest merge (`313bc2b3`), a fresh configure and `cmake --build build --target AllTests --parallel 4` passed on `main`. The post-merge bounded UI suites passed 143/143 (including `UIServerRuntimeTests` 28, `GZAdminUIBackendClientTests` 52, `UIAuthManagerTests` 21, `UILabIntegrationTests` 16, `UILabAuthTests` 21, and `UITileExecutionPolicyTests` 5); `AdminUIAssetsSync`, source/link boundaries, namespace (175 baselined), safety, metadata, and documentation gates passed.
- **M2.6 closeout evidence (2026-08-11):** after rebuilding `AllTests`, `./build/tests/AllTests --gated=run` completed 5,004 tests with 0 failures in 506.708s. `scripts/admin_ui_browser_smoke_test.ts` passed against a live local binary topology (including CSP, session/CSRF, keyboard, accessibility, and Lab OAuth); `scripts/admin_ui_visual_smoke_test.ts` passed; `scripts/test/check_ui_design_system.sh` and `ctest --test-dir build -R AdminUIAssetsSync --output-on-failure` passed. The legacy static/page-load scripts remain retired rather than blockers.

### M2.6 historical blockers

- ~~A current replacement or retirement decision for the legacy `/explore`,
  `/css/explore.css`, `/js/ui.js`, and `/api/pds/accounts` checks.~~
  **Resolved (2026-08-09, maintainer chose retirement.)** All four endpoints
  were verified absent from `Garazyk/Sources/` — the admin UI moved off
  `kaszlak` to the former monolithic admin UI/`AdminUIServer`, and nothing registers those
  routes. The two scripts that tested them, `scripts/test/test_static_files.sh`
  and `scripts/test/test_page_load.sh`, were deleted. They were wired into
  nothing: not `ci.yml`, not CTest, not `scripts/test/run-tests.sh` (which
  invoked only `check_ui_design_system.sh`). Their coverage is superseded by
  `scripts/admin_ui_browser_smoke_test.ts` and
  `scripts/admin_ui_visual_smoke_test.ts`, which drive the real the former monolithic admin UI
  binary in a real browser, and by the `AdminUIAssetsSync` CTest, which
  compares asset inventories and SHA-256 hashes. `.agents/skills/garazyk-admin-ui`
  was updated to point at the live tests and at the post-M2.5/M2.6 source
  paths, several of which were still pre-extraction.
- ~~A worktree environment with the pinned Playwright npm dependency available
  for the browser and visual smoke scripts.~~ **Resolved (2026-08-11):** the
  pinned Chromium runtime was installed and both live browser smokes passed.

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

- the former monolithic admin UI links `ATProtoAdminUI`, `ATProtoTransport`, and `ATProtoCore`
  only — the dropped links to `ATProtoRuntime`, `ATProtoStorage`,
  `ATProtoServices`, `ATProtoSync`, and `ATProtoAppViewServer` are the
  measurable proof the extraction is real.
- All three gates pass; the namespace baseline shrinks rather than grows.
- Existing `UIServerRuntimeTests`, the browser and visual smoke tests, and
  `scripts/test/check_ui_design_system.sh` pass unchanged.
- No file under `Garazyk/Sources/` outside a pack names a service-specific UI
  symbol.

## M3. PLC pilot (campagnola)

Execution detail: [PLC service brief](service-admin-uis/plc.md).

### M3 status (2026-08-11)

**Complete.** The PLC pilot has a bounded snapshot, PLC-owned pack,
password-gated loopback listener, compatibility-host composition, and focused
tests; no other service rollout is in scope. Native configure/build, focused
PLC/Admin UI/auth/command/lifecycle tests, the local-network gated suite
(5,018 tests, 0 failures), browser smoke, asset/design gates, module/safety
gates, and the GNUstep/Linux container binary gate passed on 2026-08-11.

The smallest real surface: six routes (`plc-did`, `plc-log`, `plc-health`,
`plc-metrics`, `plc-list`, `plc-export`), a 103-line backend client, three
partials. Chosen because PLC has no admin credential today, which forces the
credential story into the open rather than letting it be inherited from the
PDS.

1. Introduce `GARAZYK_PLC_ADMIN_PASSWORD`. Fail closed when unset — the admin
   listener does not start, and the service logs why.
2. Add `GZPLCAdminUIPack` under `Garazyk/Sources/PLC/AdminUI/`.
3. Attach it to `PLCRuntimeComposite` as a third member alongside `server` and
   `syncEngine`. Add `--admin-ui-port` / `GARAZYK_PLC_ADMIN_UI_PORT`, bound to
   `127.0.0.1` unless explicitly overridden.
4. The embedded pack reads the bounded in-process snapshot directly, so no
   internal protocol-listener token is minted or exposed to the browser.
5. Register the new test suite in **both** places: re-run
   `cmake -S . -B build` so the glob picks the file up, and add the class to
   the `testClasses` array in `Garazyk/Tests/test_main.m`. The registration
   audit fails on a mismatch in either direction.

**Acceptance:** `campagnola` serves the PLC UI; the former monolithic admin UI still serves an
identical one from the same pack; both run simultaneously without session
interference (M1.2) or worker starvation under concurrent load (M1.1);
`campagnola` refuses to expose the admin listener with no password set.

### M3 closeout evidence

- **GNUstep/Linux binary build (2026-08-11):** OrbStack Docker 29.4.0 built
  `garazyk-gnustep` successfully with `docker build -f
  docker/Dockerfile.gnustep -t garazyk-gnustep .`. The first build exposed a
  GNUstep-only `dispatch_queue_t` ownership error in the new snapshot adapter;
  it was corrected using the existing `PDS_DISPATCH_QUEUE_STRONG` portability
  macro. The rebuilt image was inspected as
  `sha256:6c99e5d86c7d4b546dace4331795990dff91b9b189cd79207e588ee886a5fa49`,
  and `campagnola serve --help` passed inside that image.

## M4. Roll out the remaining services

The governed inventory and service-specific acceptance gates are in the
[service brief index](service-admin-uis/README.md). Roll out in dependency
order so existing packs establish the pattern before new surfaces and the PDS
lands last: `zuk` (relay convergence), `beskid` (edge cache), `mikrus` (link
index), `syrena` (AppView), `syrena-chat` (chat), `germ` (E2EE mailbox),
`jelcz` (video), then `kaszlak` (PDS, Ozone, Security, Data Explorer, MST,
Lab).

### M4 status (2026-08-20)

**Chat, AppView, Relay, and PDS briefs closed 2026-08-12** (headline stats +
lock/unlock + `admin-ui:chat-smoke`; Exceptions/Probe/Actor dig; live-event
inspector fields; PDS snapshot + visual/browser smoke including 200% zoom).
Mikrus and Beskid brief acceptance closed 2026-08-20 (`0a5657205`) with
fixture-backed metric reconciliation, bounded pagination/error polling,
credential/body/path redaction, human pack titles, and authenticated polling
during concurrent index/cache mutation. The remaining M4 surface is Video
(`jelcz`) CA-aware Distribution/Jobs UX (in progress; see
[video brief](service-admin-uis/video.md)).
Ozone remains embed-only if a standalone Ozone binary
appears.

| Binary | Execution brief |
| --- | --- |
| `zuk` | [Relay](service-admin-uis/relay.md) |
| `beskid` | [Beskid](service-admin-uis/beskid.md) |
| `mikrus` | [Mikrus](service-admin-uis/mikrus.md) |
| `syrena` | [AppView](service-admin-uis/appview.md) |
| `syrena-chat` | [Chat](service-admin-uis/chat.md) |
| `germ` | [Germ](service-admin-uis/germ.md) |
| `jelcz` | [Video](service-admin-uis/video.md) |
| `kaszlak` | [PDS](service-admin-uis/pds.md) |

`jelcz` retains a narrow PDS client for the cross-service calls in
`UIBackendClient+Video`. `kaszlak` composes six packs — the pack protocol
should absorb this without special-casing, and if it does not, that is a
defect in M2.1 rather than a reason to special-case `kaszlak`.

**Acceptance:** every service in the brief index serves its own UI;
the former monolithic admin UI still works; browser requests use service-scoped sessions rather
than manually attached auth tokens; double maintenance is confined to this
milestone.

## M5. Retire the monolithic admin UI

**Complete (2026-08-12).** The standalone admin binary, Overview/Connections,
and `serviceProbeSpecifications` are gone. Embedded hosts use
`GARAZYK_ADMIN_UI_*` / per-service `*_ADMIN_UI_*` env; schemat/hamownia treat
`ui` as the PDS admin listener on `:2590`; peer switcher renders configured
`Name=URL` links only.

1. Delete the binary, its CMake target, `docker/Dockerfile.ui`, and the
   `project.yml` entry.
2. Delete the Overview and Connections packs, their renderers and partials,
   and `serviceProbeSpecifications`.
3. Add the peer switcher: configured links to sibling UIs, no polling, no
   credentials, no health claims about processes it cannot observe.
4. Update the 26 files enumerated in Current evidence. `packages/schemat`'s
   `WebClientTopology` dropped the retired admin build preset; Lab OAuth
   scenarios target the PDS admin listener.
5. Update `Garazyk/Sources/Admin/ADMINUI_ARCHITECTURE.md`,
   `.agents/skills/garazyk-admin-ui`, and `CLAUDE.md`'s service table.

**Acceptance:** the retired binary name and its pre-migration env-var prefix
are absent outside `docs/adr/` and run artifacts under
`scripts/scenarios/reports/`; `deno task check && deno task lint && deno task
test` passes; the scenario suite runs against the per-service UIs.

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
served by both the former monolithic admin UI and its own binary until M5. This is the cost of
keeping the tree green throughout, and it is bounded by finishing M4.

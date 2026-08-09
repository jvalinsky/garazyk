---
phase: 30
title: Extract ATProtoAdminUI and invert route registration (WS11 M2)
status: in-progress
agent: worker
depends_on: []
---

# Phase 30: Extract ATProtoAdminUI and invert route registration (WS11 M2)

## Mission

Turn `Garazyk/Sources/AdminUIServer/` — 6,152 lines that belong to no static
library and compile straight into the `garazyk-ui` executable — into an
`ATProtoAdminUI` library that depends on `ATProtoTransport` and `ATProtoCore`
only, and replace its hardcoded per-service route registration with a pack
protocol that services implement.

**This phase touches no service binary.** Its acceptance gate is that
`garazyk-ui` is rebuilt as the library's first consumer, composing every pack,
and behaves identically. The extraction is proven by the existing application
before anything embeds. Embedding happens in a later phase (WS11 M3, the PLC
pilot).

## Read first

- [`docs/plans/workstreams/11-per-service-admin-uis.md`](../workstreams/11-per-service-admin-uis.md)
  — authoritative. If this prompt disagrees with it, the workstream wins and
  this prompt gets fixed. M2 is the milestone; M1 is already complete.
- [`docs/adr/0033-per-service-embedded-admin-uis.md`](../../adr/0033-per-service-embedded-admin-uis.md)
  — the decision and its binding constraints, especially the dependency
  restriction in §2 and the pack inversion in §3.
- [`docs/adr/0031-module-boundary-link-time-gate.md`](../../adr/0031-module-boundary-link-time-gate.md)
  — how the link-time gate resolves symbols; you are adding a module to it.
- `Garazyk/Sources/Admin/ADMINUI_ARCHITECTURE.md` — current architecture; must
  be updated by this phase, since it describes `garazyk-ui` as the only UI.
- `.agents/skills/garazyk-admin-ui` — design-system, auth-boundary, and
  accessibility rules for this surface. Load it before touching markup.
- Sources: `UIServerRuntime.m` (`-registerRoutes`), `UIServerRuntime+Private.h`,
  `UIBackendClient.{h,m}`, `UIBackendClient_Internal.h`, `UITemplateEngine.m`,
  `Assets/html/shell.html`, and `CMakeLists.txt` (the `add_executable(garazyk-ui …)`
  block, the `ADMIN_UI_ASSET_STAMP` block, and the `AdminUIAssetsSync` test).

## What is already correct — do not "fix" it

- **M1 landed and is available.** `HttpServer` takes a concurrency limit
  (`+serverWithHost:port:maxConcurrentRequests:`,
  `kHttpServerDefaultMaxConcurrentRequests`), and `UIAuthManager` derives
  service-scoped cookie names via `-initWithPassword:serviceIdentifier:`.
  Do not re-derive either. Admin listeners get a limit of 8, but the first one
  is created in M3, not here.
- **`UIAuthManager` sessions are already isolated between instances.** They
  live in a per-instance dictionary keyed by token hash. Two managers cannot
  authorize each other's tokens. The cookie scoping fixed browser-side
  collision, not privilege escalation — do not add a redundant identity check.
- **`UITemplateEngine` already supports array sections** (`{{#key}}…{{/key}}`
  over dictionary elements) and inverted sections. Composing the shell
  navigation from pack metadata is a template and context change. Do not
  write a new template engine.
- **The seams are already cut per service.** Ten `UIBackendClient+<Service>`
  categories and eleven `UIServerRuntime+<Service>Routes` categories exist.
  This phase relocates them; it does not re-split them.

## Slice 1 — Pack protocol and host

Define `GZAdminUIPack`: pack identifier, display name, sidebar sections, and a
route-registration entry point. Rename `UIServerRuntime` to `GZAdminUIHost` and
construct it with an array of packs, replacing the hardcoded
`registerPDSRoutes` … `registerMSTRoutes` sequence in `-registerRoutes`.

The host must not reference any service type. Mirror the existing
`XrpcRoutePackServiceBag` convention rather than inventing a second
composition idiom.

`kaszlak` will later compose six packs (pds, ozone, security, explorer, mst,
lab). If the protocol needs special-casing to absorb that, the protocol is
wrong — fix it here rather than special-casing `kaszlak` in M4.

## Slice 2 — Split the 49-declaration private header

`UIServerRuntime+Private.h` declares 49 renderers in one category. Shared
primitives (escaping, alerts, tables, empty and error states) move to the
library; per-service renderers move to their pack.

**This is the phase's largest mechanical risk.** Do one service at a time and
keep the tree green between each. Do not attempt all eleven route categories
in one commit.

`UIServerRuntime+Renderers.m` currently emits `-Wincomplete-implementation`
warnings for renderers declared but not defined in that category. Those are
pre-existing; note whether the split resolves them, and do not treat them as
new breakage.

## Slice 3 — Split the backend client

Transport primitives from `UIBackendClient_Internal.h`
(`performJSONRequestWithURL:…`, `performRequestWithURL:…`,
`performStringRequestWithURL:…`, `URLByAppendingPath:queryItems:baseURL:`,
`pathWithSegments:`) become the library's `GZAdminUIBackendClient`. The ten
`+<Service>` categories become pack-owned clients.

`-serviceProbeSpecifications` is Overview-only. Leave it with the Overview
pack; it is deleted in M5, not carried into the library.

Keep the blocking-call contract documented in `UIBackendClient_Internal.h`
verbatim — M3 depends on it being true.

## Slice 4 — Compose the shell

`Assets/html/shell.html` hardcodes twelve tabs and twelve panels. Render the
navigation from pack metadata instead.

Two navigation modes, one chrome: multi-section services keep the segment row;
single-surface services replace it with the service identity plus a peer
switcher, moving sections to the sidebar. Toolbar, sidebar, status bar, and
tokens stay identical across every service — one visual language, per the
`garazyk-admin-ui` skill. Preserve the ARIA tab/panel relationships, roving
`tabindex`, and heading order that phase 8 established.

The peer switcher's links are configured, not discovered: no polling, no
credentials, no health claims about processes it cannot observe. It may render
empty in this phase, since no sibling UI exists until M3.

## Slice 5 — Split and generalize the asset pipeline

Assets divide into library-owned (`css/`, `js/admin-ui.js`, shell and login
templates) and pack-owned (per-service partials, `js/lab.js`, `js/mst-viewer/`).

Three hardcoded paths must be updated, and all three will silently half-work
if missed:

1. `UITemplateEngine`'s test fallback, literally
   `Garazyk/Sources/AdminUIServer/Assets`, used when the bundle path is absent.
2. The `AdminUIAssetsSync` ctest, which passes
   `-DSOURCE_ASSETS=…/AdminUIServer/Assets`.
3. `scripts/admin-ui-build/generate_css_bundle.ts`, which regenerates the
   token and reset sections of `system.css`.

Turn the `ADMIN_UI_ASSET_STAMP` `add_custom_command` into a CMake function each
target can call. All binaries share `${CMAKE_BINARY_DIR}/bin/`, so one built
`Assets/` directory continues to serve every service — do not create six.

## Slice 6 — Register the library with all three gates

1. `scripts/dev/check_module_boundaries.sh` — declare `ATProtoAdminUI`'s
   dependencies as `ATProtoTransport ATProtoCore`, and give it a level (3).
2. `scripts/check_module_boundaries.sh` — the ADR 0031 link-time gate parses
   `CMakeLists.txt` directly, so it should follow automatically. Confirm the
   baseline still reports 0 leaks rather than assuming it.
3. `scripts/check_namespace.sh` — add `ATProtoAdminUI` to `MODULES`.

**The namespace trap, and the reason this slice cannot be deferred.** That gate
scans exactly the archives named in `MODULES`. `AdminUIServer/` is in none of
them today, which is why no `UI*` class appears in
`docs/namespace-baseline.txt`. Adding the library exposes roughly fifteen
`UI*` classes to the gate for the first time. Leaving them unprefixed either
grows a baseline that exists specifically to never grow, or — if you skip step
3 — silently exempts a whole library from the namespace policy.

So **rename `UI*` to `GZAdminUI*` inside this phase**, not after it. Done this
way the baseline shrinks rather than grows, which is a net contribution to
workstream 08 M5.3. Coordinate with that workstream before starting: it is
actively renaming classes across the tree (see Rules below).

`UITileDataProtocol` and `UITileExecutionPolicy` implement a DASL Web Tiles
slice and are a UI-host concern, so they belong in the library — but
workstream 10 is active and owns them. Consult it before moving those two
files.

## Rules

- **Establish your own test baseline before starting.** Run
  `./build/tests/AllTests --gated=run` on a clean build and record the number.
  No current full-suite figure is recorded for this phase: the run attempted
  on 2026-08-04 was stopped before it reported. Do not inherit a count from
  another phase file.
- **Run `git status` before every commit, and never fold two phases into one
  commit** (README rule, added 2026-07-17). This is not theoretical here: on
  2026-08-04, commit `7b51629f "refactor(namespace): prefix CID (WS08 M5.3
  batch 2h)"` swept six unrelated WS11 M1 source files into a 237-file
  namespace rename because two sessions shared one working tree. **Run this
  phase in its own git worktree.** WS08 M5.3 is still renaming classes and
  will collide with slice 6 otherwise.
- A phase agent updates plan state in the same change as its code, per
  [`../README.md`](../README.md).
- Match surrounding style; do not run clang-format over existing files.
- New test suites need both steps: re-run `cmake -S . -B build` so the glob
  picks the file up, **and** add the class to `testClasses` in
  `Garazyk/Tests/test_main.m`. The registration audit fails on a mismatch in
  either direction, so a renamed or removed suite needs its entry updated too.

## Acceptance gate

1. **`garazyk-ui` links `ATProtoAdminUI`, `ATProtoTransport`, and
   `ATProtoCore` only.** The dropped links to `ATProtoRuntime`,
   `ATProtoStorage`, `ATProtoServices`, `ATProtoSync`, and
   `ATProtoAppViewServer` are the measurable proof the extraction is real. An
   extraction that leaves those links in place has not happened.
2. All three gates pass, and `docs/namespace-baseline.txt` **shrinks**.
3. `scripts/dev/check_module_boundaries.sh .`,
   `scripts/check_module_boundaries.sh build`,
   `scripts/check_namespace.sh build`, and
   `scripts/check-recursive-setters.sh` all pass.
4. Existing suites pass unchanged: `UIServerRuntimeTests` (26),
   `UIAuthManagerTests` (21), `UILabIntegrationTests` (16), `UILabAuthTests`
   (21), `UIBackendClientTests` (52), `GarazykUICommandTests` (7),
   `UITileExecutionPolicyTests` (5), `Phase2SecurityIntegrationTests` (36).
   Counts are as of `92c21704`; they may legitimately rise, not fall.
5. `scripts/test/check_ui_design_system.sh`, `scripts/test/test_static_files.sh`,
   `scripts/test/test_page_load.sh`, and the browser/visual smoke tests pass.
6. `ctest --test-dir build --output-on-failure` passes, including
   `AdminUIAssetsSync`.
7. No file under `Garazyk/Sources/` outside a pack names a service-specific UI
   symbol.

`deno run -A scripts/docs/repo_docs.ts validate --internal-strict` passes on
current `main` after `scripts/docs/deno.json` was added to the root workspace;
keep that gate green.

## Out of scope

- Embedding a UI in any service binary. That is M3 (PLC pilot) and M4.
- Deleting `garazyk-ui`, dropping the Overview and Connections tabs, or
  touching `packages/schemat` / `packages/hamownia` / `docker/`. That is M5.
- Introducing `GARAZYK_PLC_ADMIN_PASSWORD` or any per-service credential.
  That is M3.
- Changing what any admin route does. This phase relocates code and inverts
  registration; behavior changes belong to their own slices.

## Progress

### 2026-08-05 — Setup and slice 1 complete

- Ran in its own worktree (`.claude/worktrees/phase-30-admin-ui-library-extraction`,
  branch `worktree-phase-30-admin-ui-library-extraction`), per the Rules. A
  parallel session was independently running the same phase in a sibling
  worktree (`phase-30-admin-ui-extraction`); confirmed with the user this is
  the same person in another window, not a collision to resolve.
- **Pre-existing, out-of-scope build break found and fixed first
  (commit `4b67065b`).** Local `main` (`92c21704`) did not compile on a true
  clean checkout: `Garazyk/Sources/App/PDSApplication.m` imports and
  instantiates `PDSPLCAccountOperationProvider` as a concrete class, but the
  tracked tree only had `Core/PDSPLCAccountOperationProvider.h` (the protocol
  introduced by `30139b0a`) — no concrete implementation was tracked in git.
  Root cause: an unanchored `plc/` `.gitignore` rule (meant for a root-level
  runtime database directory) matched `Garazyk/Sources/PLC/` case-insensitively
  on APFS, silently blackholing the concrete provider's `.h`/`.m` files, which
  existed correctly on disk in the primary working directory but were never
  tracked. Anchored the pattern to `/plc/` (matching the existing `/service/`
  entry) and tracked the two files as-is — no redesign needed, the
  implementation was already correct. This was invisible locally only because
  a stale on-disk copy masked it, and `92c21704` hadn't reached
  `origin`/CI yet to catch it there.
- **Full-suite baseline could not be established.** Three clean-build
  `./build/tests/AllTests --gated=run` attempts (one disk-exhausted, one with
  8.4GB free, one with a `--timeout 60` per-test cap) all died at ~14–15.5k
  lines of output in the same CLI-dispatcher test area
  (`PDSCLIDispatcherTests`/`PDSCLIOAuthCommandTests`), consuming 5–6GB of test
  scratch space each attempt regardless of starting disk headroom. This
  matches the "run attempted on 2026-08-04 was stopped before it reported"
  precedent this same Rules section already documents — a pre-existing,
  out-of-scope environmental limitation, not something introduced by this
  phase (all three attempts used the pristine gitignore-fix-only binary,
  before any slice-1 code existed). Cleaned ~8GB of orphaned per-test scratch
  directories from `TMPDIR` twice along the way (only entries confirmed older
  than a live process or explicitly approved by the user; left system/other-tool
  temp files alone). **Per-slice regression verification instead runs the
  eight acceptance-gate-named suites directly via `--filter <ClassName>
  --gated=run`**, which is fast, reliable under this environment's disk
  constraints, and directly measures the gate that matters.
- **Slice 1 done and verified.** `GZAdminUIPack` protocol added
  (`GZAdminUIPack.h`); `UIServerRuntime` renamed to `GZAdminUIHost`
  (`GZAdminUIHost.{h,m}`, `GZAdminUIHost+Private.h`, `git mv`'d); the
  hardcoded `registerPDSRoutes … registerMSTRoutes` sequence in
  `-registerRoutes` replaced with `for (Class packClass in self.packs)
  [packClass registerRoutesWithHost:self]`. Eleven thin pack classes added
  under `Packs/` (`GZAdminUIPDSPack` … `GZAdminUIMSTPack`), each a stateless
  class-side adapter delegating to the existing `registerXRoutes` instance
  method on the host — the real per-service code stays where it is until
  slices 2–3 move it into these same pack files. `GZAdminUIDefaultPacks()`
  (`GZAdminUIDefaultPacks.{h,m}`) is the one file allowed to name every
  service, used by `garazyk-ui`'s `main.m` and the three tests that construct
  a full-surface host (`UIServerRuntimeTests`, `UILabAuthTests`,
  `UILabIntegrationTests`); `GZAdminUIHost` itself holds no compile-time
  knowledge of any service. `CMakeLists.txt` updated in both the
  `garazyk-ui` executable's source list and `AllTests`' explicit admin-UI
  source list (not glob-covered).
  - Both `AllTests` and `garazyk-ui` build cleanly (only the pre-existing,
    expected `-Wincomplete-implementation` warnings noted in Slice 2's
    section — unrelated to this slice, unchanged by it).
  - All eight acceptance-gate suites pass with counts matching the recorded
    baseline exactly: `UIServerRuntimeTests` 26, `UIAuthManagerTests` 21,
    `UILabIntegrationTests` 16, `UILabAuthTests` 21, `UIBackendClientTests`
    52, `GarazykUICommandTests` 7, `UITileExecutionPolicyTests` 5,
    `Phase2SecurityIntegrationTests` 36 — 0 failures across all eight.
- **Slice 2 done (2026-08-08).** The eleven service renderer groups were moved one at a time into their corresponding `GZAdminUI<Pack>` implementations and committed independently, from Security (`661d8396`) through Ozone (`f32cc9b5`). `status` remains `in-progress` while slices 3–6 remain.

### 2026-08-08 — Slice 3 backend-client rename and pack relocation

- Renamed `UIBackendClient` and its internal header to `GZAdminUIBackendClient`; moved all ten service category pairs under `AdminUIServer/Packs/` and updated their category declarations, consumers, CMake source lists, test stubs, and registered test class. The PDS category retains `serviceProbeSpecifications`, which is required by the existing Overview surface and is not a shared transport primitive.
- Classified the seven untracked files inherited with this slice as migration scratch only: `rename_backend_clients.sh` performed the `git mv` loop; `move_probe.py` and `tmp_pds_inject.m` were incomplete relocation experiments; `GZAdminUIBackendClient+PDS_header.m`, `tmp_probe.m`, `tmp_probeurl.m`, and `tmp_spec.m` were extracted source fragments. None is a production source or test and none is included in CMake.
- Validation (2026-08-08): with Homebrew OpenSSL 3.6.3 restored, `cmake -S . -B build` and `cmake --build build --target garazyk-ui AllTests --parallel 4` passed. The registration audit passed. `GZAdminUIBackendClientTests` passed (52 tests, 0 failures) and `UIServerRuntimeTests` passed (26 tests, 0 failures), both with `--gated=run`. `git diff --check`, `scripts/test/check_ui_design_system.sh`, `scripts/dev/check_module_boundaries.sh .`, `scripts/check_module_boundaries.sh build` (0 current leaks, 0 baselined), `scripts/check_namespace.sh build` (214 baselined), and `scripts/check-recursive-setters.sh` passed. After integration with current `main`, `deno run -A scripts/docs/repo_docs.ts validate --internal-strict` passed. Browser smoke was not run for this backend-only slice. M2.1–M2.3 are complete; M2.4–M2.6 remain.

### 2026-08-08 — Slice 4 composable shell implementation awaiting native verification

- `GZAdminUIPack.sidebarSections` now supplies ordered, presentation-only `tabIdentifier`/`displayName` metadata. The PDS pack owns its existing Overview, Connections, and PDS panels; the other shared-shell packs each own their existing tab; Lab remains absent because it owns a dedicated OAuth shell.
- `GZAdminUIHost` flattens pack metadata in composition order and renders tabs through `shell.html`. The multi-section/default composition retains the segmented header and all existing static panels. A one-section composition uses a sidebar tablist, service identity, and an intentionally empty peer-switcher. The peer switcher does not discover or poll peers, carry credentials, or claim peer health.
- `admin-ui.js` now uses one `.ui-tab` selector for both header and sidebar tabs, preserving tab/panel ARIA relations and roving `tabindex`. `system.css` adds only the shell/sidebar rules required for this layout; M2.5 still owns asset relocation and CMake pipeline changes.
- Added `UIServerRuntimeTests` coverage for all twelve default tabs in their pre-extraction visual order and relay-only sidebar/empty-peer rendering. Initial test execution caught two test defects (an XCTest macro comma expansion and a missing concrete `UIAuthManager` import), then the default-composition assertion caught an actual navigation-order regression: the default pack array had MST after Chat and Video while the existing shell displayed it before them. Restored the prior visual order without adding host service knowledge. After initializing the absent `vendor/secp256k1` submodule in this worktree, `cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug`, `cmake --build build --target AllTests --parallel 4`, and `./build/tests/AllTests --filter UIServerRuntimeTests --gated=run` passed (28 tests, 0 failures). `node --check Garazyk/Sources/AdminUIServer/Assets/js/admin-ui.js`, `git diff --check`, `scripts/dev/check_module_boundaries.sh .`, `scripts/check_module_boundaries.sh build` (0 current leaks, 0 baselined), `scripts/check-recursive-setters.sh`, and `scripts/check_no_host_process_exit.sh` passed. `scripts/test/check_ui_design_system.sh` is blocked by absent `rg`; `scripts/test/test_static_files.sh` continues to fail against the unrelated stale `/explore` endpoint (404) and left a server that was force-stopped. M2.4 is complete; M2.5–M2.6 remain.

### 2026-08-08 — Slice 5 asset ownership and shared build output

- Library-owned CSS, shell/login/demo templates, and shared JavaScript moved to
  `Assets/library/`; pack-owned partials and `lab.js`/`mst-viewer/` moved to
  `Assets/packs/<pack>/`. The source split is overlaid into one shared
  `${CMAKE_BINARY_DIR}/bin/Assets/` directory, preserving existing `/css/`,
  `/js/`, and template URLs.
- `ADMIN_UI_ASSET_STAMP` is now produced by reusable
  `add_admin_ui_assets(<target>)`; future service targets can depend on the
  same `admin-ui-assets` target without creating per-service output trees.
  `UITemplateEngine` searches library and pack template roots in its test
  fallback, `AdminUIAssetsSync` verifies the flattened inventory and hashes,
  and `generate_css_bundle.ts` follows `Assets/library/css/`.
- Verification: `cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug`,
  `cmake --build build --target AllTests --parallel 4`,
  `UIServerRuntimeTests` (28/28), `GZAdminUIBackendClientTests` (52/52),
  `AdminUIAssetsSync`, CSS bundle drift, JavaScript syntax,
  `check_ui_design_system.sh`, and `git diff --check` passed. The required
  full-suite baseline before edits returned exit 1; its redirected rerun was
  intentionally interrupted after 11m43s without a final summary.
  `test_static_files.sh` and
  `test_page_load.sh` fail on their stale `/explore` and legacy resource/API
  checks (404), unrelated to the asset relocation. M2.5 is complete; M2.6
  remains.

### 2026-08-08 — Slice 6 library registration and closeout evidence

- `ATProtoAdminUI` is now a static library with only `ATProtoTransport` and
  `ATProtoCore` dependencies. `garazyk-ui` links that library with those two
  targets and its small CLI parser source; it no longer links Runtime,
  Storage, Services, Sync, or AppViewServer. The Transport rate limiter's
  fallback database configuration is local so this narrowed consumer does not
  pull a Storage symbol across the boundary.
- All exposed Admin UI classes and helpers use the `GZAdminUI` prefix. Tile
  protocol and execution-policy exports were renamed in coordination with
  the existing WS10 tests, while the old header filenames and shared asset
  directory remain for compatibility with the current source layout. Admin
  route categories now compile from `AdminUIServer/Packs/`, and the
  post-WS08 HTTP handoff uses `ATProtoHttp*` names without aliases.
- Source boundary, link-time boundary, namespace, recursive-setter,
  host-process-exit, NSID, literal-registration, skill-index, design-system,
  asset-sync, native configure, and native `AllTests` build gates passed.
  The eight bounded UI/security suites passed with 186 tests and 0 failures.
- The full `./build/tests/AllTests --gated=run` run was started, reached
  `RepoAuthRepoTests`, and was interrupted after no final summary was emitted;
  its result is skipped/interrupted, not passing. `test_static_files.sh` and
  `test_page_load.sh` failed on the stale `/explore` and legacy resource/API
  checks. Browser and visual smoke attempts were blocked before execution by
  the missing `npm:playwright@1.52.0` dependency. Because these required
  acceptance checks are not green, Phase 30 remains `in-progress` and is not
  marked complete.

### 2026-08-08 — Wave integration

- M2.5/M2.6 changes are integrated on `main` (`bc427a13` and `8b45c6d9`), and
  WS08 M4.5 is integrated as `313bc2b3`. A fresh configure and native
  `AllTests` build passed after the manifest migration.
- Post-merge bounded UI suites passed 143/143; `AdminUIAssetsSync`, module,
  namespace, safety, metadata, and documentation gates passed.
- The full gated suite remains incomplete; stale `/explore` static/page-load
  checks and the missing pinned Playwright dependency remain named acceptance
  blockers. Phase 30 remains `in-progress`; M3 was not started.

## On completion

When the named blockers are resolved, record the commit hashes and measured
full-suite result in WS11 M2's acceptance section, set `status: complete` here,
and add phase 30 to the index table in [`../README.md`](README.md). This slice
does not claim completion while the acceptance checks above remain blocked.

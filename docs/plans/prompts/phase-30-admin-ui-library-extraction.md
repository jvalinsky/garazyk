---
phase: 30
title: Extract ATProtoAdminUI and invert route registration (WS11 M2)
status: pending
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

Note that `deno run -A scripts/docs/repo_docs.ts validate --internal-strict`
and `scripts/docs/doc-coverage.ts` currently fail for an unrelated reason —
`scripts/docs/deno.json` is not a member of the root workspace. If that is
still true when you run, report it rather than treating it as your breakage.

## Out of scope

- Embedding a UI in any service binary. That is M3 (PLC pilot) and M4.
- Deleting `garazyk-ui`, dropping the Overview and Connections tabs, or
  touching `packages/schemat` / `packages/hamownia` / `docker/`. That is M5.
- Introducing `GARAZYK_PLC_ADMIN_PASSWORD` or any per-service credential.
  That is M3.
- Changing what any admin route does. This phase relocates code and inverts
  registration; behavior changes belong to their own slices.

## On completion

Record commit hashes and the measured full-suite result in WS11 M2's
acceptance section, set `status: complete` here, and add phase 30 to the index
table in [`../README.md`](README.md).

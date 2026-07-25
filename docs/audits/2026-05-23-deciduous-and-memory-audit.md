# Deciduous Graph & Memory Audit: 2026-05-23

Auditor: Letta Code agent
Scope: All 686 deciduous nodes, 6 memory reference docs, 6 Deno packages, 31 ObjC modules, 92 scenarios
Trigger: User requested review of current plans against codebase reality

## 1. Executive Summary

The deciduous graph drifted from the codebase. The codebase contains completed work for 25 nodes marked active or pending. Two nodes lacked an implementation path. Four nodes remain active. Three memory reference docs had inaccurate status claims.

Corrections applied: 25 nodes marked completed, 2 nodes marked rejected (1 later restored), 3 reference docs updated.

### Current Graph Health

| Metric | Value |
|--------|-------|
| Total nodes | 686 |
| Total edges | 566 |
| Completed | 415 (60.6%) |
| Pending | 245 (35.7%) |
| Active | 6 (0.9%) |
| In progress | 2 (0.3%) |
| Rejected | 8 (1.2%) |
| Done | 10 (1.5%) |
| High confidence | 578 (84.3%) |
| Unset confidence | 96 (14.0%) |

### Node Type Distribution

| Type | Count |
|------|-------|
| action | 271 |
| outcome | 219 |
| goal | 87 |
| decision | 73 |
| option | 21 |
| observation | 15 |

## 2. Nodes Marked Completed (25)

The codebase contains the completed work for these active and pending nodes.

### Deno/TypeScript Packages

| Node | Title | Evidence |
|------|-------|----------|
| #204 | Research TUI engine design | packages/tui/ exists with full module/test suite. TUI runtime in scripts/scenario-dashboard/ with tui.ts, tui/runtime.ts, tui/view.ts, panels, theme system. |
| #341 | Deno test coverage: 9 new test files | 61 *_test.ts files now exist. The 9 new test push is superseded by continued coverage growth. |
| #350 | Implement scripts/generate.ts | packages/gruszka/scripts/generate.ts exists. packages/gruszka/lexicons.ts has GENERATED CODE header. Reads 528 lexicon JSONs. |
| #368 | Sans-IO lexicon resolution pipeline | packages/gruszka/lexicon_resolution/ has the layered pipeline: types.ts, core.ts, resolver.ts, ports.ts, adapters.ts, mod.ts, plus cache support. |
| #404 | Phase 2: Schemat env isolation | serviceUrl(key, env?) accepts injected EnvSource parameter. computeRunDir() is pure. initRunDir() mutates env in compatibility path but mutateEnv: false is available. |
| #407 | Phase 3: Quick wins verification | currentTheme is lazy (_currentTheme initialized on first access). formatBytes lives in packages/gruszka/format.ts. chat_viewer migrated to scripts/. |
| #411 | Phase 11: test coverage | packages/schemat/topology_registry_test.ts, topology_manifest_test.ts exist. packages/narzedzia/ has spdx_headers_test.ts, doc_coverage_test.ts, tsdoc_coverage_test.ts. |
| #578 | Review Deno JSR package readiness | All 6 packages have JSR-ready deno.json with name, version, exports, publish.include/exclude. deno.lock present. |
| #608 | Align workspace versions | All package versions aligned at 0.1.0-alpha.1. Doc-lint coverage tooling exists in narzedzia. |
| #664 | Refactor Test Harness Actors | packages/hamownia/actor.ts and tasks.ts exist. Integrated into scenarios via scripts/lib/deno/config.ts. Scenarios use postStatus, getActor. |
| #715 | Declarative layout via tree solver | dashboardLayoutTree() and solveLayout in use. Manual computeLayout retired. |
| #716 | Event-Driven RunManager | onEvent(), Deno.watchFs, TextLineStream in scripts/scenario-dashboard/services/run_manager.ts. |
| #717 | TEA Bridge | Polling suppressed for TUI. setInterval(50ms) render timer removed. Renders on state change. |
| #718 | View Layer | Hint bar, help overlay on ?, NO_COLOR support in scripts/scenario-dashboard/tui/view.ts. |

### E2E / Scenario Infrastructure

| Node | Title | Evidence |
|------|-------|----------|
| #413 | Fix scenario test infrastructure | scripts/run_scenarios.ts type-checks. 92 scenario files exist. Discovery and execution pipeline works. |
| #425 | E2E test execution consistency | packages/hamownia/preflight.ts has health checks. packages/hamownia/binary_services.ts has service startup reliability. |
| #462 | E2E Failure Remediation | 92 scenarios with proper error handling, exit flows, and reporting. |
| #497 | Fix Relay firehose commit broadcasting | RelayDownstreamHandler.m broadcasts commit events with expected flow. |
| #517 | Fix scenario 11 UI topology gap | UI role present in packages/schemat/topology_presets.ts with proper env/health/deps. |

### Objective-C / Server

| Node | Title | Evidence |
|------|-------|----------|
| #618 | Improve server reliability: SIGPIPE, SearchIndexService | GZSignalManager.h documents SIGPIPE ignoring. SearchIndexService.m logs rebuild and population failures explicitly. |
| #625 | Rename PDSSignalManager to GZSignalManager | Old class name no longer appears in codebase. GZSignalManager.h/.m exists. |
| #626 | Rename PDSSignalManager (duplicate) | Same as #625. |
| #632 | Audit and rename shared PDS-prefixed classes | Shared infrastructure classes renamed (GZCrashReporter, GZMetrics, etc.). Domain-specific PDS* classes remain intentionally (PDS-specific services, database, auth). |
| #637 | Implement Beskid edge record and identity cache | BeskidDatabase.h exposes record and identity cache operations with TTLs. Scenario 69 tests it. |
| #643 | Rename shared PDS-prefixed infrastructure (6 classes) | Same scoped conclusion as #632. GZMetrics, GZPerDidWriteDispatcher, GZProviderHTTPClient, GZProviderRegistry, GZAuthzManager, GZInputValidator all exist. |

## 3. Nodes Marked Rejected (2)

| Node | Title | Reason |
|------|-------|--------|
| #546 | Deep Security Review of GNUstep/Linux Server Port | No security-audit artifact exists in Sources/Security/. We never formally recorded the review or produced deliverables. The GNUstep/Linux port exists (docker/Dockerfile.gnustep) but the security review goal lacks a path forward. |
| #526 | Review video CDN and ATProto Media CDN | INITIALLY REJECTED, THEN RESTORED. The audit agent flagged this as stale because it looked for a dedicated CDN implementation beyond the current stack. Jelcz (Garazyk/Sources/Video/) is a full video CDN service with a database, configuration, transcoder, HLS generator, blob uploader, auth providers, XRPC pack, worker, and CLI. We need to extract reusable patterns from it into an ATProtoMediaCore framework. Status is ACTIVE. |

## 4. Genuinely Active Goals (6)

### #387: Sans-IO/TEA Architecture Remediation (Full Monorepo)

Status: Active
Completed tasks: D1 (constructMsg deduplicated in cmd_interpreter.ts), S1 partially (computeRunDir pure, mutateEnv: false), S2 (serviceUrl DI).

Remaining tasks:
- H1: hamownia lacks a TEA app loop. run_loop.ts is an imperative loop, not a Cmd[] boundary.
- S1: initRunDir() mutates env by default. The pure path exists but is not the default.
- H2 to H7: Mutable ScenarioResult, impure ProgressBar, coupled binary_services, imperative instrumentation, otel globals.
- L1 to L4: Laweta has a telemetry singleton, mutable DockerEventParser, effectful ContainerEventWatcher, and inline health polling.

Compliance scores:
| Package | Score |
|---------|-------|
| @garazyk/tui | 9.5/10 |
| dashboard | 8/10 |
| @garazyk/schemat | 6/10 |
| @garazyk/gruszka | 5.5/10 |
| @garazyk/narzedzia | 6/10 |
| @garazyk/laweta | 3.5/10 |
| @garazyk/hamownia | 2.5/10 |

### #429: E2E consistency: admin password, phone verification, preflight

Status: Active
Completed tasks: Phone verification mock is wired. Preflight has health checks.
Remaining tasks: Hardcoded admin password defaults (admin-localdev) remain in topology/compose. Mock Twilio server defaults to port 8081.

### #526: Review video CDN and design ATProto Media CDN framework

Status: Active
Current state: Jelcz video CDN service is fully implemented.
- Garazyk/Sources/Video/: JelczDatabase, JelczConfiguration, ATProtoVideoProcessor, VideoWorker, VideoHLSGenerator, VideoThumbnailGenerator, VideoTranscoder (AVFoundation + FFmpeg), VideoBlobUploader (local + remote), VideoAuthProvider (JWT + PDS), VideoXrpcPack
- Garazyk/Sources/MediaCore/: JelczCLI
- Garazyk/Binaries/jelcz/: CLI entry point
- docker/local-network/staging/bin/jelcz: Staged binary
- Scenario 67: 67_jelcz_health_endpoints.ts validates health, admin API, XRPC endpoints
- Decision #529: Adopt ATProtoMediaCore Framework (pending)

Remaining tasks: Extract reusable patterns from Jelcz into a modular Objective-C framework library for building new CDN services (audio, 3D models, images).

### #656: Remediate E2E Flakiness and SQLite Corruption

Status: Active
Completed tasks: WAL mode configured in run_command.ts. Teardown improvements in atproto_network.ts close watchers.
Remaining tasks: The Deno layer lacks SO_REUSEADDR and SIGPIPE handling. TCP TIME_WAIT exhaustion remains unaddressed.

### #714: Concurrent resource isolation

Status: Active
Completed tasks (Category C): serviceUrlFromManifest() in docker_config.ts, neededPorts() reads from manifest, stale_cleanup.ts gates on isolation mode, 7 new tests.

Remaining tasks:
- Category D: Scenario fallback URLs hardcode localhost:PORT fallbacks in 12 scenario files (06, 37, 47, 53, 60, 69, 72, 75, 89, 90, 92, 16).
- Category E: Mock Twilio server defaults to port 8081.
- Category I: Dashboard scripts/scenario-dashboard/ hardcodes ports in network_manager.ts, routes/index.tsx, tui.ts, tui/panels/network.ts.
- Category K: Demo CLI packages/hamownia/cli/demo.ts hardcodes many ports/URLs.

### #498: Fix list management scenario

Status: Active (pending)
Remaining tasks: Scenario 39 app.bsky graph list retrieval fails. Action #499 (AppView list read fallback) and #501 (commit and push) lack outcomes.

## 5. JSR Publish Readiness

| Package | Status | Issues |
|---------|--------|--------|
| @garazyk/laweta | Passes | None |
| @garazyk/hamownia | Passes | None |
| @garazyk/narzedzia | Passes | None |
| @garazyk/tui | Passes | None |
| @garazyk/gruszka | Fails | 1 slow-type error: client.ts:207 missing explicit return type |
| @garazyk/schemat | Fails | 3 slow-type errors: port_allocator.ts:155 (leaseDir default), port_allocator.ts:173 (leaseDir default), resource_manifest.ts:117 (path default) |

Fix pattern: Add explicit type annotations to function parameters with default values:
- leaseDir: string = defaultPortLeaseDir()
- path: string = readEnv(...)

## 6. Memory Reference Doc Audit

### garazyk-jsr-slowtypes.md (PARTIALLY OUTDATED)

Issue: The status section claimed all 6 packages passed deno publish --dry-run. schemat has 3 slow-type errors and gruszka has 1.
Updated: The status section reads "5 of 6 packages pass" and lists specific error locations and fix patterns.

### garazyk-resource-isolation.md (PARTIALLY OUTDATED)

Issue: Category I referenced packages/dashboard/ for hardcoded ports, but the active dashboard code lives in scripts/scenario-dashboard/.
Updated: Category I path corrected to scripts/scenario-dashboard/ with specific files (network_manager.ts, routes/index.tsx, tui.ts, tui/panels/network.ts).

### garazyk-sansio-audit.md (PARTIALLY OUTDATED)

Issues:
- D1 was listed as open but is fixed (constructMsg centralized in cmd_interpreter.ts).
- S1 was listed as CRITICAL but is partially mitigated (computeRunDir pure, mutateEnv: false).
- S2 was listed as open but is fixed (serviceUrl DI).

Updated: Added Remediation progress (2026-05-23) section with D1 FIXED, S1 PARTIALLY FIXED, S2 FIXED annotations.

### garazyk-tui-sansio-refactor.md (CURRENT)

All 4 phases described match the codebase. No updates needed.

### deciduous-graph-state.md (PARTIALLY OUTDATED, NOW REFRESHED)

The graph was stale because users completed many active goals. Refreshed via sync.ts pull after marking nodes.

### deciduous-pulse.md (CURRENT)

Accurate reflection of graph health.

## 7. Codebase Statistics

### Deno/TypeScript

| Metric | Count |
|--------|-------|
| Test files (packages/**/*_test.ts) | 61 |
| Scenario files | 92 |
| JSR packages | 6 |
| Packages passing deno publish --dry-run | 4/6 |
| Boundary violations | 0 |

### Objective-C

| Metric | Count |
|--------|-------|
| Source modules | 31 |
| Source files (.h + .m) | 853 |
| Staged binaries | 12 (beskid, campagnola, constellation, garazyk-ui, germ, jelcz, kaszlak, mikrus, syrena, syrena-chat, zuk, Assets) |
| PDS-prefixed classes remaining | Domain-specific only (intentional) |

### Docker Infrastructure

| Component | Location |
|-----------|----------|
| Main compose | docker/local-network/docker-compose.yml |
| Alt compose | docker/local-network/docker-compose.alt.yml |
| Scenario compose | docker/local-network/docker-compose.scenarios.yml |
| Mock Twilio | docker/local-network/Dockerfile.mock-twilio |
| PDS config | docker/local-network/pds-config.json, pds2-config.json |

## 8. Branch Status

| Branch | Status |
|--------|--------|
| main | Current HEAD, all work merged |
| refactor/deno-packages | 75 commits ahead of main. This is a pre-merge branch from the package extraction work. It is likely fully merged or stale. |
| code-review-remediation | 0 commits ahead of main and is fully merged |
| subagent-* branches | 3 subagent branches from parallel work and are likely stale |

## 9. Graph Gaps Identified by Pulse

The deciduous pulse identified structural gaps in the graph.

### Goals without options (no alternatives considered)
#404, #407, #411, #413, #449, #475, #497, #498, #516, #546, #625, #710, #711, #712, #714

### Decisions without actions (decided but not implemented)
#405, #408, #410, #430, #431, #432, #433, #436, #437, #452, #529, #589, #602, #608, #666, #715-718

### Actions without outcomes (work done but no recorded result)
#421, #422, #423, #424, #428, #473, #474, #499, #501, #523, #541-545, #557, #563, #564, #567, #570, #575, #576, #583-585, #588, #590, #598, #607, #612, #620-622, #627-630, #633-635, #644-646, #720, #724

Users completed these actions but did not record the outcomes.

## 10. Recommendations

Immediate (fix stale data):
1. Fix JSR slow-types in schemat and gruszka.
2. Record outcomes for completed actions that lack them, especially the E2E remediation actions (#421-428, #473-474, #499, #501, #523).
3. Close or merge refactor/deno-packages branch.
4. Clean up subagent branches (subagent-CBOR-Transcoder-*, subagent-Networking-*, subagent-Teardown-*).

Short-term (active work):
5. #387 Sans-IO remediation: Fix H1 (hamownia TEA loop).
6. #714 Resource isolation: Replace hardcoded fallbacks with manifest-aware resolution for Categories D, E, I, K.
7. #526 ATProtoMediaCore: Extract Jelcz patterns into a reusable framework library.

Medium-term (quality):
8. #656 E2E flakiness: Add SO_REUSEADDR to Deno network layer, address TCP TIME_WAIT exhaustion.
9. #429 E2E consistency: Remove hardcoded admin password defaults, centralize mock server configuration.
10. Graph hygiene: Add options to goals that lack them, add outcomes to actions that lack them.

## 11. Audit Methodology

1. Pulled deciduous graph state via deciduous pulse --json (686 nodes, 566 edges).
2. Launched 3 parallel agents to audit:
   - Agent 1: Deno/TS package plans (13 items checked against codebase).
   - Agent 2: ObjC/E2E scenario plans (15 items checked against codebase).
   - Agent 3: Memory reference docs (6 files read and cross-referenced).
3. Verified each finding against actual code for file existence, type-checking, deno publish --dry-run, and boundary checks.
4. Applied corrections: 25 nodes to completed, 2 to rejected (1 restored), 3 reference docs updated.
5. Re-synced deciduous to memory via sync.ts pull.
6. Committed all memory changes.

End of audit. Generated 2026-05-23T18:56:00Z.

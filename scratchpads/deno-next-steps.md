# Deno Packages: Next Steps Plan

> Generated: 2026-05-20 · Updated after completing Phases 1–10, 12 (Tier 2 schemat)

---

## 1. Current State Summary

| Package | Tests | JSR Publish | Sans-IO | Untested Source Files |
|---------|-------|-------------|---------|-----------------------|
| `gruszka` | 35 | ✅ Clean | ✅ Pure (chat_viewer moved to scripts/) | 20 (mostly generated clients) |
| `schemat` | 159 | ✅ Clean | ✅ Pure (DI-enabled docker_config + logging) | 8 |
| `laweta` | 63 | ✅ Clean | ✅ HOME deferred | 6 |
| `hamownia` | 73 | ✅ Clean | ✅ Pure (progress fixed) | 28 (mostly CLI/infra) |
| `narzedzia` | 11 | ✅ Clean | ✅ Pure | 10 |
| `tui` | 227 | ✅ Clean | ✅ Pure (currentTheme lazy-init via getCurrentTheme()) | 3 |

**Total: 2948 package tests + 156 dashboard tests = 3104 passing (1 dashboard test needs --allow-ffi).**
**All 6 packages pass `deno publish --dry-run`. Boundary check passes with zero violations.**

### Completed Phases (1–8)

| Phase | What was done |
|-------|--------------|
| 1 (A1, A2) | ProgressBar.render() returns string, run_loop.ts owns stdout, 8 progress tests |
| 2 (A3) | tui/mod.ts pure root, @garazyk/tui/runtime subpath, explicit named exports |
| 3 (A7) | DockerApiClientOptions with endpoint/dockerHost/homeDir, HOME deferred |
| 4 (E) | Stale fuzz-command export removed, addCname() return type fixed |
| 5 (A8) | 53-variant Msg union → 7 sub-unions + per-slice reducers |
| 6 (F) | 17 new tests (11 boundary_check, 6 topology_types) |
| 7 | All 6 packages JSR-ready. Stale hamownia exports removed, npm:playwright@1.52.0, tui LICENSE, mock_twilio slow-type |
| 8 | smoke_command.ts moved narzedzia→hamownia, boundary check zero violations |
| 12 | **Phase 2: Schemat env isolation.** docker_config.ts: EnvSource/ProcessInfo/FileSystemOps/ClockSource DI interfaces, computeRunDir pure function, initRunDir with injectable fs/env. logging.ts: Logger interface, ConsoleLogger class, createLogger factory. Tests: 10→25 docker_config, 14→24 logging. All 159 schemat tests pass, boundary clean, publish dry-run clean. |
| 9 | **Phase 3a: tui currentTheme lazy init.** Already implemented — `getCurrentTheme()` uses `_currentTheme = undefined` + lazy resolution on first access. `COLORS` uses getters. No module-load env read. |
| 10 | **Phase 3b: Deduplicate formatBytes.** Already implemented — `gruszka/format.ts` has unified loop-based impl; `laweta/format.ts` and `hamownia/format.ts` re-export from `@garazyk/gruszka/format.ts`. |

### Also completed (A4)

| A4 | **Move chat_viewer.ts out of gruszka.** Already done — `scripts/chat_viewer.ts` contains all chat viewer code; `packages/gruszka/` has no chat_viewer references. |

---

## 2. Remaining Issues

### P1. ✅ tui `currentTheme` module-load env read — RESOLVED

`tui/theme.ts` already uses lazy initialization: `_currentTheme` starts as `undefined`, `getCurrentTheme()` resolves on first call, `COLORS` uses getters. Importing `@garazyk/tui` no longer triggers `Deno.env.get`.

### P2. ✅ Duplicate `formatBytes` in laweta and hamownia — RESOLVED

Unified in `gruszka/format.ts` (loop-based, TiB support). `laweta/format.ts` and `hamownia/format.ts` re-export from `@garazyk/gruszka/format.ts`. Tests in `gruszka/format_test.ts`.

### P3. Deferred Architecture Plan Items

| Item | Status | Why deferred |
|------|--------|-------------|
| A5 — Generic TEA types | Deferred | No second consumer yet; dashboard's Cmd is runtime-specific |
| A6 — `Result<T, E>` type | Deferred | Useful but not blocking; can be added incrementally |

### P4. Test Coverage Gaps (by priority)

**Tier 1 — Pure logic, high value, easy to test:**

| File | Package | Exports | Why it matters |
|------|---------|---------|----------------|
| `laweta/format.ts` | laweta | `formatBytes()` | Pure function, 13 lines, used by docker_api + container_stats |
| `hamownia/format.ts` | hamownia | `formatBytes()` | Pure function, 16 lines, used by atproto_network + run_loop |
| `schemat/topology_registry.ts` | schemat | `isKnownServiceRole`, `roleEnvKey`, `defaultServiceName`, `defaultRolePort`, `validateRoleCapability`, `Cap`, `Role` constants | Pure validation/lookup, core source of truth |
| `schemat/topology_manifest.ts` | schemat | `parsePortMapping`, `sanitizeTopologyName`, `serviceNameForRole`, `publicUrlForRole`, `internalUrlForRole`, `roleToEnvKey` | Pure helpers, core manifest logic |
| `narzedzia/spdx_headers.ts` | narzedzia | `hasSpdx()`, `addSpdxHeader()` | Pure string functions, license tooling |
| `narzedzia/doc_coverage.ts` | narzedzia | `countDocumentation()`, `subsystemForPath()`, `classifyDoc()`, `pct()`, `summarize()` | Pure heuristics and path mapping |
| `narzedzia/tsdoc_coverage.ts` | narzedzia | `buildReport()` | Pure aggregation, core coverage logic |

**Tier 2 — Mostly pure, needs some env mocking:**

| File | Package | Exports | Why it matters |
|------|---------|---------|----------------|
| `laweta/telemetry.ts` | laweta | `withSpan`, `addSpanEvent`, `recordGauge`, `recordCounter`, `isOtelEnabled`, `setTelemetryTestHook` | Test hook system, OTel integration |
| `schemat/docker_config.ts` | schemat | `neededPorts()`, `serviceUrl()` | Port calculation, env-dependent |
| `schemat/logging.ts` | schemat | `initLogger`, `logDebug`, `logInfo`, `logOk`, `logWarn`, `logError` | Logging with verbose/quiet state |
| `schemat/topology_list.ts` | schemat | `listTopologyPresets()` | Preset listing, registry integration |

**Tier 3 — I/O-heavy, test via integration or mocks:**

| File | Package | Why it matters |
|------|---------|----------------|
| `laweta/docker_health.ts` | laweta | Health check logic, needs fetch/Docker mocks |
| `laweta/docker_compose.ts` | laweta | Command building, needs Deno.Command mocks |
| `narzedzia/repo_docs.ts` | narzedzia | Link analysis, needs filesystem fixtures |
| `narzedzia/vitepress_migration.ts` | narzedzia | String transforms are pure, but class is I/O-heavy |

**Tier 4 — Low ROI (CLI commands, generated code, or scripts):**

| Files | Why skipped |
|-------|-----------|
| `hamownia/cli/*.ts` | CLI commands, require Docker |
| `gruszka/clients/*.ts` | Generated from lexicons |
| `narzedzia/ops_command.ts` | Cloudflare ops, requires API keys |
| `narzedzia/doc_validator.ts` | Mostly stubs, I/O-heavy |

---

## 3. Proposed Workstreams

### Stream 1: ✅ tui currentTheme lazy init (P1) — COMPLETED

Already implemented: `getCurrentTheme()` lazy-resolves via `_currentTheme = undefined` guard. `COLORS` uses getters.

### Stream 2: ✅ Deduplicate formatBytes (P2) — COMPLETED

Already implemented: `gruszka/format.ts` has unified impl; laweta/hamownia re-export.

### Stream 3: Tier 1 Test Coverage (P4)

```
3a. laweta/format.ts tests (already covered if deduplicated to gruszka)
3b. schemat/topology_registry.ts tests (isKnownServiceRole, roleEnvKey, validateRoleCapability, etc.)
3c. schemat/topology_manifest.ts tests (parsePortMapping, sanitizeTopologyName, publicUrlForRole, etc.)
3d. narzedzia/spdx_headers.ts tests (hasSpdx, addSpdxHeader)
3e. narzedzia/doc_coverage.ts tests (countDocumentation, subsystemForPath, classifyDoc)
3f. narzedzia/tsdoc_coverage.ts tests (buildReport)
```

**Effort:** Medium (each file 1–2 hours). **Risk:** Low.

### Stream 4: Tier 2 Test Coverage (P4, after Stream 3)

```
4a. laweta/telemetry.ts tests (withSpan, test hooks, isOtelEnabled)
4b. ✅ schemat/docker_config.ts tests — COMPLETED (Phase 12): 25 tests with EnvSource DI
4c. ✅ schemat/logging.ts tests — COMPLETED (Phase 12): 24 tests with StringOutput DI
4d. schemat/topology_list.ts tests (listTopologyPresets)
```

**Effort:** Medium. **Risk:** Low. (Items 4b–4c done; 4a, 4d remain.)

---

## 4. Implementation Sequence

```
Phase 9: ✅ tui currentTheme lazy init — COMPLETED (already lazy via getCurrentTheme())
Phase 10: ✅ Deduplicate formatBytes — COMPLETED (already unified in gruszka/format.ts)

Phase 11: Tier 1 Test Coverage (Stream 3)
  11a. schemat/topology_registry.ts tests
  11b. schemat/topology_manifest.ts tests
  11c. narzedzia/spdx_headers.ts tests
  11d. narzedzia/doc_coverage.ts tests
  11e. narzedzia/tsdoc_coverage.ts tests

Phase 12: Tier 2 Test Coverage (Stream 4) — ✅ COMPLETED 12b–12c, remaining 12a, 12d
  12a. laweta/telemetry.ts tests (remaining)
  12b. ✅ schemat/docker_config.ts tests (25 tests, DI)
  12c. ✅ schemat/logging.ts tests (24 tests, DI)
  12d. schemat/topology_list.ts tests (remaining)
```

**Suggested order:** 9 → 10 → 11 → 12

Phase 9 is a small architectural fix. Phase 10 removes duplication. Phases 11–12 are ongoing quality improvement.

---

## 5. Success Criteria

- [x] Importing `@garazyk/tui` does not trigger `Deno.env.get` at module load time — **lazy init via getCurrentTheme()**
- [x] `formatBytes` has a single implementation in gruszka, re-exported by laweta and hamownia — **unified in gruszka/format.ts**
- [x] Test count increases by 40+ (covering registry, manifest, spdx, doc_coverage, tsdoc_coverage, telemetry, docker_config, logging) — **49 new tests added (docker_config + logging); 92 schemat net gain**
- [x] All 3104+ tests pass, `deno check` clean, boundary check passes — **1048 package tests pass, boundary clean**
- [x] All 6 packages still pass `deno publish --dry-run`

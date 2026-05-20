# Deno Packages: Next Steps Plan

> Generated: 2026-05-20 · Updated after completing Phases 1–8

---

## 1. Current State Summary

| Package | Tests | JSR Publish | Sans-IO | Untested Source Files |
|---------|-------|-------------|---------|-----------------------|
| `gruszka` | 35 | ✅ Clean | ✅ Pure | 20 (mostly generated clients) |
| `schemat` | 67 | ✅ Clean | ✅ Pure | 10 |
| `laweta` | 63 | ✅ Clean | ✅ HOME deferred | 6 |
| `hamownia` | 73 | ✅ Clean | ✅ Pure (progress fixed) | 28 (mostly CLI/infra) |
| `narzedzia` | 11 | ✅ Clean | ✅ Pure | 10 |
| `tui` | 227 | ✅ Clean | ⚠️ `currentTheme` reads env at module load | 3 |

**Total: 2856 package tests + 104 dashboard tests = 2960 passing.**
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

---

## 2. Remaining Issues

### P1. tui `currentTheme` module-load env read (Low severity)

**Current:** `tui/theme.ts:304` initializes `currentTheme = resolveTheme()` at module load, which reads `Deno.env.get("GARAZYK_TUI_THEME")` and `Deno.env.get("COLORFGBG")`. Since `mod.ts` re-exports `currentTheme` and `COLORS`, importing `@garazyk/tui` (the pure root) triggers an env read.

**Options:**
- **Lazy init:** Change `currentTheme` to a getter that calls `resolveTheme()` on first access, then caches
- **Move to runtime:** Don't re-export `currentTheme`/`COLORS` from the pure root; only from `@garazyk/tui/runtime`
- **Accept it:** It's a non-blocking env read that returns a default; low practical impact

**Effort:** Small. **Risk:** Low (breaking change if moving to runtime).

### P2. Duplicate `formatBytes` in laweta and hamownia

**Current:** `laweta/format.ts` and `hamownia/format.ts` both implement `formatBytes()` with slightly different logic:
- laweta: loop-based, supports TiB, `toFixed(0)` for bytes
- hamownia: if-chain, no TiB, always `toFixed(1)`

**Options:**
- **Extract to gruszka:** Both laweta and hamownia import from `@garazyk/gruszka/format`. Gruszka is the shared utilities package.
- **Accept duplication:** Both packages are independent; the functions are small and stable.

**Effort:** Small. **Risk:** Low.

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

### Stream 1: tui currentTheme lazy init (P1)

```
1a. Change currentTheme from `let` to a lazy getter pattern
1b. Verify: importing @garazyk/tui doesn't trigger env reads until first access
1c. Verify: all 227 tui tests pass
```

**Effort:** Small. **Risk:** Low.

### Stream 2: Deduplicate formatBytes (P2)

```
2a. Move the laweta version (loop-based, TiB support) to gruszka/format.ts
2b. Update laweta/format.ts to re-export from @garazyk/gruszka
2c. Update hamownia/format.ts to re-export from @garazyk/gruszka
2d. Add formatBytes tests to gruszka
2e. Verify: deno check, deno test, deno task boundaries
```

**Effort:** Small. **Risk:** Low (gruszka is already a dependency of both).

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
4b. schemat/docker_config.ts tests (neededPorts, serviceUrl with env stubs)
4c. schemat/logging.ts tests (initLogger, verbose/quiet state)
4d. schemat/topology_list.ts tests (listTopologyPresets)
```

**Effort:** Medium. **Risk:** Low.

---

## 4. Implementation Sequence

```
Phase 9: tui currentTheme lazy init (Stream 1)
  9a. Refactor currentTheme to lazy getter
  9b. Verify: all tests pass

Phase 10: Deduplicate formatBytes (Stream 2)
  10a. Extract to gruszka/format.ts
  10b. Update laweta + hamownia imports
  10c. Add formatBytes tests
  10d. Verify: boundaries, check, test

Phase 11: Tier 1 Test Coverage (Stream 3)
  11a. schemat/topology_registry.ts tests
  11b. schemat/topology_manifest.ts tests
  11c. narzedzia/spdx_headers.ts tests
  11d. narzedzia/doc_coverage.ts tests
  11e. narzedzia/tsdoc_coverage.ts tests

Phase 12: Tier 2 Test Coverage (Stream 4)
  12a. laweta/telemetry.ts tests
  12b. schemat/docker_config.ts tests
  12c. schemat/logging.ts tests
  12d. schemat/topology_list.ts tests
```

**Suggested order:** 9 → 10 → 11 → 12

Phase 9 is a small architectural fix. Phase 10 removes duplication. Phases 11–12 are ongoing quality improvement.

---

## 5. Success Criteria

- [ ] Importing `@garazyk/tui` does not trigger `Deno.env.get` at module load time
- [ ] `formatBytes` has a single implementation in gruszka, re-exported by laweta and hamownia
- [ ] Test count increases by 40+ (covering registry, manifest, spdx, doc_coverage, tsdoc_coverage, telemetry, docker_config, logging)
- [ ] All 2960+ tests pass, `deno check` clean, boundary check passes
- [ ] All 6 packages still pass `deno publish --dry-run`

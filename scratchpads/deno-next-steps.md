# Deno Packages: Next Steps Plan

> Generated: 2026-05-20 · Updated after completing Phases 1–6

---

## 1. Current State Summary

| Package | Tests | JSR Publish | Sans-IO | Key Gaps |
|---------|-------|-------------|---------|----------|
| `gruszka` | 35 | ✅ Clean | ✅ Pure | 20 untested files (mostly generated clients) |
| `schemat` | 67 | ✅ Clean | ✅ Pure | 10 untested source files |
| `laweta` | 63 | ✅ Clean | ✅ HOME deferred | 6 untested files (compose, health, format, telemetry) |
| `hamownia` | 73 | ❌ 3 stale exports | ✅ Pure (progress fixed) | 27 untested files; `npm:playwright` missing constraint |
| `narzedzia` | 11 | ❌ `npm:playwright` transitive | ✅ Pure | 12 untested files; smoke_command boundary violation |
| `tui` | 227 | ❌ Missing LICENSE | ✅ Pure root + runtime subpath | 3 untested files |

**Total: 2856 tests passing, 0 failures. All `deno check` clean.**

### Completed Architecture Plan Actions

| Action | Status | What was done |
|--------|--------|--------------|
| A1 — Extract ProgressBar rendering | ✅ | `render()` returns string, `run_loop.ts` owns stdout |
| A2 — Remove run_loop terminal I/O | ✅ | `writeProgressLine()` helper, zero `Deno.stdout` in pure logic |
| A3 — Split tui/ subpaths | ✅ | `@garazyk/tui` pure root, `@garazyk/tui/runtime` for terminal I/O |
| A4 — Move chat_viewer out of gruszka | ✅ | Already done before this session |
| A7 — Inject env into docker_api.ts | ✅ | `DockerApiClientOptions` with `endpoint/dockerHost/homeDir` |
| A8 — Slice DashboardState.Msg | ✅ | 7 sub-unions + per-slice reducers + root coordinator |
| E — Narzedzia publish blocker | ✅ | Stale `fuzz-command` removed, `addCname()` return type fixed |
| F — Test coverage | ✅ | 17 new tests (11 boundary_check, 6 topology_types) |

---

## 2. Remaining Issues (Priority Order)

### P1. JSR Publish Blockers (3 packages)

**P1a. hamownia — 3 stale exports referencing deleted files**

`deno.json` exports `./service-command`, `./demo-command`, `./test-command` but the files were moved to `cli/service.ts`, `cli/demo.ts`, `cli/test.ts` in commit 56efcbd7. The exports need to either:
- Point to the new `cli/*.ts` paths, or
- Be removed if the CLI subpaths aren't part of the public API

**Effort:** Small. **Risk:** Low.

**P1b. hamownia — `npm:playwright` missing version constraint**

`preflight.ts:69` uses `import("npm:playwright")` without a version constraint. JSR requires `npm:playwright@1.60.0` or similar. This also blocks narzedzia (transitive dependency via hamownia).

**Effort:** Small. **Risk:** Low (just add `@1.60.0` to the specifier).

**P1c. tui — Missing LICENSE file**

JSR requires a license field or file. `packages/tui/deno.json` has no `license` key and no `LICENSE` file. Other packages use `"license": "Unlicense OR CC0-1.0"` and have a `LICENSE` file.

**Effort:** Small. **Risk:** None.

### P2. Boundary Violation (1 active)

**narzedzia/smoke_command.ts imports @garazyk/hamownia**

`smoke_command.ts:2` imports `createCharacterRegistry`, `ScenarioResult`, `timedCall` from hamownia. The boundary rule says narzedzia must not depend on hamownia.

Options:
- **Move smoke_command.ts to hamownia** — it's a scenario utility, not a dev tool
- **Extract the shared types** (`ScenarioResult`, `timedCall`) into schemat or a new shared package
- **Add to baseline** if the dependency is accepted

**Effort:** Small–Medium. **Risk:** Low.

### P3. Deferred Architecture Plan Items

| Item | Status | Why still deferred |
|------|--------|-------------------|
| A5 — Generic TEA types | Deferred | No second consumer yet; dashboard's Cmd is runtime-specific |
| A6 — `Result<T, E>` type | Deferred | Useful but not blocking anything; can be added incrementally |

### P4. Test Coverage Gaps (by priority)

**High-priority untested files (core logic, not CLI/generated):**

| File | Package | Why it matters |
|------|---------|----------------|
| `laweta/docker_health.ts` | laweta | Health check logic — core Docker feature |
| `laweta/compose.ts` | laweta | Compose integration — 37 bytes, likely just a re-export |
| `laweta/format.ts` | laweta | Formatting utilities |
| `schemat/topology_presets.ts` | schemat | Built-in topology definitions — source of truth |
| `schemat/topology_manifest.ts` | schemat | Manifest loading — core feature |
| `schemat/topology_compiler.ts` | schemat | Topology compilation — core feature |
| `narzedzia/doc_coverage.ts` | narzedzia | Doc coverage tooling |
| `narzedzia/spdx_headers.ts` | narzedzia | License header tooling |

**Low-priority (CLI commands, generated code, or scripts):**
- `hamownia/cli/*.ts` — CLI commands, hard to unit test without Docker
- `gruszka/clients/*.ts` — Generated from lexicons, low ROI for hand-written tests
- `narzedzia/ops_command.ts` — Cloudflare ops, requires API keys

---

## 3. Proposed Workstreams

### Stream 1: JSR Publish Readiness (P1)

```
1a. Remove stale hamownia exports (service-command, demo-command, test-command)
1b. Add version constraint to npm:playwright in hamownia/preflight.ts
1c. Add LICENSE file + license field to tui/deno.json
1d. Verify: deno publish --dry-run passes for all 6 packages
```

**Effort:** Small (1–2 hours). **Risk:** Low.

### Stream 2: Boundary Fix (P2)

```
2a. Decide: move smoke_command.ts to hamownia, or extract shared types, or baseline
2b. Implement the chosen fix
2c. Verify: deno run -A packages/narzedzia/boundary_check.ts passes
```

**Effort:** Small–Medium. **Risk:** Low.

### Stream 3: Incremental Test Coverage (P4)

Focus on the high-priority untested files first:

```
3a. laweta/docker_health.ts tests
3b. laweta/format.ts tests
3c. schemat/topology_presets.ts tests (preset structure, defaults)
3d. schemat/topology_compiler.ts tests (compilation logic)
3e. narzedzia/doc_coverage.ts tests
3f. narzedzia/spdx_headers.ts tests
```

**Effort:** Medium (each file is 1–3 hours). **Risk:** Low.

### Stream 4: Deferred Architecture Items (when needed)

- **A5 (TEA types):** Create `@garazyk/tea` or `tui/tea.ts` when a second TEA consumer appears
- **A6 (Result type):** Add `Result<T, E>` to narzedzia or schemat when ad-hoc patterns become painful

**Effort:** Medium each. **Risk:** Medium (A5 needs careful design).

---

## 4. Implementation Sequence

```
Phase 7: JSR Publish Readiness (Stream 1)
  7a. Fix hamownia stale exports
  7b. Add npm:playwright@1.60.0 constraint
  7c. Add LICENSE + license to tui
  7d. Verify: deno publish --dry-run passes for all 6 packages

Phase 8: Boundary Fix (Stream 2)
  8a. Move smoke_command.ts to hamownia (or extract shared types)
  8b. Verify: boundary check passes with zero violations

Phase 9: Test Coverage (Stream 3, ongoing)
  9a. laweta: docker_health, format
  9b. schemat: topology_presets, topology_compiler
  9c. narzedzia: doc_coverage, spdx_headers
```

**Suggested order:** 7 → 8 → 9

Phase 7 is the highest priority — it unblocks JSR publishing for all packages. Phase 8 cleans up the last boundary violation. Phase 9 is ongoing quality improvement.

---

## 5. Success Criteria

- [ ] `deno publish --dry-run` passes for all 6 packages
- [ ] `deno run -A packages/narzedzia/boundary_check.ts` passes with zero violations
- [ ] All 2856+ package tests pass + 102 dashboard tests pass
- [ ] `deno task check` passes with zero errors
- [ ] Test count increases by 20+ (covering laweta, schemat, narzedzia core modules)

# Garazyk Code Review Research — Master Plan

## Goal
Conduct research-driven code review preparation across all 6 packages. For each package, spawn targeted web search queries to identify best practices, known pitfalls, and reference implementations that will inform future code review activities.

## Deciduous Tracking
- Goal node 280: "Research-driven code review preparation for all 6 packages"
- Action nodes 281–286: One per package, linked to goal
- Scratchpad files: `scratchpads/code-review-research/{pkg}-research.md`
- Doc attachments: 40–45 (one per action node)

## Sub-Agent Spawning Strategy

### Wave 1: Docker & Infrastructure (parallel)
These are independent — no cross-dependencies.

**Agent A: Laweta — Docker Engine API**
Search queries:
1. "Deno createHttpClient unix socket proxy stability issues 2025 2026"
2. "Docker Engine API v1.43 changes deprecated endpoints"
3. "NDJSON parsing edge cases partial lines buffer overflow"
4. "Docker log stream multiplexing protocol 8-byte header parsing"
5. "sans-IO pattern TypeScript library design"
6. "Docker health_status event unreliable missed events"

**Agent B: Schemat — Topology & Compose**
Search queries:
1. "Docker Compose YAML generation JavaScript string concatenation pitfalls"
2. "Docker Compose healthcheck curl vs wget best practices"
3. "Docker volume mount path traversal security"
4. "SigNoz Docker Compose configuration best practices 2025"
5. "JSON manifest versioning backward compatibility strategy"

### Wave 2: AT Protocol & Networking (parallel)
These depend on understanding the ATProto ecosystem.

**Agent C: Gruszka — XRPC & Firehose**
Search queries:
1. "ipld dag-cbor JavaScript decoding security vulnerabilities"
2. "ATProto XRPC client TypeScript best practices 2025"
3. "ATProto lexicon code generation TypeScript"
4. "ATProto firehose WebSocket reconnection cursor"
5. "HTTP retry idempotency POST mutation safety XRPC"
6. "TypeScript Proxy object nested method chain type inference"

**Agent D: Hamownia — Scenario Orchestration**
Search queries:
1. "Deno.Command spawn child process timeout SIGTERM SIGKILL"
2. "E2E test framework scenario runner architecture patterns"
3. "Deno HTTP mock server testing patterns"
4. "Playwright network request interception blocking public hosts"
5. "OpenTelemetry test harness instrumentation patterns"
6. "test result JSON report format best practices"

### Wave 3: Tooling & UI (parallel)
These are the most independent packages.

**Agent E: Narzedzia — Static Analysis**
Search queries:
1. "TypeScript monorepo module boundary enforcement tools"
2. "regex import analysis vs AST TypeScript static analysis"
3. "TypeScript documentation coverage metrics tools"
4. "SPDX license header checking automation tools"

**Agent F: TUI — Terminal UI**
Search queries:
1. "terminal UI layout engine tree solver comparison"
2. "sans-IO terminal UI architecture Elm TEA pattern"
3. "ANSI 16 color terminal UI theme design best practices"
4. "terminal screen buffer double buffering diff rendering"
5. "terminal key event parsing escape sequences TypeScript"
6. "CJK wide character terminal UI rendering Unicode width"

## Execution Order
1. ✅ Package surveys complete (all 6 packages read and analyzed)
2. ✅ Scratchpad files written with research queries and review concerns
3. ✅ Deciduous nodes created and linked
4. ✅ Wave 1: Spawn agents A + B (Docker/infrastructure research)
5. ✅ Wave 2: Spawn agents C + D (ATProto/networking research)
6. ✅ Wave 3: Spawn agents E + F (tooling/UI research)
7. ✅ Synthesize findings into per-package review checklists → `CHECKLISTS.md`
8. ✅ Create deciduous outcomes with key findings (nodes 308–313)
9. ✅ Remediation action plan → `ACTION_PLAN.md`

## Deliverables
| File | Purpose |
|------|---------|
| `{pkg}-research.md` | Per-package research queries + code review concerns |
| `{pkg}-findings.md` | Per-package web search results + review checklists |
| `CHECKLISTS.md` | Master checklist across all 6 packages |
| `ACTION_PLAN.md` | 3-phase remediation plan (Security → Architecture → DX) |
| `MASTER-PLAN.md` | This file — orchestration overview |

## Cross-Cutting Themes (validated by research)
Several concerns span multiple packages — confirmed by the research findings:

- **Sans-IO pattern**: laweta (DockerEventParser ✅ clean), tui (layout/render ⚠️ NO_COLOR env leak at import), gruszka (transport ✅ clean) — boundary is inconsistent across packages
- **Deno API stability**: `Deno.createHttpClient` has known Rust-side memory leak (#33848), `Deno.Command` should use `AbortSignal.timeout()` for lifecycle safety
- **Security**: path traversal (schemat — `relative()`+`startsWith("..")` insufficient vs symlinks), SQL injection (hamownia/narzedzia — string interpolation in ops), DAG-CBOR prototype pollution (gruszka), `-A` permissions (hamownia)
- **Resource cleanup**: child processes (hamownia — needs AbortSignal), Docker containers (laweta — `client.close()` must be deterministic), WebSocket (gruszka — no cursor tracking), terminal mode (tui — `NO_COLOR` frozen at import)
- **Type safety gaps**: `any` casts (gruszka — `RawCaller.call()`), `Record<string, any>` (schemat — `renderComposeYaml`), type intersections (hamownia — `ScenarioConfig & CharacterRegistry`), regex parsing (narzedzia — boundary checker misses `import type`, re-exports, dynamic imports)
- **Determinism**: YAML output (schemat — needs serializer), manifest versioning (schemat — v1/v2 hardcoded), doc coverage (narzedzia — regex heuristics drift with formatting), layout rounding (tui — remainder allocation to last child)
- **Parser-first vs regex-first**: Boundary checker (narzedzia), doc coverage (narzedzia), markdown migration (narzedzia), YAML generation (schemat) — all would benefit from structured parsing over string matching

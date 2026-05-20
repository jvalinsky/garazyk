# Garazyk Code Review Remediation — Detailed Plan

## Overview

25 items across 6 packages, organized into 3 phases by risk severity. Each item
specifies: files touched, exact change description, test requirements, verification
steps, and PR sequencing. Phases are ordered so that no PR depends on a later phase.

**Deciduous goal**: Node 280
**Branch**: Work on `code-review-remediation` branched from `main`

---

## Phase 1: Security & Stability (7 items)

These are potential vulnerabilities, resource leaks, or crash risks. Each is
independent — no cross-package dependencies within this phase.

---

### 1.1 schemat: Replace manual YAML generation with `@std/yaml` serializer

**Risk**: Data corruption — unquoted env values containing `:`, `#`, newlines, or
boolean-like strings get misinterpreted by Docker Compose's YAML parser.

**Files**:
- `packages/schemat/topology_compiler.ts` — `renderComposeYaml()` (L252–443), `renderSidecarService()` (L578–691), `renderSigNozServices()` (L131–247)

**Current state**: Builds `Record<string, any>` objects then calls `stringify()` from
`@std/yaml` (already imported at L2). The env entries are built as `string[]` arrays
using template literals: `${k}=${v}` (L328, L649). Docker Compose accepts both
`KEY=VALUE` string format and `{KEY: VALUE}` map format for environment variables.

**Change**:
1. Convert env entries from `string[]` (`["KEY=VALUE"]`) to `Record<string, string>`
   (`{KEY: "VALUE"}`) throughout `renderComposeYaml()`, `renderSidecarService()`, and
   `renderSigNozServices()`.
2. The `@std/yaml` `stringify()` already handles quoting correctly for map values —
   this is the fix. Values containing `:`, `#`, newlines, etc. will be properly quoted.
3. Replace `Record<string, any>` with explicit interfaces for the compose service
   object: `ComposeService`, `ComposeHealthcheck`, `ComposeDependsOn`.

**Tests**:
- Add test: env value containing `:` renders correctly (not reinterpreted as YAML mapping)
- Add test: env value containing `#` renders correctly (not truncated as comment)
- Add test: env value containing `true`/`false`/`null` renders as string, not YAML boolean/null
- Add test: multiline env value renders as YAML block scalar
- Run existing: `deno test packages/schemat/`

**Verification**: `deno check packages/schemat/topology_compiler.ts && deno task boundaries && deno test packages/schemat/`

**PR**: `fix(schemat): use YAML map format for environment variables`

---

### 1.2 schemat: Harden path traversal protection in `renderVolume()`

**Risk**: Symlink escape — `relative()` + `startsWith("..")` is insufficient when
the resolved path contains a symlink pointing outside the base directory.

**Files**:
- `packages/schemat/topology_compiler.ts` — `ensurePathIsWithinBase()` (L515–544), `renderVolume()` (L546–574)

**Current state**: `ensurePathIsWithinBase()` already does both textual check AND
`Deno.realPathSync()` symlink check (L530–543). The research flagged this as
insufficient, but the code already handles symlinks. However, there are two gaps:
1. `Deno.realPathSync()` is called on `resolvedPath` which may not exist yet — the
   `catch (NotFound)` handles this, but a TOCTOU race exists between the check and
   the actual volume mount.
2. The `renderVolume()` function itself doesn't call `ensurePathIsWithinBase()` for
   sidecar config files — it does (L634–639), but the check happens after `resolve()`
   and before the volume string is constructed.

**Change**:
1. Add a `Deno.realPathSync()` check on the **base directory** only (not the target,
   which may not exist). If the base doesn't exist, throw.
2. For the target path, use `resolve()` + `relative()` textual check as primary, and
   add a `Deno.realPathSync()` check only when the target already exists (it's a
   bind mount of existing source code, so it usually will).
3. Document the TOCTOU limitation in a code comment — Docker Compose itself will
   resolve the path at mount time, so full prevention requires Docker-level controls.
4. Add `renderVolume()` tests with symlink attack vectors.

**Tests**:
- Add test: `../etc/passwd` volume source is rejected
- Add test: volume source with symlink inside base is accepted
- Add test: volume source with symlink escaping base is rejected
- Add test: nonexistent volume source passes textual check (will fail at Docker level)

**Verification**: `deno check packages/schemat/topology_compiler.ts && deno test packages/schemat/`

**PR**: `fix(schemat): harden path traversal protection in renderVolume`

---

### 1.3 laweta: Ensure `Deno.createHttpClient` is deterministically closed

**Risk**: `EMFILE` file descriptor exhaustion and Rust-side memory leak (Deno #33848)
if `DockerApiClient.close()` is not called.

**Files**:
- `packages/laweta/docker_api.ts` — `DockerApiClient` class (L313–672)
- `packages/laweta/docker_events.ts` — `ContainerEventWatcher`
- `packages/laweta/docker_health.ts` — `waitForViaInspectOrEvents`

**Current state**: `DockerApiClient` has `close()` (L387–392) and `init()` calls
`close()` on failure (L375, L381). `createDockerClient()` calls `close()` if init
fails (L801). The client is properly managed.

**Gaps**:
1. No `Symbol.dispose`/`using` support — callers must remember to call `close()`.
2. `ContainerEventWatcher.close()` has a 100ms race timeout — could leak if the
   event stream doesn't drain in time.
3. `waitFor()` and `waitForViaInspectOrEvents()` create `setInterval` loops, but
   the `Waiter` type only stores `timeoutId`, NOT the interval id. When `close()`
   rejects waiters, the polling interval keeps running — this is a real leak.
4. No "closed" guard — requests can be issued after `close()` is called.

**Change**:
1. Add `[Symbol.dispose]()` and `[Symbol.asyncDispose]()` to `DockerApiClient`
   that delegate to `close()`. This enables `using client = new DockerApiClient()`.
2. Add a `_closed` boolean guard to `DockerApiClient.request()` — throw if called
   after `close()`.
3. In `ContainerEventWatcher.close()`, replace the 100ms race with an
   `AbortSignal.timeout(500)` on the event stream, then force-close.
4. **Fix the interval leak**: Store interval IDs in the `Waiter` type alongside
   `timeoutId`, and clear them in `close()` when rejecting waiters.
5. Audit all call sites in hamownia that create `DockerApiClient` instances —
   ensure they use `using` or explicit `close()` in `finally` blocks.

**Tests**:
- Add test: `using client = new DockerApiClient()` auto-closes on scope exit
- Add test: `request()` throws after `close()` is called
- Add test: `ContainerEventWatcher.close()` cleans up within 500ms
- Add test: `waitFor()` interval is cleared when waiter is rejected
- Add test: `waitForViaInspectOrEvents` cleans up interval on abort
- Run existing: `deno test packages/laweta/`

**Verification**: `deno check packages/laweta/ && deno test packages/laweta/`

**PR**: `fix(laweta): add Symbol.dispose to DockerApiClient, harden cleanup paths`

---

### 1.4 laweta: Add NDJSON buffer limit enforcement

**Risk**: OOM from malformed Docker event streams that never contain a newline.

**Files**:
- `packages/laweta/docker_api.ts` — `parseNdjsonStream()` (L730–788)

**Current state**: Already has a 1MB buffer limit (L767–769):
```ts
if (buffer.length > 1024 * 1024) {
  throw new Error(`NDJSON buffer limit exceeded (1MB) in ${context}`);
}
```

**Gap**: The limit is on the *accumulated buffer*, not on individual line length.
A single 1MB line is allowed through. For Docker events, lines are typically <1KB.
A 1MB single line likely indicates a malformed stream.

**Change**:
1. Add a `MAX_LINE_LENGTH` constant (e.g., 64KB) — any single line exceeding this
   is likely malformed and should be rejected with a clear error.
2. Track the current line start position and check line length before parsing.
3. The existing 1MB total buffer limit stays as a backstop.

**Tests**:
- Add test: single line >64KB is rejected
- Add test: total buffer >1MB is rejected
- Add test: normal Docker event stream parses correctly
- Add test: partial line at chunk boundary is buffered correctly

**Verification**: `deno check packages/laweta/ && deno test packages/laweta/`

**PR**: `fix(laweta): add per-line length limit to NDJSON parser`

---

### 1.5 gruszka: DAG-CBOR hardening — recursion limits and prototype pollution

**Risk**: Stack exhaustion from deeply nested CBOR, or prototype pollution from
`__proto__`/`constructor` keys.

**Files**:
- `packages/gruszka/firehose.ts` — `validateDagCborShape()` (L75–91)

**Current state**: Already has both protections:
1. Recursion depth limit of 256 (L76–78)
2. Prototype pollution check for `__proto__` and `constructor` (L85–87)

**Gap**: The depth limit of 256 is generous but reasonable. The prototype pollution
check is present. However, there's no test coverage for these guards.

**Change**:
1. Add tests that verify `validateDagCborShape` rejects depth > 256
2. Add tests that verify `validateDagCborShape` rejects `__proto__` and `constructor`
3. Consider lowering the depth limit to 64 (ATProto firehose frames are typically
   3–5 levels deep) — but this is a tuning decision, not a fix.
4. Add a `MAX_FRAME_SIZE` constant to `parseFirehoseFrame()` — reject frames
   larger than 10MB (current firehose frames are typically <100KB).

**Tests**:
- Add test: deeply nested CBOR (depth 257) is rejected
- Add test: CBOR with `__proto__` key is rejected
- Add test: CBOR with `constructor` key is rejected
- Add test: oversized firehose frame (>10MB) is rejected
- Add test: normal firehose frame parses correctly

**Verification**: `deno check packages/gruszka/ && deno test packages/gruszka/`

**PR**: `fix(gruszka): add frame size limit and test coverage for DAG-CBOR guards`

---

### 1.6 gruszka: TransportLayer retry safety audit

**Risk**: Retrying POST requests could create duplicate records.

**Files**:
- `packages/gruszka/transport.ts` — `TransportLayer.request()` (L160–213)

**Current state**: Already correct — L170–173:
```ts
const httpMethod = (options.method || "GET").toUpperCase();
const isIdempotent = /^(GET|HEAD|OPTIONS)$/.test(httpMethod);
const maxAttempts = transportOptions?.maxRetries ??
  (isIdempotent ? this._maxAttempts : 1);
```
Mutations default to 1 attempt (no retry). GET/HEAD/OPTIONS default to 3 attempts.

**Gap**: The `RequestOptions.maxRetries` field allows callers to override the
default and retry mutations. This is a footgun — a caller could set `maxRetries: 3`
on a POST without understanding the consequences.

**Change**:
1. Add a JSDoc warning on `RequestOptions.maxRetries` that overriding on mutations
   is dangerous without idempotency keys.
2. Add a runtime warning (console.warn) when `maxRetries > 1` is set on a
   non-idempotent method.
3. Consider adding an `allowMutationRetry` boolean opt-in that must be explicitly
   set to allow retrying mutations.
4. **Deduplicate `getBinary()` retry logic** — it currently duplicates the retry
   loop from `request()`. Refactor to route through `request()` with a binary
   response handler, or extract a shared `retryLoop()` helper.

**Tests**:
- Add test: GET requests retry on 503 by default
- Add test: POST requests do NOT retry by default
- Add test: POST with explicit `maxRetries: 3` logs a warning
- Add test: POST with `maxRetries: 3` and `allowMutationRetry: true` does retry

**Verification**: `deno check packages/gruszka/ && deno test packages/gruszka/`

**PR**: `fix(gruszka): add mutation retry safety guard to TransportLayer`

---

### 1.7 narzedzia: Security audit of `ops_command.ts`

**Risk**: Path traversal, SQL injection, or DID validation bypass in PDS ops tooling.

**Files**:
- `packages/narzedzia/ops_command.ts`

**Change**:
1. Audit `runBackup()` — verify tar exit code is checked
2. Audit `runBackfill()` — verify SQL is parameterized, not string-interpolated
3. Audit `runValidateConfig()` — verify path inputs are sanitized
4. Audit `runSetupPds()` — verify Cloudflare API calls use abort timeouts
5. Audit `validateDid()` — verify it's not stricter than the full `did:web` space
6. Audit `CloudflareClient` — verify API calls use explicit status checks

**Tests**:
- Add test: `validateDid()` accepts valid `did:plc:` and `did:web:` DIDs
- Add test: `validateDid()` rejects malformed DIDs
- Add test: path inputs with `..` are rejected
- Add test: SQL generation uses parameterized queries

**Verification**: `deno check packages/narzedzia/ && deno test packages/narzedzia/`

**PR**: `fix(narzedzia): harden security in ops_command.ts`

---

## Phase 2: Architecture & Determinism (10 items)

These resolve architectural brittleness and unpredictable behavior. Some items
depend on Phase 1 (e.g., 2.1 depends on 1.1 for the compose service types).

---

### 2.1 schemat: Add explicit health-port property to topology DSL

**Risk**: `extractContainerPort()` picks the first port mapping — may not be the
health check port.

**Files**:
- `packages/schemat/topology_types.ts` — `ServiceAdapter` interface
- `packages/schemat/topology_compiler.ts` — `extractContainerPort()` (L508–513),
  `renderComposeYaml()` health check section (L357–390)

**Current state**: `extractContainerPort()` returns `parsePortMapping(adapter.ports[0]).containerPort`.
The health check URL is built from this port (L380).

**Change**:
1. Add `healthPort?: string` to `ServiceAdapter` interface in `topology_types.ts`
2. In `renderComposeYaml()`, prefer `adapter.healthPort` over `extractContainerPort()`
3. Fall back to `extractContainerPort()` for backward compatibility
4. Add `healthPort` to all preset definitions in `topology_presets.ts`
5. Add a validation in `validatePreset()` that `healthPort` matches a declared port

**Tests**:
- Add test: `healthPort` is used when specified
- Add test: falls back to first port when `healthPort` is omitted
- Add test: validation rejects `healthPort` that doesn't match any declared port

**Verification**: `deno check packages/schemat/ && deno task boundaries && deno test packages/schemat/`

**PR**: `feat(schemat): add explicit healthPort property to topology DSL`

**Depends on**: 1.1 (compose service types)

---

### 2.2 schemat: Parameterize SigNoz service configuration

**Risk**: Hardcoded image tags and service topology make upgrades brittle.

**Files**:
- `packages/schemat/topology_compiler.ts` — `renderSigNozServices()` (L131–247)
- `packages/schemat/topology_types.ts`

**Change**:
1. Add `SigNozConfig` interface to `topology_types.ts`:
   ```ts
   interface SigNozConfig {
     clickhouseImage?: string;  // default: "clickhouse/clickhouse-server:25.5"
     zookeeperImage?: string;   // default: "bitnami/zookeeper:3.7"
     collectorImage?: string;   // default: "signoz/signoz-otel-collector:v0.144.4"
     uiImage?: string;          // default: "signoz/signoz:v0.123.0"
     collectorConfigPath?: string;
     managerConfigPath?: string;
   }
   ```
2. Add `sigNoz?: SigNozConfig` to `CompilerOptions`
3. Refactor `renderSigNozServices()` to read from config with defaults
4. Add `jwtSecret` to `SigNozConfig` — the hardcoded `localdev-signoz-secret` (L226)
   should be configurable

**Tests**:
- Add test: default SigNoz config produces same output as before
- Add test: custom image tags override defaults
- Add test: custom collector config path is used

**Verification**: `deno check packages/schemat/ && deno test packages/schemat/`

**PR**: `feat(schemat): parameterize SigNoz OTel stack configuration`

**Depends on**: 1.1 (compose service types)

---

### 2.3 schemat: Versioned manifest schema with discriminated union

**Risk**: v1/v2 hardcoded branches make v3 addition fragile.

**Files**:
- `packages/schemat/topology_types.ts` — `TopologyManifest`
- `packages/schemat/topology_compiler.ts` — `createTopologyManifest()`

**Current state**: `TopologyManifest` already has `version: 1 | 2` (L346–413 in
topology_types.ts), but it's a single interface with optional v2 fields — not a
discriminated union. This means v1 manifests can have v2 fields at the type level,
and v2 manifests can omit them silently. Also, `compileTopology()` has an
unnecessary `as string` cast (L456).

**Change**:
1. Split `TopologyManifest` into `TopologyManifestV1` and `TopologyManifestV2`
   as a discriminated union:
   ```ts
   type TopologyManifest = TopologyManifestV1 | TopologyManifestV2;
   interface TopologyManifestV1 { version: 1; /* core fields only */ }
   interface TopologyManifestV2 { version: 2; /* core + v2 fields */ }
   ```
2. Add `parseTopologyManifest(json: unknown): TopologyManifest` that validates
   against the version field and migrates older versions
3. Add `MANIFEST_CURRENT_VERSION` constant
4. Update `writeTopologyManifest()` to always write current version
5. Update `loadTopologyManifest()` to use the parser
6. Remove the unnecessary `as string` cast in `compileTopology()` (L456)

**Tests**:
- Add test: v1 manifest parses and migrates to current
- Add test: v2 manifest parses and migrates to current
- Add test: unknown version is rejected with clear error
- Add test: current version round-trips through write/load

**Verification**: `deno check packages/schemat/ && deno test packages/schemat/`

**PR**: `feat(schemat): add versioned manifest schema with migration support`

---

### 2.4 hamownia: Migrate to `AbortSignal.timeout()` for child process lifecycle

**Risk**: Zombie processes from manual timeout + SIGTERM/SIGKILL race conditions.

**Files**:
- `packages/hamownia/scenario_runner.ts` — `runHostScenarioInChild()` (L163–247)
- `packages/hamownia/host_child_runner.ts` — `runChild()`

**Current state**: Manual timeout with `setTimeout` + `Promise.race` + `child.kill("SIGTERM")`
+ grace period + `child.kill("SIGKILL")` (L194–214).

**Change**:
1. Replace manual timeout with `AbortSignal.timeout(timeoutSeconds * 1000)` passed
   to `Deno.Command` via `signal` option
2. Catch `AbortError` (DOMException with name "AbortError") and convert to
   `ScenarioResult` with timeout status
3. Remove manual `setTimeout`/`clearTimeout`/`child.kill()` chain
4. Keep the SIGTERM→SIGKILL grace period for cleanup after abort, but trigger it
   from the AbortError catch block instead of a manual race

**Tests**:
- Add test: child process that completes before timeout succeeds
- Add test: child process that exceeds timeout is terminated
- Add test: AbortError is caught and converted to ScenarioResult
- Add test: temp directory is cleaned up on both success and timeout

**Verification**: `deno check packages/hamownia/ && deno test packages/hamownia/`

**PR**: `refactor(hamownia): use AbortSignal.timeout for child process lifecycle`

---

### 2.5 hamownia: Add state cleanup to `MockTwilioServer`

**Risk**: Cross-contamination between scenarios from stale in-memory state.

**Files**:
- `packages/hamownia/mock_twilio.ts` — `MockTwilioServer` class

**Change**:
1. Add `reset()` method to `MockTwilioServer` that clears all in-memory Maps
2. Call `reset()` at the start of each scenario run in the run loop
3. Add a `/__control/reset` endpoint that clears state (for external callers)
4. Fix the duplicate `MockState` declaration flagged in the survey

**Tests**:
- Add test: `reset()` clears all verification states
- Add test: consecutive `collect()` calls don't see previous scenario's events
- Add test: `/__control/reset` endpoint clears state

**Verification**: `deno check packages/hamownia/ && deno test packages/hamownia/`

**PR**: `fix(hamownia): add state cleanup to MockTwilioServer between scenarios`

---

### 2.6 hamownia: Use `SimpleSpanProcessor` for synchronous OTel span reporting

**Risk**: `BatchSpanProcessor` may drop spans if the runner crashes before flushing.

**Files**:
- `packages/hamownia/otel.ts`

**Change**:
1. Switch from `BatchSpanProcessor` to `SimpleSpanProcessor` when in test mode
2. Add `OTEL_PROCESSOR_MODE` env var to control processor selection
3. Ensure `shutdown()` is called in `finally` blocks throughout the runner

**Tests**:
- Add test: spans are captured synchronously in test mode
- Add test: `shutdown()` flushes all pending spans
- Add test: processor mode can be overridden via env var

**Verification**: `deno check packages/hamownia/ && deno test packages/hamownia/`

**PR**: `fix(hamownia): use SimpleSpanProcessor for synchronous OTel in test mode`

---

### 2.7 tui: Move `NO_COLOR` read from import time to initialization

**Risk**: `NO_COLOR` frozen at module load — can't be overridden in tests or at runtime.

**Files**:
- `packages/tui/renderer.ts` — L19: `export const NO_COLOR: boolean = Deno.env.get("NO_COLOR") !== undefined;`

**Current state**: `NO_COLOR` is a module-level `const` read at import time.

**Change**:
1. Replace `export const NO_COLOR` with a lazy getter:
   ```ts
   let _noColor: boolean | undefined;
   export function isNoColor(): boolean {
     return _noColor ??= Deno.env.get("NO_COLOR") !== undefined;
   }
   ```
2. Add `setNoColor(value: boolean)` for test overrides
3. Add `resetNoColor()` to clear the cached value
4. Update all consumers to use `isNoColor()` instead of `NO_COLOR`
5. Export `NO_COLOR` as a deprecated getter for backward compatibility

**Tests**:
- Add test: `isNoColor()` reads from env on first call
- Add test: `setNoColor(true)` overrides env
- Add test: `resetNoColor()` re-reads from env
- Add test: deprecated `NO_COLOR` getter still works

**Verification**: `deno check packages/tui/ && deno test packages/tui/`

**PR**: `refactor(tui): defer NO_COLOR read to initialization, add test override`

---

### 2.8 tui: Add overflow validation to `solveLayout()`

**Risk**: Fixed-size children that exceed the available space collapse growing children
to zero width/height, producing invisible panels.

**Files**:
- `packages/tui/layout_tree.ts` — `solveLayout()` (L63–220)

**Current state**: No validation that `consumedMainSize <= mainAxisSize`. If fixed
children consume more than the available space, `remainingSpace` goes negative and
growing children get zero width/height.

**Change**:
1. After computing `consumedMainSize`, check if it exceeds `mainAxisSize`
2. If so, log a warning and proportionally shrink fixed children to fit
3. Ensure no child gets a size < 0
4. Add `minWidth`/`minHeight` enforcement — if a child's minimum can't be met,
   emit a warning and use 0 (don't crash)

**Tests**:
- Add test: two fixed children that exceed available width are proportionally shrunk
- Add test: growing child gets zero size when fixed children consume all space
- Add test: `minWidth` is respected when space is available
- Add test: `minWidth` is relaxed to 0 when space is insufficient (with warning)

**Verification**: `deno check packages/tui/ && deno test packages/tui/`

**PR**: `fix(tui): add overflow validation to solveLayout`

---

### 2.9 tui: Honor `BoxCommand.clip` in `rasterize()`

**Risk**: Nested clipped content bleeds outside its container.

**Files**:
- `packages/tui/command.ts` — `rasterize()`, `translateCommand()`

**Change**:
1. In `rasterize()`, apply clip rectangle to all drawing operations within a
   `BoxCommand` that has `clip` set
2. In `translateCommand()`, translate child clip rectangles along with the command
3. Add `clipTo(box: BoundingBox)` helper to `ScreenBuffer` that constrains
   subsequent writes to the given rectangle

**Tests**:
- Add test: text inside a clipped box doesn't render outside the clip region
- Add test: nested clipped boxes clip correctly
- Add test: clip rectangle is translated along with the box position

**Verification**: `deno check packages/tui/ && deno test packages/tui/`

**PR**: `fix(tui): honor BoxCommand.clip in rasterize`

---

### 2.10 tui: Fix focus ring off-by-one between `jump()` and comments

**Risk**: `jump(index)` is 0-based but comments describe 1-based numeric keys.

**Files**:
- `packages/tui/focus.ts`

**Change**:
1. Update comments to clarify 0-based indexing
2. Add `jumpToPanel(n: number)` that accepts 1-based panel number (what users type)
3. Keep `jump(index)` as the internal 0-based API
4. Add bounds checking — wrap or clamp on out-of-range indices

**Tests**:
- Add test: `jump(0)` selects first panel
- Add test: `jumpToPanel(1)` selects first panel
- Add test: out-of-range index wraps or clamps

**Verification**: `deno check packages/tui/ && deno test packages/tui/`

**PR**: `fix(tui): clarify focus ring indexing, add 1-based jumpToPanel`

---

## Phase 3: DX & Tooling Accuracy (8 items)

These improve developer experience, type safety, and tooling correctness. They
can be done in parallel with each other.

---

### 3.1 narzedzia: Add AST-backed import scanning to boundary checker

**Risk**: Regex misses `import type`, re-exports, dynamic imports with template literals,
and produces false positives from comments/strings.

**Files**:
- `packages/narzedzia/boundary_check.ts` — `importPattern` (L74–75), `checkBoundaries()`

**Current state**: Single regex handles `import`/`export from` and `import()`:
```ts
/\b(?:import|export)\s+(?:type\s+)?(?:[^"']*?\s+from\s+)?["'](...)["']|\bimport\s*\(\s*["'](...)["']\s*\)/g
```

**Change**:
1. Add `es-module-lexer` as a dependency (fast, WASM-based, handles all ES module
   syntax including `import type`, re-exports, and dynamic imports)
2. Keep regex as a fast prefilter for files that don't use `@garazyk/` imports
3. Use `es-module-lexer` for precise specifier extraction on files that match
4. Add support for `export { X } from "@garazyk/..."` and `export type { X } from "..."`
5. Document intentionally unsupported forms: `require()`, `import.meta.resolve()`

**Tests**:
- Add test: `import type { X } from "@garazyk/schemat"` is detected
- Add test: `export { X } from "@garazyk/laweta"` is detected
- Add test: `export type { X } from "@garazyk/gruszka"` is detected
- Add test: dynamic `import("@garazyk/hamownia")` is detected
- Add test: `import("@garazyk/" + name)` is flagged as unknown (not a literal)
- Add test: comment containing `@garazyk/schemat` is NOT flagged (no false positive)

**Verification**: `deno check packages/narzedzia/ && deno task boundaries && deno test packages/narzedzia/`

**PR**: `feat(narzedzia): add AST-backed import scanning to boundary checker`

---

### 3.2 narzedzia: Persist baseline violations to config file

**Risk**: `currentBaseline` is hardcoded as empty set — can't track known violations.

**Files**:
- `packages/narzedzia/boundary_check.ts` — L72: `const currentBaseline = new Set<string>([]);`

**Change**:
1. Load baseline from `.deciduous/boundary-baseline.json` (or similar)
2. Add `--update-baseline` CLI flag to save current violations as the new baseline
3. Add `--baseline-file <path>` CLI flag for custom baseline location
4. Default to empty set if file doesn't exist (backward compatible)

**Tests**:
- Add test: baseline file is loaded on startup
- Add test: violations in baseline are not reported as new
- Add test: new violations not in baseline are reported
- Add test: missing baseline file falls back to empty set

**Verification**: `deno check packages/narzedzia/ && deno task boundaries && deno test packages/narzedzia/`

**PR**: `feat(narzedzia): persist boundary baseline to config file`

---

### 3.3 narzedzia: Remove or implement `doc_validator.ts` stubs

**Risk**: `validateDocDiagrams()` and `checkDocPatterns()` return `false`, making
`docValidationMain()` exit non-zero.

**Files**:
- `packages/narzedzia/doc_validator.ts`

**Change**:
1. If these functions are not needed, remove them and simplify `docValidationMain()`
2. If they are planned, replace `return false` with `throw new Error("Not implemented")`
   so callers get a clear error instead of a silent failure
3. Add `deno.json` exports if the module is intended to be public

**Tests**:
- Add test: `docValidationMain()` with stubs throws "Not implemented" or succeeds
  after stubs are removed

**Verification**: `deno check packages/narzedzia/ && deno test packages/narzedzia/`

**PR**: `fix(narzedzia): remove or implement doc_validator stubs`

---

### 3.4 gruszka: Add firehose cursor tracking for resumption

**Risk**: On WebSocket disconnect, events are lost or duplicated because there's
no cursor tracking.

**Files**:
- `packages/gruszka/firehose.ts` — `FirehoseClient` (L154–247)

**Current state**: `FirehoseClient.subscribe()` accepts a `cursor` parameter (L177)
but doesn't track the last-received cursor internally. `collect()` returns events
but doesn't expose the cursor.

**Change**:
1. Add `lastCursor: number` property to `FirehoseClient`, updated on each event
2. Add `subscribeWithResume()` method that auto-reconnects using `lastCursor`
3. Add configurable `maxReconnectAttempts` and `reconnectDelayMs`
4. Expose `lastCursor` in `collect()` return value

**Tests**:
- Add test: `lastCursor` is updated on each event
- Add test: `subscribeWithResume()` reconnects from last cursor
- Add test: `collect()` returns cursor alongside events

**Verification**: `deno check packages/gruszka/ && deno test packages/gruszka/`

**PR**: `feat(gruszka): add firehose cursor tracking for resumption`

---

### 3.5 gruszka: Audit `AgentProxy` type inference for `any` leaks

**Risk**: Recursive mapped types may degrade to `any` for method chains.

**Files**:
- `packages/gruszka/client.ts` — `AgentProxy`, `createAgentProxy`

**Change**:
1. Add compile-time type tests that verify `client.app.bsky.feed.getTimeline` is
   typed as a function (not `any`)
2. Add compile-time type tests that verify `client.com.atproto.repo.createRecord`
   is typed as a function
3. If `any` leaks are found, tighten the recursive mapped type or add explicit
   overload signatures for known namespaces
4. **Eliminate `as unknown as AgentProxy` double-cast** in `createAgentProxy()` —
   replace `Object.assign(baseClient, {...})` with a typed composition that
   structurally satisfies `AgentProxy` without assertion
5. Replace `any` in `WrapClient<C>` conditional mapped type with stricter
   `unknown`-based constraints where possible
6. Replace `any` in `RawCaller.call()` and `AgentCaller.call()` parameter/return
   types with `unknown`

**Tests**:
- Add type-level tests (using `@std/assert` `assertType<T>()` pattern)
- Add runtime test: calling a generated method returns the expected type

**Verification**: `deno check packages/gruszka/ && deno test packages/gruszka/`

**PR**: `fix(gruszka): audit and tighten AgentProxy type inference`

---

### 3.6 tui: Add grapheme-aware width calculation

**Risk**: Emoji, ZWJ sequences, and combining marks cause alignment drift.

**Files**:
- `packages/tui/text.ts` — `getCharWidth()`, `measureText()`, `truncate()`

**Change**:
1. Add `unicode-width` or similar library as optional dependency for grapheme-aware
   width calculation
2. Keep `getCharWidth()` as the fast path for ASCII/BMP — use grapheme-aware only
   when wide characters are detected
3. Update `measureText()` to handle ZWJ sequences (e.g., 👨‍👩‍👧‍👦 = width 2, not 8)
4. Update `truncate()` to respect grapheme boundaries

**Tests**:
- Add test: CJK characters report width 2
- Add test: emoji with ZWJ reports width 2
- Add test: combining marks don't add width
- Add test: `truncate()` doesn't split grapheme clusters
- Add test: `measureText()` with ANSI escapes preserves style

**Verification**: `deno check packages/tui/ && deno test packages/tui/`

**PR**: `feat(tui): add grapheme-aware width calculation`

---

### 3.7 tui: Extend `parseKey()` for bracketed paste and Kitty CSI-u

**Risk**: Pasted text is interpreted as keystrokes; Kitty keyboard protocol events
are misparsed.

**Files**:
- `packages/tui/input.ts` — `parseKey()`, `readKeys()`

**Change**:
1. Add bracketed paste detection: `\x1b[200~` ... `\x1b[201~` → emit `PasteEvent`
2. Add Kitty CSI-u detection: `\x1b[?u` enable, `\x1b[u` disable
3. Add modifier+key combinations from CSI-u (e.g., `Ctrl+Shift+Key`)
4. Document which legacy sequences are intentionally unsupported

**Tests**:
- Add test: bracketed paste sequence produces `PasteEvent`
- Add test: Kitty CSI-u key event parses correctly
- Add test: legacy CSI sequences still parse correctly
- Add test: ambiguous ESC is handled with timeout

**Verification**: `deno check packages/tui/ && deno test packages/tui/`

**PR**: `feat(tui): add bracketed paste and Kitty CSI-u support to parseKey`

---

### 3.8 tui: Make theme selection injectable instead of global mutable state

**Risk**: Global mutable theme leaks across consumers in the same process.

**Files**:
- `packages/tui/theme.ts` — `getCurrentTheme()`, `setCurrentTheme()`, `COLORS`

**Current state**: Theme is stored in a module-level `_currentTheme` variable.
`getCurrentTheme()` reads from env on first call, then caches. `COLORS` is a
getter-based proxy over the current theme.

**Change**:
1. Add `ThemeContext` class that holds the current theme and can be passed around:
   ```ts
   class ThemeContext {
     constructor(theme?: Theme);
     get theme(): Theme;
     setTheme(theme: Theme): void;
     reset(): void; // re-read from env
   }
   ```
2. Add `createThemeContext()` factory that reads from env
3. Keep `getCurrentTheme()` / `setCurrentTheme()` / `COLORS` as deprecated globals
   that use a default `ThemeContext` singleton
4. Update `ScreenBuffer` and `renderer.ts` to accept optional `ThemeContext`
5. Update `runtime.ts` to export `createThemeContext`

**Tests**:
- Add test: `ThemeContext` with explicit theme doesn't read env
- Add test: `ThemeContext.reset()` re-reads from env
- Add test: two `ThemeContext` instances can have different themes
- Add test: deprecated globals still work

**Verification**: `deno check packages/tui/ && deno test packages/tui/`

**PR**: `refactor(tui): make theme selection injectable via ThemeContext`

---

## PR Sequencing

```
Phase 1 (parallel within phase):
  1.1 fix(schemat): use YAML map format for environment variables
  1.2 fix(schemat): harden path traversal protection in renderVolume
  1.3 fix(laweta): add Symbol.dispose to DockerApiClient, harden cleanup paths
  1.4 fix(laweta): add per-line length limit to NDJSON parser
  1.5 fix(gruszka): add frame size limit and test coverage for DAG-CBOR guards
  1.6 fix(gruszka): add mutation retry safety guard to TransportLayer
  1.7 fix(narzedzia): harden security in ops_command.ts

Phase 2 (after 1.1 merges):
  2.1 feat(schemat): add explicit healthPort property to topology DSL       [depends on 1.1]
  2.2 feat(schemat): parameterize SigNoz OTel stack configuration           [depends on 1.1]
  2.3 feat(schemat): add versioned manifest schema with migration support
  2.4 refactor(hamownia): use AbortSignal.timeout for child process lifecycle
  2.5 fix(hamownia): add state cleanup to MockTwilioServer between scenarios
  2.6 fix(hamownia): use SimpleSpanProcessor for synchronous OTel in test mode
  2.7 refactor(tui): defer NO_COLOR read to initialization, add test override
  2.8 fix(tui): add overflow validation to solveLayout
  2.9 fix(tui): honor BoxCommand.clip in rasterize
  2.10 fix(tui): clarify focus ring indexing, add 1-based jumpToPanel

Phase 3 (parallel within phase):
  3.1 feat(narzedzia): add AST-backed import scanning to boundary checker
  3.2 feat(narzedzia): persist boundary baseline to config file
  3.3 fix(narzedzia): remove or implement doc_validator stubs
  3.4 feat(gruszka): add firehose cursor tracking for resumption
  3.5 fix(gruszka): audit and tighten AgentProxy type inference
  3.6 feat(tui): add grapheme-aware width calculation
  3.7 feat(tui): add bracketed paste and Kitty CSI-u support to parseKey
  3.8 refactor(tui): make theme selection injectable via ThemeContext
```

## Verification Protocol

After each PR:
1. `deno check` on the affected package
2. `deno task boundaries` (full repo boundary check)
3. `deno test` on the affected package
4. `deno test` on downstream packages that import the changed module
5. Update deciduous outcome node with the PR link

After each phase:
1. Full `deno check` across all packages
2. Full `deno task boundaries`
3. Full `deno test` across all packages
4. `deno publish --dry-run` for all 6 packages (JSR slow-type check)

## Cross-Cutting Items (not PR'd, tracked separately)

These span multiple packages and need coordination:

| Item | Packages | Notes |
|------|----------|-------|
| Sans-IO consistency audit | laweta, tui, gruszka | Verify boundary is clean across all three |
| Deno 2 API stability check | laweta, hamownia, tui | Test against Deno 2.x for breaking changes |
| `any` eradication | gruszka, schemat, hamownia | Replace `Record<string, any>` with explicit types |
| Resource cleanup audit | all | Ensure all resources are cleaned in `finally` blocks |
| Parser-first vs regex-first | narzedzia, schemat | Evaluate structured parsing over string matching |

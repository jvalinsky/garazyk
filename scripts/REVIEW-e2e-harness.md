# Deep Code Review: Garazyk Deno/TypeScript E2E Test Harness

**Date:** 2025-05-15
**Reviewer:** Letta Code (agent-1b8a94d7)
**Scope:** `scripts/lib/deno/`, `scripts/run_scenarios.ts`, `scripts/scenario-dashboard/services/run_manager.ts`, `scripts/lib/deno/clients/`

---

## Executive Summary

The Garazyk e2e test harness is a well-structured system for orchestrating Docker-based integration tests against ATProto PDS implementations. It demonstrates several strong architectural choices — the sans-IO event parser, the topology preset system, and the scenario metadata registry are thoughtful designs. However, the review uncovered **6 critical**, **13 high**, **19 medium**, and **10 low** severity findings across architecture, concurrency, security, testing, and client code.

The most urgent issues are:
1. **`withSpanSync` is broken** — it fires the tracer asynchronously but returns synchronously, meaning the span never actually wraps the function execution
2. **Transport retries on POST** — non-idempotent writes are retried, risking duplicate records
3. **Global unhandledrejection handler** — suppresses all `AbortError` rejections process-wide, masking real bugs
4. **`Deno.exit(0)` bypasses cleanup** — resource leaks are hidden by forced process termination
5. **Path traversal in topology preset loading** — preset names are interpolated into filesystem paths without sanitization; volume/source paths can escape `repoRoot`
6. **No tests for transport, runner, topology, or docker modules** — core infrastructure is untested
7. **Proxy agent can become accidentally thenable** — `then` property access triggers Promise resolution, breaking the agent
8. **Character registry is global mutable state** — not safe for re-entrant or parallel usage

---

## Findings by Severity

### CRITICAL (5)

#### C1. `withSpanSync` is fundamentally broken
**File:** `scripts/lib/deno/otel.ts:213-249`

The function calls `getTracer()` (which returns a `Promise`), then calls `.then()` on it to start the span. But the function returns `result!` synchronously *before* the `.then()` callback has executed. This means:
- The span is never active when `fn()` runs
- `result` is `undefined` when returned (the `!` assertion suppresses the type error)
- If `fn()` throws, the error is thrown before the `.catch()` fallback can call `fn()` directly
- The function is exported and used in production code

```typescript
// Current (broken):
const tracer = getTracer(); // Returns Promise
tracer.then((t: any) => {
  t.startActiveSpan(name, { attributes }, (span: any) => {
    result = fn(); // Runs AFTER the function returns
  });
});
if (error) throw error;
return result!; // Always undefined
```

**Recommendation:** Remove `withSpanSync` entirely. All callers should use `withSpan` (async). If sync tracing is truly needed, the tracer must be eagerly initialized at module load, not lazily.

---

#### C2. Transport retries on non-idempotent POST requests
**File:** `scripts/lib/deno/transport.ts:39-59`

The `request()` method retries all failed requests up to 3 times, including POSTs. For XRPC methods like `createRecord`, `createAccount`, and `sendMessage`, this can create duplicate records or duplicate messages. The retry logic has no awareness of idempotency.

```typescript
for (let attempt = 1; attempt <= this._maxAttempts; attempt++) {
  try {
    const response = await fetch(targetUrl.toString(), options);
    // ...
    return { status: response.status, body };
  } catch (error) {
    if (attempt === this._maxAttempts) throw error;
    await new Promise(r => setTimeout(r, this._baseDelay * attempt));
  }
}
```

**Recommendation:** Only retry GET requests and explicitly idempotent operations. Add an `idempotent` flag to the request options, defaulting to `false` for POSTs. Alternatively, remove retries from `TransportLayer` entirely and let callers implement retry with appropriate semantics.

---

#### C3. Global unhandledrejection handler suppresses all AbortErrors
**File:** `scripts/lib/deno/docker_events.ts:42-47`

The module-level event listener calls `e.preventDefault()` on *any* `AbortError` rejection, process-wide. This means:
- Any other module that fails to handle an `AbortError` will have its error silently swallowed
- If the `ContainerEventWatcher` is never instantiated, the handler still suppresses legitimate errors
- There's no scoping — this affects all promise rejections in the entire process

```typescript
globalThis.addEventListener("unhandledrejection", (e) => {
  const reason = (e as PromiseRejectionEvent).reason;
  if (reason instanceof DOMException && reason.name === "AbortError") {
    e.preventDefault(); // Suppresses ALL AbortErrors globally
  }
});
```

**Recommendation:** Move the suppression into the `ContainerEventWatcher` class. Attach the handler in the constructor and remove it in `close()`. Alternatively, use a flag to track whether the watcher is active and only suppress when it is.

---

#### C4. `Deno.exit(0)` bypasses event loop cleanup
**File:** `scripts/run_scenarios.ts:781`

The orchestrator calls `Deno.exit(0)` at the end of the main function, which forcibly terminates the process without running pending microtasks, `finally` blocks, or cleanup handlers. This masks:
- Resource leaks (open HTTP clients, unread stream bodies)
- Pending OTel span flushes
- Incomplete promise chains

**Recommendation:** Remove `Deno.exit(0)`. Let the process exit naturally. If the process hangs, that indicates a resource leak that should be fixed, not masked.

---

#### C5. `run_manager.ts` stdout pipe leaks the log file writable
**File:** `scripts/scenario-dashboard/services/run_manager.ts:244-257`

The stdout stream is piped to the log file with `preventClose: true`, but the stderr stream is consumed in a manual async loop that closes `logFile` in its `finally` block. If stderr finishes before stdout, the log file is closed while stdout is still writing. If stdout finishes first, the writable is never properly closed (because `preventClose: true` means the pipe won't close it).

```typescript
this.childProcess.stdout.pipeTo(logFile.writable, { preventClose: true });
(async () => {
  try {
    for await (const chunk of this.childProcess!.stderr) {
      await logFile.write(chunk);
    }
  } finally {
    logFile.close(); // Closes while stdout may still be writing
  }
})();
```

**Recommendation:** Use `Promise.all` to wait for both stdout and stderr to finish, then close the log file. Or use a `WritableStream` tee to merge both streams into a single writer.

---

#### C6. Path traversal in topology preset loading and volume rendering
**Files:** `scripts/lib/deno/topology.ts:489-500, 554-558, 822-869`; `scripts/lib/deno/topology_compiler.ts:509-521, 583-588`

`loadTopologyPreset(name)` interpolates `name` directly into a filesystem path without sanitization. A malicious or malformed preset name (e.g., `../../etc/passwd`) could cause the harness to read arbitrary `.json` files as topology presets. Separately, `renderVolume()` and `renderSidecarService()` join preset-controlled relative paths without checking that the resolved path stays under `repoRoot` or the source clone directory. A malicious preset can therefore generate a compose file that bind-mounts arbitrary host paths into containers.

**Recommendation:** Restrict preset names to an allowlist/registry (already partially done via `topology_registry.ts`). Canonicalize every file path with `normalize()`/`relative()` and reject any path that escapes the allowed root. Reject absolute paths and any `..` traversal segments. Add tests for traversal attempts and malicious bind-mount/config-file paths.

---

### HIGH (12)

#### H1. `formatBytes` is duplicated 3 times
**Files:** `scripts/lib/deno/docker_api.ts:665-670`, `scripts/lib/deno/container_stats.ts:338-343`, `scripts/run_scenarios.ts:25-30`

The same function is copy-pasted in three files. Any bug fix or unit change must be applied three times.

**Recommendation:** Extract to a shared `scripts/lib/deno/format.ts` module.

---

#### H2. `run_scenarios.ts` is a 795-line monolith
**File:** `scripts/run_scenarios.ts`

This file contains: argument parsing, scenario discovery, network lifecycle management, scenario execution, result reporting, signal handling, and progress display. All concerns are interleaved, making it hard to test, modify, or reason about any single concern.

**Recommendation:** Decompose into:
- `cli.ts` — argument parsing and usage
- `scenario_discovery.ts` — finding and filtering scenarios
- `network_lifecycle.ts` — setup/teardown orchestration
- `scenario_executor.ts` — running individual scenarios with timeout
- `reporting.ts` — result aggregation and output

---

#### H3. Proxy-based agent returns `any` from all calls
**File:** `scripts/lib/deno/client.ts:101-163`

The `createAgentProxy` function returns `any`, meaning every method call on `client.agent.*` is completely untyped. Method names are only validated at runtime (via the XRPC call), and there's no autocomplete or compile-time checking.

```typescript
function createAgentProxy(path: string[], client: XrpcClient, session: AgentSession): any {
  return new Proxy(function () {}, {
    get(_target, prop: string) {
      // ...
      return createAgentProxy([...path, prop], client, session);
    },
    async apply(_target, _thisArg, args: any[]) {
      // ...
      const data = isQuery
        ? await client.rawTransport.get(method, params, token)
        : await client.rawTransport.post(method, params, token);
      return { data };
    },
  });
}
```

**Recommendation:** Generate a typed interface from the ATProto lexicon definitions, similar to how `@atproto/api` works. At minimum, add a typed facade for the most commonly used methods.

---

#### H4. `@ts-ignore` comments suppress type errors on `scenarioParams`
**File:** `scripts/scenario-dashboard/services/run_manager.ts:55-56, 158-159, 222-228`

Four `@ts-ignore` directives suppress type errors on `scenarioParams`, which is not declared on the `Run` type but is dynamically added. This means the type system cannot verify that `scenarioParams` is used correctly anywhere.

**Recommendation:** Add `scenarioParams` to the `Run` interface with the correct type. Remove the `@ts-ignore` directives.

---

#### H5. `ContainerEventWatcher.close()` has a 100ms race with the event loop
**File:** `scripts/lib/deno/docker_events.ts:356-362`

After calling `abortController.abort()`, the `close()` method races the event loop promise against a 100ms timeout. If the abort doesn't propagate within 100ms (which can happen on a busy Unix socket), the client is force-closed while the reader is still pending. This can cause:
- Unhandled promise rejections (though the global handler suppresses them)
- Resource leaks if the Rust HTTP client doesn't clean up

```typescript
await Promise.race([
  this.eventLoopPromise.then(() => {}, () => {}),
  new Promise<void>((resolve) => setTimeout(resolve, 100)),
]);
```

**Recommendation:** Increase the timeout to 500ms or 1s. Add a `finally` block that always calls `client.close()`. Log a warning if the timeout fires.

---

#### H6. `isPidAlive` uses `SIGCONT` as a liveness check
**File:** `scripts/scenario-dashboard/services/run_manager.ts:188-195`

Sending `SIGCONT` to a process to check if it's alive is a hack. `SIGCONT` resumes a stopped process — if the target process was stopped (e.g., via `SIGSTOP`), this would unintentionally resume it. The correct approach is to use signal 0 (which Deno doesn't support directly) or `Deno.Process.status`.

**Recommendation:** Use `Deno.Command("kill", ["-0", String(pid)])` to check liveness without side effects. Or check `/proc/{pid}` on Linux, or use `kill(pid, 0)` via FFI.

---

#### H7. Empty catch blocks silently swallow errors
**Files:** `scripts/lib/deno/container_stats.ts:165-167, 169-171`, `scripts/lib/deno/docker_events.ts:392-395, 546-548, 630-632`

Multiple catch blocks silently swallow errors with no logging. In `container_stats.ts`, if `listContainers()` or `containerStats()` fails, the sampler returns an empty array with no indication that data was lost. In `docker_events.ts`, `buildContainerMap()` failures are silently ignored.

**Recommendation:** At minimum, log the error at debug level. For critical paths, consider propagating the error or incrementing a failure counter.

---

#### H8. `BskyAgent` import is unused
**File:** `scripts/lib/deno/transport.ts:1`

`BskyAgent` is imported from `@atproto/api` but never used in the file. This is a dead dependency that adds unnecessary import time and bundle size.

**Recommendation:** Remove the import.

---

#### H11. Transport error handling loses context and has weak retry classification
**File:** `scripts/lib/deno/transport.ts:3-7, 39-58, 79-98, 101-176`

`request()` retries only thrown `fetch` errors, not transient HTTP statuses like `429/503`. The `XrpcError` stringifies arbitrary response bodies into the exception message, which can leak sensitive server output if the caller logs it. The raw error is rethrown without URL/method/attempt context, making debugging harder.

**Recommendation:** Introduce a typed transport error with `cause`, `method`, `url`, `status`, `attempt`, and a short redacted body snippet. Classify retryable status codes explicitly and retry only those.

---

#### H12. Silent catch-all paths hide real failures in startup/recovery/cleanup
**Files:** `scripts/lib/deno/docker_api.ts:255-269, 285-293, 566-573`; `scripts/lib/deno/docker.ts:208-231, 260-294, 371-377, 454-460, 525-527, 572-598, 627, 745-752`; `scripts/lib/deno/client.ts:68-74`; `scripts/scenario-dashboard/services/run_manager.ts:114-137`

Several helpers convert all errors into `false`, `undefined`, or a no-op. This makes daemon/socket/config problems look like "service not healthy" or disappear entirely, and makes recovery from a corrupt lock file impossible to diagnose.

**Recommendation:** Catch only expected benign errors. For everything else, return a structured failure reason or log the underlying cause once. In recovery paths, validate and surface file/JSON errors instead of swallowing them.

---

#### H13. Run-manager state transitions are race-prone with no mutex
**File:** `scripts/scenario-dashboard/services/run_manager.ts:25-69, 73-110, 176-178, 260-274`

`startRun()` has no mutex, so concurrent requests can both pass `if (this.activeRun)` before either sets state. The lock file is written by overwrite, not atomic rename, so a crash can leave DB and filesystem state inconsistent.

**Recommendation:** Serialize run state transitions behind a mutex or queue. Write lock files atomically via temp file + rename. Validate the lock file schema before trusting it.

---

#### H9. Proxy agent can become accidentally thenable
**File:** `scripts/lib/deno/client.ts:101-163`

The `createAgentProxy` uses a `Proxy` with a `get` trap. If any code accesses `client.agent.then`, the proxy returns another proxy — which makes the agent look like a thenable object. JavaScript engines will treat any object with a `then` method as a Promise, causing unexpected behavior when the agent is used in `await` expressions or Promise chains. Similarly, `constructor`, `inspect`, and `toJSON` could behave unexpectedly.

```typescript
// This will accidentally resolve as a Promise:
const result = await client.agent; // Triggers .then() trap
```

**Recommendation:** Special-case `then` in the `get` trap to return `undefined`, preventing the proxy from being treated as thenable. Also special-case `constructor`, `inspect`, and `toJSON`.

---

#### H10. Character registry is global mutable state — not re-entrant
**File:** `scripts/lib/deno/config.ts:48-170`

`BASE_CHARACTERS` captures `PDS1`/`PDS2` at import time, and `resetCharacters()` only rebuilds from that static template. The registry (`registry`) is module-global and mutable — scenario code mutates shared `Character` objects in place (e.g., `luna.did = session.did`). This works in today's sequential runner, but:
- Changing topology env vars after import won't propagate into rebuilt characters
- If scenarios ever run in parallel, shared mutable state will cause data races
- `resetCharacters()` only rebuilds from the original template, not from current env

**Recommendation:** Make character construction pure and parameterized by the current topology/env. Return fresh immutable character objects per scenario, or deep-clone on access. Avoid shared mutable registry state.

---

### MEDIUM (18)

#### M1. Manual YAML string building in topology_compiler.ts
**File:** `scripts/lib/deno/topology_compiler.ts` (renderComposeYaml function)

The compose YAML is built by concatenating strings with template literals. This is fragile — if any value contains YAML special characters (colons, quotes, newlines), the output will be malformed. While this is only used for Docker Compose files (not user-facing), a malformed YAML could cause Docker Compose to fail silently or misconfigure containers.

**Recommendation:** Use a YAML serialization library (e.g., `yaml` from npm or `@std/yaml`). If string building is kept, add escaping for values that could contain special characters.

---

#### M2. `TransportLayer.request()` returns `any` for all responses
**File:** `scripts/lib/deno/transport.ts:39-60`

The `request()` method parses the response body as JSON but returns `{ status, body }` where `body` is typed as `any`. This means all downstream consumers (the per-domain clients, the agent proxy) lose type information.

**Recommendation:** Add a generic type parameter: `request<T>(method, url, options): Promise<{ status: number, body: T }>`. The per-domain clients can then specify the expected return type.

---

#### M3. Hardcoded secrets in topology_compiler.ts
**File:** `scripts/lib/deno/topology_compiler.ts`

Secrets like `PDS_ADMIN_PASSWORD`, `PDS_MASTER_SECRET`, and `SIGNOZ_TOKENIZER_JWT_SECRET` are hardcoded as default values. While these are local development secrets, they appear in source code and could accidentally be committed to production configs.

**Recommendation:** Move all secrets to environment variables with no defaults. Fail loudly if required secrets are not set. At minimum, add a comment explaining that these are local-dev-only.

---

#### M4. `XrpcClient.adminLogin()` has a hardcoded default password
**File:** `scripts/lib/deno/client.ts:54`

```typescript
async adminLogin(password = "test-admin-password"): Promise<string> {
```

The default password is hardcoded in the client library. Any code that calls `adminLogin()` without arguments will use this password.

**Recommendation:** Remove the default. Require the password to be passed explicitly.

---

#### M5. `config.ts` has hardcoded character passwords
**File:** `scripts/lib/deno/config.ts:48-139`

All character passwords are hardcoded (`luna_pass_123`, `admin_pass_123`, etc.). While these are test accounts, they're committed to source control and could be used in production-like environments.

**Recommendation:** Generate passwords from environment variables or a secrets file. Use `crypto.randomUUID()` for test accounts if no specific password is needed.

---

#### M6. `ContainerStatsSampler.start()` fires initial sample synchronously
**File:** `scripts/lib/deno/container_stats.ts:119-121`

```typescript
start(): void {
  if (this.running) return;
  this.running = true;
  this.timerId = setInterval(() => this.sample(), this.intervalMs);
  this.sample(); // Fires synchronously — caller can't await
}
```

The initial `sample()` call is fire-and-forget. If the caller needs to know when the first sample is complete (e.g., to verify metrics are being collected), there's no way to await it.

**Recommendation:** Return a `Promise<void>` from `start()` that resolves after the first sample completes.

---

#### M7. `selectScenarios` is exported from `run_scenarios.ts`
**File:** `scripts/run_scenarios.ts` (imported in `topology_compiler_test.ts:12`)

The test file imports `selectScenarios` from `run_scenarios.ts`, which means the 795-line monolith must be loaded just to test scenario selection logic. This creates a heavy dependency chain for testing.

**Recommendation:** Extract `selectScenarios` to a separate module (e.g., `scenario_discovery.ts`).

---

#### M8. `ContainerStatsSampler.recordMetrics()` creates new instruments on every call
**File:** `scripts/lib/deno/container_stats.ts:236-283`

The `recordMetrics()` method calls `recordGauge()` and `recordCounter()` on every sample, which internally calls `getMeter()` → `createGauge()` / `createCounter()` on every invocation. While the meter is cached, the instrument creation may not be idempotent depending on the OTel SDK implementation.

**Recommendation:** Use the cached `createGauge()` / `createCounter()` instruments from the constructor, and call `.record()` / `.add()` directly on them.

---

#### M9. `AgentSession` stores credentials in a plain object
**File:** `scripts/lib/deno/client.ts:87-92`

The `AgentSession` class stores `accessJwt`, `refreshJwt`, and `did` as plain properties on a class instance. These are sensitive credentials that could be logged or serialized accidentally.

**Recommendation:** Mark the session as non-serializable. Use a `WeakRef` or `#private` field to prevent accidental exposure.

---

#### M10. `waitForServiceHealthy` creates a new watcher for each call
**File:** `scripts/lib/deno/docker_events.ts:652-667`

The convenience function creates a new `ContainerEventWatcher` (and thus a new Docker API client, event stream, and container map) for each call. If called multiple times in sequence, this is wasteful.

**Recommendation:** Accept an optional `ContainerEventWatcher` parameter. If provided, reuse it instead of creating a new one.

---

#### M11. `topology_compiler.ts` test has hardcoded repo path
**File:** `scripts/lib/deno/topology_compiler_test.ts:260, 268, 279, 305, 325, 349, 421, 449, 466, 680`

Multiple tests hardcode `/Users/jack/Software/garazyk` as the repo root. This makes the tests non-portable.

**Recommendation:** Use `import.meta.resolve` or `Deno.cwd()` to determine the repo root dynamically.

---

#### M12. `timedCall()` returning null is a footgun for cascading failures
**File:** `scripts/lib/deno/runner.ts:154-180`

`timedCall()` records the failure and returns `null` instead of propagating. This makes it easy for scenario code to keep marching after a failed prerequisite, generating cascaded noise and hiding the original fault. The `expectFailure` path also returns `null`, so callers have to remember to inspect `result.failed` or the return value manually.

```typescript
const session = await timedCall(result, "Create account", async () => { ... });
if (session) {
  luna.did = session.did; // Only runs if account creation succeeded
} else {
  result.finish();
  return result; // Must remember to bail out manually
}
```

**Recommendation:** Return a discriminated outcome object (`{ ok, value, error }`) or make propagation configurable. For critical setup steps, fail fast rather than continuing with nulls.

---

#### M13. Missing manifest entries silently fall back to `{}`
**File:** `scripts/lib/deno/scenario_metadata.ts:64-98`

The runner silently falls back to `{}` for missing manifest entries. If a new scenario file is added without a corresponding manifest, it can run without its declared requirements, timeout, or browser flow metadata. This weakens topology gating and makes it easier for scenario selection to drift from reality.

**Recommendation:** Warn or fail when a discovered scenario has no manifest entry. Even better, co-locate manifest export with the scenario module so the file and its metadata cannot diverge.

---

#### M14. Scenarios use fixed sleeps instead of waiting for observable state
**Files:** `scripts/scenarios/scenarios/02_social_graph.ts:129`, `scripts/scenarios/scenarios/05_federation.ts:215`

Hard-coded waits are flaky under load and on slower CI machines. They turn propagation timing into a guess instead of an assertion.

**Recommendation:** Poll for the specific state change: follow records visible, relay upstreams updated, AppView backfill advanced, etc. Use bounded retries with diagnostics, not fixed sleeps.

---

#### M15. Client query encoding is inconsistent across wrappers
**Files:** `scripts/lib/deno/transport.ts:62-74`, `scripts/lib/deno/clients/feed.ts:50-79`, `scripts/lib/deno/clients/graph.ts:58-66`, `scripts/lib/deno/clients/admin.ts:32-35`

`TransportLayer.get()` serializes arrays as repeated query params, but some domain clients override that and join arrays with commas, while `AdminClient.getLabels()` uses a `uris[]` shape. This makes endpoint encoding ad hoc and harder to reason about when lexicon expectations differ.

**Recommendation:** Centralize parameter serialization and keep it lexicon-driven. If an endpoint needs repeated params, encode that explicitly in one place rather than spreading special cases across clients.

---

#### M16. Scenario error handling downgrades required service failures to skips
**Files:** `scripts/scenarios/scenarios/01_account_lifecycle.ts:79-90`, `scripts/scenarios/scenarios/05_federation.ts:136-146`, `scripts/scenarios/scenarios/07_blobs_uploads.ts:212-228`

Skipping on unexpected exceptions is fine for optional features, but these checks often gate core infrastructure. If PLC, relay, or AppView is broken, a skip can make the scenario look partially healthy instead of clearly failed.

**Recommendation:** Reserve `stepSkipped` for optional capabilities explicitly declared in metadata. For required steps and assertions, fail the step and abort or clearly mark the scenario failed.

---

#### M17. `run_manager.ts` lock file has a TOCTOU race
**File:** `scripts/scenario-dashboard/services/run_manager.ts:62-63`

The `startRun()` method checks `this.activeRun` in memory, then writes a lock file. If two dashboard instances are running simultaneously, both could pass the in-memory check before either writes the lock file.

**Recommendation:** Use `Deno.open()` with `createNew: true` (which fails atomically if the file exists) for the lock file. Check the return value to detect conflicts.

---

#### M18. `any` is pervasive — 97 occurrences across 25 files
**Files:** `scripts/lib/deno/transport.ts`, `scripts/lib/deno/otel.ts`, `scripts/lib/deno/topology.ts`, `scripts/lib/deno/topology_compiler.ts`, `scripts/lib/deno/client.ts`, `scripts/scenario-dashboard/services/run_manager.ts`

The security review counted **97 `any` occurrences across 25 files** in the Deno scripts tree, with the heaviest concentration in the transport/OTel/topology layers. `any` and `@ts-ignore` suppress checks on HTTP bodies, tracer APIs, adapter shapes, and DB rows.

**Recommendation:** Replace `any` with typed interfaces or `unknown` plus explicit narrowing at the boundary. Remove `@ts-ignore` by extending the model types or adding a proper DB row mapper.

---

#### M19. Topology compiler input validation is incomplete
**Files:** `scripts/lib/deno/topology.ts:433-452, 489-525`; `scripts/lib/deno/topology_compiler.ts:63-106, 236-373`

The validator checks presence/duplication, but not path confinement or dangerous scalar content. That leaves room for traversal, malformed compose output, and fragile parsing.

**Recommendation:** Add a validation pass for every path-like field, every env/build-arg scalar, and every generated service/network name before rendering or writing artifacts.
**File:** `scripts/scenario-dashboard/services/run_manager.ts:62-63`

The `startRun()` method checks `this.activeRun` in memory, then writes a lock file. If two dashboard instances are running simultaneously, both could pass the in-memory check before either writes the lock file.

**Recommendation:** Use `Deno.open()` with `createNew: true` (which fails atomically if the file exists) for the lock file. Check the return value to detect conflicts.

---

### LOW (10)

#### L1. `ScenarioResult.artifacts` and `.metadata` are typed as `Record<string, any>`
**File:** `scripts/lib/deno/runner.ts:23-24`

These fields accept any value, making it easy to accidentally store non-serializable data.

**Recommendation:** Type as `Record<string, unknown>` and add a serialization check in `toReport()`.

---

#### L2. `timedCall` catches `any` and extracts `.message`
**File:** `scripts/lib/deno/runner.ts:172-179`

The catch block casts the error to `any` and accesses `.message`. Non-Error throws (strings, numbers) will produce unhelpful failure messages.

**Recommendation:** Use `String(e)` as the fallback (which is already there), but also check for `Error` instances to get the stack trace.

---

#### L3. `DockerApiClient.requestJSON()` doesn't consume the response body on error
**File:** `scripts/lib/deno/docker_api.ts:531-534`

If `request()` returns a non-OK response, the body is consumed by `DockerApiError`. But if `requestJSON()` calls `request()` and the response is OK but not JSON, `resp.json()` will throw, and the response body won't be consumed.

**Recommendation:** Add a try/catch around `resp.json()` that consumes the body on parse failure.

---

#### L4. `ContainerStatsSampler` uses `any` for cached instruments
**File:** `scripts/lib/deno/container_stats.ts:99-100`

```typescript
private gauges: Record<string, any> = {};
private counters: Record<string, any> = {};
```

These are never actually used — the `recordMetrics()` method calls `recordGauge()` / `recordCounter()` directly instead of using the cached instruments.

**Recommendation:** Either use the cached instruments or remove the unused fields.

---

#### L5. `seed.ts` has a `createAccountOrLogin` that swallows errors
**File:** `scripts/lib/deno/seed.ts:43-54`

The function catches all errors from `createAccount` and falls back to `createSession`. This means any non-"already exists" error (network failure, invalid input) will silently trigger a login attempt.

**Recommendation:** Only catch `XrpcError` with status 400 and message containing "already exists". Re-throw all other errors.

---

#### L6. `AccountsClient.deleteSession` has an empty catch block
**File:** `scripts/lib/deno/clients/accounts.ts:41-46`

```typescript
async deleteSession(token: string) {
  try {
    await this.transport.post("com.atproto.server.deleteSession", undefined, token);
  } catch {
    // Best effort
  }
}
```

Even "best effort" operations should log failures at debug level.

**Recommendation:** Add `console.debug` logging.

---

#### L7. `RawClient.postRaw` throws if params are provided
**File:** `scripts/lib/deno/clients/raw.ts:35-45`

The method throws an error if `params` has any keys, but the error message doesn't suggest an alternative for the common case where the caller needs both binary data and query parameters.

**Recommendation:** Improve the error message to suggest using `xrpcGet` with a custom transport or adding params to the URL manually.

---

#### L8. `config.ts` `BASE_CHARACTERS` is typed as `Record<string, any>`
**File:** `scripts/lib/deno/config.ts:48`

The character templates lose all type information. A typo in a character property would not be caught at compile time.

**Recommendation:** Define a `CharacterTemplate` interface and type `BASE_CHARACTERS` as `Record<string, CharacterTemplate>`.

---

#### L9. `otel.ts` `shutdownTracing` just sleeps for 100ms
**File:** `scripts/lib/deno/otel.ts:293-305`

The shutdown function doesn't actually flush spans — it just yields the event loop for 100ms and hopes the SDK has exported them. This is unreliable.

**Recommendation:** Call the SDK's `shutdown()` method if available. If not, document that this is a best-effort flush.

---

#### L10. Docker runner `scenarioPath` should be canonicalized
**File:** `scripts/lib/deno/docker_runner.ts:35-85, 57-75`

The `docker run` invocation is safe from shell injection because it uses an argument array, and the repo is mounted read-only. However, `scenarioPath` is only string-replaced, not normalized or root-checked, so `..` segments could escape the mounted workspace inside the container.

**Recommendation:** Derive the relative path with `relative(repoRoot, scenarioPath)` and reject anything that starts with `..` or is absolute.
**File:** `scripts/lib/deno/otel.ts:293-305`

The shutdown function doesn't actually flush spans — it just yields the event loop for 100ms and hopes the SDK has exported them. This is unreliable.

**Recommendation:** Call the SDK's `shutdown()` method if available. If not, document that this is a best-effort flush.

---

### INFO (9)

#### I1. The sans-IO pattern in `docker_events.ts` is well-executed
**File:** `scripts/lib/deno/docker_events.ts:90-233`

`DockerEventParser` is a pure synchronous class that accepts events via `feed()` and returns `WatcherEvent` objects. It has no I/O, no async, and no dependencies — making it fully testable without Docker. This is a strong architectural choice.

---

#### I2. The topology preset system is well-designed
**Files:** `scripts/lib/deno/topology.ts`, `scripts/lib/deno/topology_compiler.ts`

The topology system supports multiple PDS implementations (Garazyk, reference-pds, allegedly-plc, appviewlite, happyview, parakeet) through a declarative preset system. The v2 manifest schema properly separates host and Docker runner environments. The `validateRoleCapability` and `normalizeTopologyPreset` functions enforce schema constraints at load time.

---

#### I3. The scenario metadata system is a good pattern
**File:** `scripts/lib/deno/scenario_metadata.ts`

The `SCENARIO_MANIFESTS` registry and the `isScenarioCompatible()` / `missingRequirements()` functions provide a clean way to match scenarios to topology capabilities. The role-scoped requirements (`plc:didResolution`, `relay:subscribeRepos`) are well-structured.

---

#### I4. The `container_stats_test.ts` is well-structured
**File:** `scripts/lib/deno/container_stats_test.ts`

The test file uses mock clients effectively, tests edge cases (missing networks, empty blkio stats), and verifies the memory pressure alert system. This is a good example of how to test Docker-dependent code without Docker.

---

#### I5. The `topology_compiler_test.ts` is comprehensive
**File:** `scripts/lib/deno/topology_compiler_test.ts`

With 30+ test cases covering validation, rendering, compilation, schema enforcement, and preset loading, this is the most thorough test file in the codebase. The "every topology preset" smoke test at line 670 is particularly valuable.

---

#### I6. The `ContainerEventWatcher` dual-path waiting is pragmatic
**File:** `scripts/lib/deno/docker_events.ts:562-635`

The `waitForViaInspectOrEvents` method combines event-based waiting with periodic inspect polling. This is a practical response to Docker's unreliable health_status events. The comment at line 557-561 explains the reasoning clearly.

---

#### I7. SQL injection was not observed in `run_manager.ts`
**File:** `scripts/scenario-dashboard/services/run_manager.ts:147-173, 282`

The DB layer uses prepared statements with placeholders. The real risk in this file is concurrency/state inconsistency, not SQL injection.

---

#### I8. Docker socket handling is not command-injection prone
**File:** `scripts/lib/deno/docker_api.ts:556-578`

The socket path is passed directly to `Deno.createHttpClient` and never interpolated into a shell command. The main issue is trust boundary/validation, not shell injection.

---

#### I9. Redundant `catch (e) { throw e; }` in client.ts
**File:** `scripts/lib/deno/client.ts:153-160`

The `apply` trap in the proxy agent catches an error only to immediately rethrow it. This is a no-op that adds unnecessary indentation.

**Recommendation:** Remove the try/catch block entirely.
**File:** `scripts/lib/deno/docker_events.ts:562-635`

The `waitForViaInspectOrEvents` method combines event-based waiting with periodic inspect polling. This is a practical response to Docker's unreliable health_status events. The comment at line 557-561 explains the reasoning clearly.

---

## Per-Subsystem Summary

### Docker Layer (`docker_api.ts`, `docker.ts`, `docker_events.ts`, `docker_runner.ts`)

| Finding | Severity | File |
|---------|----------|------|
| Global unhandledrejection handler | CRITICAL | docker_events.ts:42 |
| 100ms close race condition | HIGH | docker_events.ts:356 |
| Empty catch blocks | HIGH | docker_events.ts:392, 546, 630 |
| `formatBytes` duplication | HIGH | docker_api.ts:665 |
| One-shot watcher per call | MEDIUM | docker_events.ts:652 |

### Transport & Client (`transport.ts`, `client.ts`, `clients/`)

| Finding | Severity | File |
|---------|----------|------|
| Retries on POST | CRITICAL | transport.ts:39 |
| Unused `BskyAgent` import | HIGH | transport.ts:1 |
| Error handling loses context | HIGH | transport.ts:3-58 |
| Silent catch-all paths | HIGH | docker_api.ts, docker.ts, client.ts |
| `any` return type | MEDIUM | transport.ts:39 |
| Proxy agent returns `any` | HIGH | client.ts:101 |
| Proxy agent accidentally thenable | HIGH | client.ts:101 |
| Hardcoded admin password | MEDIUM | client.ts:54 |
| `AgentSession` plain credentials | MEDIUM | client.ts:87 |
| Inconsistent query encoding | MEDIUM | transport.ts, feed.ts, graph.ts, admin.ts |
| `deleteSession` empty catch | LOW | accounts.ts:41 |
| `createAccountOrLogin` swallows errors | LOW | seed.ts:43 |
| Redundant catch-then-rethrow | INFO | client.ts:153 |

### OTel (`otel.ts`, `container_stats.ts`)

| Finding | Severity | File |
|---------|----------|------|
| `withSpanSync` is broken | CRITICAL | otel.ts:213 |
| `shutdownTracing` just sleeps | LOW | otel.ts:293 |
| `start()` fires sample synchronously | MEDIUM | container_stats.ts:119 |
| Unused cached instruments | LOW | container_stats.ts:99 |
| Empty catch blocks | HIGH | container_stats.ts:165 |

### Scenario Runner (`run_scenarios.ts`, `runner.ts`, `scenario_metadata.ts`)

| Finding | Severity | File |
|---------|----------|------|
| 795-line monolith | HIGH | run_scenarios.ts |
| `Deno.exit(0)` | CRITICAL | run_scenarios.ts:781 |
| `formatBytes` duplication | HIGH | run_scenarios.ts:25 |
| `selectScenarios` in monolith | MEDIUM | run_scenarios.ts |
| `timedCall` catches `any` | LOW | runner.ts:172 |
| `timedCall` null return footgun | MEDIUM | runner.ts:154 |
| Missing manifest entries silent | MEDIUM | scenario_metadata.ts:64 |
| Fixed sleeps instead of polling | MEDIUM | 02_social_graph.ts, 05_federation.ts |
| Required failures downgraded to skips | MEDIUM | 01, 05, 07 scenarios |

### Config (`config.ts`)

| Finding | Severity | File |
|---------|----------|------|
| Character registry global mutable state | HIGH | config.ts:48-170 |
| Hardcoded character passwords | MEDIUM | config.ts:48-139 |
| `BASE_CHARACTERS` typed as `Record<string, any>` | LOW | config.ts:48 |

### Topology (`topology.ts`, `topology_compiler.ts`, `topology_schema.ts`)

| Finding | Severity | File |
|---------|----------|------|
| Path traversal in preset loading | CRITICAL | topology.ts:489, topology_compiler.ts:509 |
| Manual YAML string building | MEDIUM | topology_compiler.ts |
| Hardcoded secrets | MEDIUM | topology_compiler.ts |
| Hardcoded repo path in tests | MEDIUM | topology_compiler_test.ts |
| Incomplete input validation | MEDIUM | topology.ts:433, topology_compiler.ts:63 |

### Dashboard (`run_manager.ts`)

| Finding | Severity | File |
|---------|----------|------|
| Stdout pipe leaks writable | CRITICAL | run_manager.ts:244 |
| `@ts-ignore` on scenarioParams | HIGH | run_manager.ts:55,158,222 |
| `isPidAlive` uses SIGCONT | HIGH | run_manager.ts:188 |
| State transitions race-prone | HIGH | run_manager.ts:25-69 |
| Lock file TOCTOU race | MEDIUM | run_manager.ts:62 |
| Silent catch in recovery | HIGH | run_manager.ts:114-137 |

### Test Coverage

| Module | Has Tests | Coverage |
|--------|-----------|----------|
| `docker_api.ts` | Yes (docker_api_test.ts) | Skips without Docker; no unit tests for parsing |
| `docker_events.ts` | Yes (docker_events_test.ts) | Good sans-IO parser tests; no watcher lifecycle tests |
| `container_stats.ts` | Yes (container_stats_test.ts) | Good mock-based tests |
| `topology_compiler.ts` | Yes (topology_compiler_test.ts) | Comprehensive |
| `otel.ts` | Yes (otel_test.ts) | Only tests no-op path |
| `transport.ts` | **No** | — |
| `runner.ts` | **No** | — |
| `topology.ts` | **No** | — |
| `docker.ts` | **No** | — |
| `docker_runner.ts` | **No** | — |
| `client.ts` | **No** | — |
| `config.ts` | **No** | — |
| `run_manager.ts` | Yes (run_manager.test.ts) | Partial |

---

## Prioritized Action Items

### P0 — Fix immediately (safety/correctness)

1. **Remove `withSpanSync`** from `otel.ts` — it's broken and will produce incorrect tracing data
2. **Remove POST retries** from `TransportLayer.request()` — or make them opt-in only for idempotent methods
3. **Scope the unhandledrejection handler** to `ContainerEventWatcher` lifecycle — don't suppress global rejections
4. **Remove `Deno.exit(0)`** from `run_scenarios.ts` — fix the underlying resource leaks instead
5. **Fix the stdout/stderr pipe** in `run_manager.ts` — use `Promise.all` to coordinate both streams
6. **Sanitize topology preset names** — restrict to allowlist, canonicalize paths, reject `..` traversal

### P1 — Fix soon (maintainability/reliability)

7. **Extract `formatBytes`** to a shared module
8. **Decompose `run_scenarios.ts`** into 4-5 focused modules
9. **Add `scenarioParams` to the `Run` type** and remove `@ts-ignore` directives
10. **Replace `isPidAlive`** with a signal-0 check or process status check
11. **Add logging to empty catch blocks** in container_stats.ts and docker_events.ts
12. **Special-case `then` in the proxy agent** to prevent accidental thenability
13. **Make character construction pure** — parameterize by topology, return fresh objects
14. **Improve transport error handling** — typed errors with context, classify retryable status codes
15. **Add mutex to run_manager** — serialize state transitions, atomic lock file writes
16. **Add topology path validation** — validate path-like fields, env/build-arg scalars, service names

### P2 — Fix when convenient (type safety/cleanup)

13. **Add generic type parameter** to `TransportLayer.request()`
14. **Type the agent proxy** — at minimum, add a typed facade for common methods
15. **Remove hardcoded secrets** — use env vars with no defaults
16. **Remove unused `BskyAgent` import** from transport.ts
17. **Extract `selectScenarios`** from the monolith for testability
18. **Replace `timedCall` null return** with a discriminated outcome object
19. **Warn on missing manifest entries** for discovered scenarios
20. **Replace fixed sleeps with polling** in social graph and federation scenarios
21. **Centralize query parameter encoding** across domain clients
22. **Reserve `stepSkipped` for optional capabilities** — fail required steps instead

### P3 — Backlog (testing/quality)

23. **Add unit tests for `transport.ts`** — mock fetch, test retry logic, error classification
24. **Add unit tests for `runner.ts`** — test `timedCall`, `ScenarioResult`, report writing
25. **Add unit tests for `topology.ts`** — test `resolveTopology`, manifest creation
26. **Add tests for the OTel enabled path** — mock the OTel API, verify span creation
27. **Fix hardcoded repo paths** in topology_compiler_test.ts

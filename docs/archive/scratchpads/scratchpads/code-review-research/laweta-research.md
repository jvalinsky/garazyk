# Laweta: Docker Engine API over Unix Socket — Research Plan

## Package Summary
Generic Docker Engine API client over Unix socket using `Deno.createHttpClient`. No ATProto-specific code. Pure Docker primitives.

## Key Techniques
1. **Unix socket HTTP proxy** — `Deno.createHttpClient({ proxy: { transport: "unix", path } })`
2. **NDJSON stream parsing** — `parseNdjsonStream<T>()` for `/events` and `/stats?stream=true`
3. **Docker log multiplexing** — 8-byte frame header demux (stdout/stderr split)
4. **Sans-IO event parser** — `DockerEventParser` is pure synchronous, `ContainerEventWatcher` is I/O shell
5. **Promise-based health waiting** — `waitForHealthy()` with event+inspect hybrid fallback
6. **OTel telemetry hooks** — `withSpan()`, `recordGauge()`, `recordCounter()` via test hook injection
7. **Container stats sampling** — `ContainerStatsSampler` with memory pressure detection (failcnt)
8. **Port conflict detection** — `findPortConflicts()` via single `listContainers` call

## Research Queries (for sub-agents)

### Q1: Deno Unix socket HTTP client stability
- Search: "Deno createHttpClient unix socket proxy stability issues 2025 2026"
- Search: "Deno 2 unix socket HTTP client breaking changes"
- Focus: Any known issues with `Deno.createHttpClient` for Unix socket proxy, especially around connection pooling, resource leaks, or abort behavior

### Q2: Docker Engine API v1.43 completeness
- Search: "Docker Engine API v1.43 changes deprecated endpoints"
- Search: "Docker Engine API streaming events best practices"
- Focus: Are there API changes in newer Docker versions that affect the endpoints used? Is v1.43 still the right target?

### Q3: NDJSON stream parsing edge cases
- Search: "NDJSON parsing edge cases partial lines buffer overflow"
- Search: "Docker events stream NDJSON parsing best practices"
- Focus: Known issues with Docker's NDJSON streams (partial reads, encoding, backpressure)

### Q4: Docker log multiplexing protocol correctness
- Search: "Docker log stream multiplexing protocol 8-byte header parsing"
- Search: "Docker container logs TTY vs non-TTY demux edge cases"
- Focus: Correctness of the multiplexed frame detection heuristic (`isMultiplexedLogBuffer`), partial frame handling

### Q5: Sans-IO pattern in TypeScript/JavaScript
- Search: "sans-IO pattern TypeScript library design"
- Search: "separate protocol logic from I/O TypeScript best practices"
- Focus: Best practices for sans-IO design in JS/TS, testing patterns, reference implementations

### Q6: Container health check event reliability
- Search: "Docker health_status event unreliable missed events"
- Search: "Docker container health check event stream vs polling tradeoffs"
- Focus: Known issues with Docker health events being unreliable (the code already has inspect polling fallback — is this documented?)

## Code Review Concerns to Investigate
- `detectSocketPath()` uses `Deno.statSync()` — synchronous I/O on module load path
- `parseNdjsonStream` catches and logs malformed lines silently — could mask real issues
- `ContainerEventWatcher.close()` has a 100ms race timeout — could leak resources
- `waitForViaInspectOrEvents` creates `setInterval` that may never be cleaned if the promise is GC'd
- `findPortConflicts` iterates all containers' ports — O(n*m) but likely fine for test harness scale
- `telemetry.ts` `withSpan` is a no-op passthrough — is the OTel integration actually complete?

## Deciduous Link
- Node 281: laweta action

# Hamownia: Scenario Orchestration, Process Lifecycle, OTel — Research Plan

## Package Summary
Assertion-based E2E testing framework for AT Protocol simulations. Runs scenarios in host-child processes or Docker containers, with crash detection, progress tracking, and OTel instrumentation.

## Key Techniques
1. **Scenario context injection** — `ScenarioContext` replaces mutable config globals
2. **Host-child process runner** — Spawns `deno run -A` child processes with timeout + SIGTERM/SIGKILL
3. **Docker runner mode** — `runScenarioInDocker()` for containerized execution
4. **Crash detection via event watcher** — `ContainerEventWatcher` subscription in run loop
5. **OTel stats sampling** — `ContainerStatsSampler` with memory pressure alerts
6. **Mock Twilio server** — `MockTwilioServer` for phone verification flows
7. **Progress bar with duration cache** — `ProgressBar` + `DurationCache` for ETA estimation
8. **Scenario metadata/requirements** — `ScenarioManifest` with capability requirements
9. **Browser flow testing** — `attachPublicNetworkLeakGuard()` for network isolation
10. **Diagnostics collection** — `collectDiagnostics()` for post-failure analysis

## Research Queries (for sub-agents)

### Q1: Deno child process management best practices
- Search: "Deno.Command spawn child process timeout SIGTERM SIGKILL"
- Search: "Deno child process resource cleanup timeout patterns"
- Focus: The host-child runner spawns `deno run -A` — is this safe? Timeout handling, zombie process prevention, temp dir cleanup

### Q2: E2E test framework scenario runner patterns
- Search: "E2E test framework scenario runner architecture patterns"
- Search: "test harness scenario orchestration crash detection retry"
- Focus: Best practices for scenario runners — isolation, timeout, retry, parallel execution, result aggregation

### Q3: Mock server patterns for testing
- Search: "Deno HTTP mock server testing patterns"
- Search: "mock Twilio server phone verification testing"
- Focus: The `MockTwilioServer` — is it thread-safe? Does it handle concurrent requests? State cleanup between scenarios?

### Q4: Browser testing network isolation
- Search: "Deno browser testing network isolation leak guard"
- Search: "Playwright network request interception blocking public hosts"
- Focus: `attachPublicNetworkLeakGuard()` — how does it work? Is it effective? Can it be bypassed?

### Q5: OTel instrumentation in test harnesses
- Search: "OpenTelemetry test harness instrumentation patterns"
- Search: "OTel Deno integration tracing metrics test framework"
- Focus: The `otel.ts` module — is it a complete OTel integration or just stubs? How does it connect to the SigNoz stack?

### Q6: Scenario result reporting and aggregation
- Search: "test result JSON report format best practices"
- Search: "E2E test result aggregation timeout crash handling"
- Focus: `ScenarioResult` + `StepResult` — is the report format complete? Can it handle partial results from crashes?

## Additional Code Review Concerns (from deep survey)
- `host_child_runner.ts` uses dynamic `import()` with query-string cache busting — can hide module-load issues
- `atproto_network.ts` has complex branching and many side effects; health/wait logic spread across modes
- `binary_services.ts` opens log files and pipes streams without awaiting pipe completion
- `docker_runner.ts` container cleanup is best-effort and timeout-driven
- `account_discovery.ts` SQL string interpolation for LIMIT clause — safe-ish but sensitive pattern
- `mock_twilio.ts` `MockState` is declared twice; control endpoints expose mutable state over HTTP
- `otel.ts` environment variables are mutated at runtime; some APIs create instruments on each call rather than caching
- `report_writer.ts` fatal error folded into JSON counts but not returned aggregate totals
- `run_command.ts` large control flow with multiple early returns; re-exec logic depends on env-guard discipline
- `stale_cleanup.ts` uses `lsof`, `ps`, `kill` — may not exist on all platforms; false positives possible
- `scenario_selector.ts` uses `Deno.exit(1)` for fatal errors — hard to reuse programmatically
- `runner.ts` `ok` requires at least one step — empty results marked as not OK; timestamps are seconds vs ms inconsistency
- `cli/demo.ts` lots of secrets defaulted/generated inline; cleanup conditional
- `cli/service.ts` `logs` tails a file without ensuring it exists; `reseed` wipes data recursively
- `ops_command.ts` security-sensitive: path sanitization, DID validation, SQL generation, Cloudflare API calls; `runBackup` doesn't inspect tar exit code

## Deciduous Link
- Node 284: hamownia action

# Hamownia Package Codebase Review: Research Findings

## Executive Summary
This document synthesizes research on best practices, common pitfalls, and reference implementations relevant to the `hamownia` scenario orchestration package. The findings cover process lifecycle management in Deno, architectural patterns for E2E test runners, network mocking and interception, observability, and reporting formats. This context is intended to guide the architectural and code-level review of the package.

## 1. Process Lifecycle Management (Deno)

When spawning child processes (e.g., test runners, isolated service nodes), managing timeouts and graceful termination is critical to prevent resource leaks and zombie processes.

**Best Practices:**
*   **AbortSignal Integration:** The idiomatic way to handle timeouts in Deno for `Deno.Command` is using `AbortSignal.timeout(ms)`. This provides a clean API that automatically sends a `SIGTERM` when the timeout is reached.
*   **Manual Control:** For scenarios requiring conditional termination, use `AbortController` and pass its `signal` to `Deno.Command`. This allows terminating the child process if a specific event occurs before the timeout.
*   **Error Handling:** When a process is aborted via a signal, the `output()` promise rejects with a `DOMException` (`name: "AbortError"`). The orchestration package must specifically catch this to differentiate a timeout from a standard process crash.

**Pitfall:** `Deno.Command.outputSync()` does not support `AbortSignal` as it blocks the event loop. Always use the asynchronous API for child processes requiring timeout control.

## 2. Scenario Runner Architecture Patterns

A robust E2E test runner must decouple test logic from infrastructure. The architecture of `hamownia` should be evaluated against these established patterns:

*   **Command/Template Method Patterns:** Scenarios should be treated as "Commands" that move through a defined lifecycle (Setup -> Execute -> Validate -> Teardown). The orchestrator handles the flow, retry logic, and logging, while the scenarios define the specifics.
*   **Observer Pattern for Telemetry:** The runner should emit discrete events (e.g., `scenario:start`, `step:fail`, `process:timeout`) that reporters and observability sinks (like OpenTelemetry) can subscribe to, rather than tightly coupling execution and logging.
*   **State & Dependency Management:** Use Dependency Injection (DI) or context passing to provide scenarios with necessary "Abilities" (e.g., initialized API clients, database fixtures, or Playwright browser instances). Avoid global shared state, especially if running scenarios in parallel.
*   **Screenplay / Facade Patterns:** For complex workflows, prefer composing reusable tasks or facades over raw imperative steps to improve the maintainability of the scenarios.

## 3. Network Mocking & Request Interception

Controlling the network boundary is essential for reliable, non-flaky scenarios.

### Deno HTTP Mock Server Testing
*   **Real Local Servers (Integration):** When testing the full HTTP stack, use `Deno.serve({ port: 0 })` to dynamically bind to available ports, avoiding parallel test collisions.
*   **Resource Management:** Always bind the local server to an `AbortController.signal` and trigger `abort()` in a `finally` block to prevent Deno test runner resource leak warnings.
*   **Unit Mocks:** For lower-level unit tests, `stub(globalThis, "fetch", ...)` from `@std/testing/mock` is preferred over full network emulation.

### Playwright Interception
When `hamownia` orchestrates browser automation, preventing external network calls (e.g., third-party tracking, external CDNs) stabilizes tests and reduces execution time.
*   **Best Practice:** Utilize Playwright's `page.route('**/*', handler)` to implement a strict network boundary.
*   **Implementation Pattern:** Check if the request URL matches the internal cluster or mock server (e.g., `url.startsWith('http://localhost')`). If yes, `route.continue()`; otherwise, `route.abort()`.

## 4. Observability and OpenTelemetry (OTel) in Test Harnesses

Instrumenting the test harness itself provides deep insights into scenario failures and performance bottlenecks.

*   **In-Memory Exporters for Assertions:** Use `InMemorySpanExporter` and `SimpleSpanProcessor` (not `BatchSpanProcessor`, which introduces delays) to synchronously capture spans during a scenario run. This allows the runner to assert that specific internal trace events occurred.
*   **Trace-Based Testing:** When scenarios involve multiple distributed services, the runner can capture the `traceId` and query the backend (e.g., Jaeger) to validate the entire execution path.
*   **Context Propagation:** The test runner must actively inject trace context into HTTP headers (W3C Trace Context) and CLI arguments (for spawned child processes) to ensure the scenario's telemetry is stitched to the orchestrator's telemetry.

## 5. Test Result JSON Report Formats

When standardizing output for downstream consumption (e.g., CI/CD dashboards, log aggregators), `hamownia` should adhere to industry-standard JSON schema structures.

**Key Requirements for the Schema:**
*   **Hierarchical Structure:** `Run -> Suites (Scenarios) -> Tests (Steps)`.
*   **Essential Fields per Step:** Status (`passed`, `failed`, `skipped`), duration (ms), start/end timestamps, and error traces.
*   **Contextual Metadata:** Environment variables, git commit hash, and random seeds (if applicable) must be included at the root level to guarantee reproducibility.
*   **Artifact Linkage:** Attachments (e.g., paths to screenshots, Playwright traces, network dumps) should be structured as arrays of objects linked to the specific failing step.

## Next Steps for Code Review
1. Review the `Deno.Command` usage in `hamownia` to ensure `AbortSignal` is properly utilized for lifecycle safety.
2. Evaluate if the runner effectively isolates scenario state and handles resource cleanup (`finally` blocks, aborting mock servers).
3. Check the reporting and telemetry hooks to ensure they are decoupled from the core execution loop (e.g., using an Observer pattern).

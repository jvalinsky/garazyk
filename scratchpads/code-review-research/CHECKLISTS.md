# Garazyk Code Review: Master Checklist

This document synthesizes the code review checklists for all six packages based on deep research into best practices, known pitfalls, and structural vulnerabilities.

## 1. Laweta (Docker Engine API over Unix socket)
- [ ] **Unix Socket Stability:** Ensure `Deno.createHttpClient` strictly manages connections to prevent `EMFILE` or native Rust memory leaks; `client.close()` must be called deterministically.
- [ ] **Log Stream Multiplexing:** Verify the 8-byte header parser correctly handles network fragmentation and does not misalign if chunks split midway through a header.
- [ ] **NDJSON Edge Cases:** Check for buffer bounds on partial lines to prevent OOM/DoS, and ensure escaped `\n` characters don't break the JSON payload splits.
- [ ] **Sans-IO Architecture:** Ensure `DockerEventParser` is fully decoupled from the socket implementation, making it testable via pure byte arrays.
- [ ] **Health Status Fallback:** The standalone Docker `health_status` event is known to be unreliable; verify the package actively polls `State.Health` as a fallback.

## 2. Gruszka (XRPC Client, DAG-CBOR Firehose)
- [ ] **DAG-CBOR Safety Boundaries:** Ensure decoding of firehose frames enforces recursion limits and rejects prototype pollution keys (`__proto__`, `constructor`).
- [ ] **Proxy Type Inference:** Verify that the `AgentProxy` dynamic method chaining accurately maintains TypeScript inference without falling back to `any`.
- [ ] **Firehose Cursor Tracking:** The WebSocket consumer must track the sequence cursor to cleanly resume on disconnects without skipping or double-processing events.
- [ ] **Idempotent Retries:** Ensure `TransportLayer` only retries HTTP `GET` requests; blindly retrying `POST` operations can lead to duplicate mutations.
- [ ] **Lexicon Codegen Gap:** Investigate whether `createGeneratedClient()` aligns with modern `@atproto/lexicon` tooling or leaves type-safety gaps.

## 3. Hamownia (Scenario Orchestration)
- [ ] **Process Lifecycle:** Ensure `Deno.Command` execution uses `AbortSignal.timeout()` to guarantee reliable cleanup and prevent zombie processes.
- [ ] **Network Isolation:** Verify `attachPublicNetworkLeakGuard()` effectively blocks unexpected external traffic (via Playwright routes or Deno fetch stubs).
- [ ] **Synchronous Telemetry:** OpenTelemetry span processing in tests should prefer `SimpleSpanProcessor` to guarantee spans aren't dropped if the runner crashes.
- [ ] **Mock Server Leakage:** Ensure `MockTwilioServer` implements strict state cleanup between scenarios to prevent cross-contamination.
- [ ] **Result Determinism:** Review the `ScenarioResult` JSON output to ensure it accurately folds timeouts and crashes without leaving malformed or incomplete data.

## 4. Schemat (Topology & Docker Compose)
- [ ] **YAML Serializer:** Replace manual string concatenation with a robust YAML serializer to prevent injection attacks and quoting bugs with complex env variables.
- [ ] **Path Traversal Protection:** Ensure volume paths (`renderVolume()`) are validated against a trusted root and effectively block symlink/mount-point escapes.
- [ ] **Explicit Health Probes:** Change `extractContainerPort()` to read from an explicit health-port property rather than naively selecting the first published port.
- [ ] **Observability Hardcoding:** `renderSigNozServices()` should not hardcode floating `latest` tags; make the collector image and config path parameterizable.
- [ ] **Versioned Manifest Models:** Move away from hardcoded v1/v2 schema branches in favor of a robust, discriminated schema system for topology manifests.

## 5. Narzedzia (Static Analysis & Doc Coverage)
- [ ] **AST-Based Boundary Enforcement:** Regex-based import scanning (`importPattern`) cannot reliably handle type imports, aliases, and dynamic imports; evaluate an AST-backed approach.
- [ ] **Model-Based Doc Coverage:** Regex heuristics for Objective-C headers and TypeScript docs should be replaced with (or backed by) structured parser models to prevent drift.
- [ ] **Non-Destructive Defaults:** Header linting and doc migration tools should operate in read-only/check mode by default, mutating files only under a strict `--fix` flag.
- [ ] **Baseline Config Persistence:** `currentBaseline` should be loaded from a configuration file rather than hardcoded, allowing the CI to detect regressions against known limits.
- [ ] **Security Hotspots:** Review `ops_command.ts` closely to ensure path generation, SQL construction, and DID validation do not rely on free-form concatenations.

## 6. TUI (Terminal UI Layout & Theming)
- [ ] **Layout Tree Edge Cases:** Ensure `solveLayout()` defines explicit policies for remainder pixel distribution, min/max constraints, and overflow/clipping behaviors.
- [ ] **Strict Sans-IO Boundary:** Verify that the `ScreenBuffer` and rendering pipeline do not read environment variables (like `NO_COLOR`) natively during render calls; rely on injected config.
- [ ] **Resize Invalidation:** Confirm the layout solver and `ScreenBuffer` actively invalidate or resize their caches when terminal geometry changes.
- [ ] **Advanced Input Parsing:** Evaluate `parseKey()` coverage for CSI-u (Kitty protocol), bracketed paste, and ambiguous legacy sequences.
- [ ] **Grapheme-Aware Sizing:** Check `getCharWidth()` to ensure it properly handles CJK ambiguity, emoji, zero-width joiners, and combining marks, preventing alignment drift.
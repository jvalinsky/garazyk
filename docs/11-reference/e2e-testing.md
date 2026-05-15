---
title: End-to-End Testing
---

# End-to-End Testing

Garazyk uses narrative scenarios to validate workflows across the PDS, Relay, AppView, and PLC. These tests exercise the full stack, from HTTP requests to database persistence.

## Testing Strategy

1. **Unit Tests:** Individual components (`XCTest`).
2. **Integration Tests:** Multiple components and database interactions (`XCTest` + `PDSDatabase`).
3. **Scenarios:** Narrative-driven, multi-service workflows (Deno + TypeScript).
4. **Interoperability:** AT Protocol specification compliance.

## Scenarios

Scenarios orchestrate a local Docker network and use the shared `XrpcClient` in `scripts/lib/deno/`. They record timing data and generate JSON reports.

### Running Scenarios
Use `run_scenarios.ts` to manage execution:

```bash
# List all scenarios
./scripts/run_scenarios.ts --list

# Run a specific scenario by ID
./scripts/run_scenarios.ts 01

# Start services, run all scenarios, and tear down
./scripts/run_scenarios.ts --setup --teardown
```

## Objective-C Integration Tests

Low-level database and concurrency verification still use Objective-C tests in `Garazyk/Tests/`.

### PLC Integration
Located in `Garazyk/Tests/plc_e2e/`. These require a running PLC environment:

```bash
cd Garazyk/Tests/plc_e2e
docker compose up -d
./build/tests/AllTests -XCTest PLCServerTests
```

## Related

- [Deno Scenario Framework](./deno-scenario-framework)
- [Testing Map](./testing-map)
- [Documentation Map](./documentation-map)
- [Contributor Guide](../index.md)

# Garazyk Test Console

Project-local Pi extension for the Garazyk test workflow.

## Commands

- `/xtest list` — list classes registered in `Garazyk/Tests/test_main.m`.
- `/xtest <ClassName>` — run `./build/tests/AllTests -XCTest <ClassName>`.
- `/xtest <ClassName/testMethod>` — run one XCTest method.
- `/xtest audit-registration` — run `PDS_TEST_REGISTRATION_AUDIT=1 ./build/tests/AllTests`.
- `/testnav` — suggest focused tests from the current git diff.
- `/testnav <path> [...]` — suggest focused tests for explicit repository paths.
- `/test-registration` — check changed XCTest files against `test_main.m` registration.
- `/scenarios list` — list ATProto scenario simulations.
- `/scenarios setup [--binary] [--pds2]` — start the local scenario network.
- `/scenarios run <id> [...] [--pds2]` — run scenario IDs.
- `/scenarios report` — summarize latest scenario JSON reports.
- `/scenarios teardown [--binary]` — stop the scenario network.
- `/services` — check local PLC/PDS/Relay/AppView/PDS2 health.
- `/services logs <pds|plc|relay|appview|pds2>` — show binary-mode log tail.
- `/services teardown [--binary]` — stop scenario services.
- `/test-audit` — run `tooling/test-audit-validator` auto gate.
- `/test-audit clang` — run strict clang gate.
- `/test-audit summary` — summarize latest test-audit JSON report.

## Agent tool

- `garazyk_test_suggest` — suggests focused tests, scenarios, scripts, and fuzzers for changed files or explicit paths.

## Notes

The extension intentionally starts with explicit commands. It does not auto-run expensive tests, full quality gates, Docker setup, or fuzzers without a user command.

The registration guard also runs a soft warning after agent turns when changed `*Tests.m` files are not present in `test_main.m`.

---
title: Deno Scenario Framework
---

# Deno Scenario Framework

The Deno Scenario Framework (`scripts/scenarios/`) orchestrates integration tests against a local
Docker network to validate federation, OAuth flows, and AT Protocol interactions.

## Key Documents

| File | Description |
|---|---|
| `scripts/scenarios/README.md` | Scenario runner overview and quick start |
| `scripts/scenarios/SCENARIO_STANDARDS.md` | Authoring standards for new scenarios |
| `scripts/scenarios/topologies/README.md` | Topology definitions and configuration |

## Related Packages

| Package | Role |
|---|---|
| `@garazyk/hamownia` | Scenario runner engine, assertions, mock Twilio |
| `@garazyk/schemat` | Topology schema, compilation, presets |
| `@garazyk/laweta` | Docker orchestration, compose, health checks |
| `@garazyk/gruszka` | XRPC client generation from lexicons |

## Quick Start

```bash
# Run the full scenario suite
deno task hamownia

# Run a specific scenario
deno run -A packages/hamownia/cli.ts run --scenario account_lifecycle

# Check boundary violations
deno task narzedzia
```

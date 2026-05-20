---
title: Tutorials
---

# Tutorials

Learn by doing. These resources walk through specific tasks.

## Scenario Authoring

The [Scenario Authoring Guide](../../scripts/scenarios/README.md) and
[Scenario Standards](../../scripts/scenarios/SCENARIO_STANDARDS.md) show how to write
integration tests that validate AT Protocol flows against a local Docker network.

Start by reading an existing scenario in `scripts/scenarios/` to see the pattern.

## Adding an XRPC Endpoint

See the `designing-atproto-service` skill (`.agents/skills/designing-atproto-service/`) for
step-by-step guidance on scaffolding a new service binary with XRPC handlers, CMake integration,
and database wiring.

## Working with the TUI

The [TUI package](../../packages/tui/) provides a terminal UI framework. See
[docs/tui/README.md](../tui/README.md) for the architecture (note: historical reference,
migrating to `@opentui/core`).

## Federation Testing

See the `testing-atproto-federation` skill for a workflow to spin up, verify, and debug
multi-PDS AT Protocol federation.

## Deno Package Development

| Guide | Package |
|---|---|
| `packages/gruszka/` — XRPC client generation | See `README.md` in each package |
| `packages/schemat/` — Topology authoring | `packages/schemat/topology_authoring.ts` |

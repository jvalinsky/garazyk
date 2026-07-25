---
title: Deno Packages
---

# Deno Packages

This repository contains six Deno/TypeScript packages for tooling, testing, and terminal UI.

| Package              | Path                  | Tests | JSR | Description                                            |
| -------------------- | --------------------- | ----- | --- | ------------------------------------------------------ |
| `@garazyk/gruszka`   | `packages/gruszka/`   | 240   | ✅  | XRPC client generation from ATProto lexicons           |
| `@garazyk/schemat`   | `packages/schemat/`   | 67    | ✅  | Topology schema, compilation, and presets              |
| `@garazyk/laweta`    | `packages/laweta/`    | 63    | ✅  | Docker Engine API client and orchestration             |
| `@garazyk/hamownia`  | `packages/hamownia/`  | 73    | ❌  | Scenario runner with assertions and mock services      |
| `@garazyk/narzedzia` | `packages/narzedzia/` | 11    | ❌  | Developer tooling (boundary check, doc coverage, SPDX) |
| `@garazyk/tui`       | `packages/tui/`       | 227   | ❌  | Terminal UI framework (screen buffer, focus, theme)    |

## Architecture

Core logic is pure TypeScript with no terminal or network I/O. The design pushes side effects to CLI entry points and runtime handles.

- [Lexicon Resolution Pipeline](lexicon-resolution.md): 5-layer sans-IO architecture.
- [Repository Boundaries](../plans/workstreams/03-repository-boundaries.md): Extraction, release, and compatibility.
- [Deno Scenario Framework](deno-scenario-framework.md) (and `agent-scenario-testing` skill): Programmatic integration and automated testing.

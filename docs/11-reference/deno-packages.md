---
title: Deno Packages
---

# Deno Packages

Six Deno/TypeScript packages providing tooling, testing, and terminal UI capabilities.

| Package | Path | Tests | JSR | Description |
|---|---|---|---|---|
| `@garazyk/gruszka` | `packages/gruszka/` | 240 | ✅ | XRPC client generation from ATProto lexicons |
| `@garazyk/schemat` | `packages/schemat/` | 67 | ✅ | Topology schema, compilation, and presets |
| `@garazyk/laweta` | `packages/laweta/` | 63 | ✅ | Docker Engine API client and orchestration |
| `@garazyk/hamownia` | `packages/hamownia/` | 73 | ❌ | Scenario runner with assertions and mock services |
| `@garazyk/narzedzia` | `packages/narzedzia/` | 11 | ❌ | Developer tooling (boundary check, doc coverage, SPDX) |
| `@garazyk/tui` | `packages/tui/` | 227 | ❌ | Terminal UI framework (screen buffer, focus, theme) |

## Architecture

All packages follow a Sans-I/O pattern: core logic is pure TypeScript with zero terminal or network
I/O. Side effects are pushed to the boundary (CLI entry points, runtime handles).

For the full lexicon resolution pipeline architecture (5-layer sans-IO design), see
[Lexicon Resolution Pipeline](lexicon-resolution.md).

For detailed package status including JSR publish blockers and test coverage gaps, see
[Deno Packages Next Steps](../plans/deno-packages-next-steps.md).

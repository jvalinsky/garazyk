# Scenario Dashboard TUI (Terminal User Interface)

> **Status: Historical Reference** — The hand-rolled TUI documented here is scheduled for
> replacement by `@opentui/core` (target Q3 2026). These docs are preserved for three reasons:
> (1) understanding terminal rendering patterns used in the migration, (2) documenting the
> TEA state bridge design which carries forward unchanged, and (3) the theme system which is
> framework-agnostic and persists post-migration. For current development, prefer the
> `@opentui/core` documentation and `opentui` skill.

## Documentation Index

- [Architecture & Event Loop](architecture.md)
- [Core Primitives (Renderer, Input, Focus)](core-primitives.md)
- [Layout & Components](components.md)
- [Theme Architecture](theme-architecture.md)
- [Runtime & State Bridge](runtime.md)

## Key Design Decisions

1. **Immediate-Mode Rendering**: The custom TUI uses a double-buffered `ScreenBuffer`. Every frame, the entire view is redrawn to a new 2D array of `Cell` objects. A minimal diff algorithm compares it to the previous frame to generate minimal ANSI escape sequences, preventing terminal flicker.
2. **Synchronous TEA Architecture**: The dashboard is powered by the Elm Architecture (TEA) in `dashboard_state.ts`. The TUI simply subscribes to state changes via a `TuiRuntimeHandle` and re-renders the view synchronously when the state updates.
3. **No External Framework (Initially)**: Built entirely on Deno's `Deno.stdin` and ANSI escape sequences. This avoided Node.js dependencies like `blessed` or `ink`, staying true to Deno primitives.
4. **Transition to `@opentui/core`**: Maintaining hand-rolled input parsing, flexbox math, and multi-byte UTF-8 handling is complex. Transitioning to `@opentui/core` delegates these concerns to a highly optimized native runtime while keeping the TEA state bridge intact.
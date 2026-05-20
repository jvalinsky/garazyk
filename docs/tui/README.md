# Scenario Dashboard TUI (Terminal User Interface)

This directory documents the hand-rolled Terminal User Interface (TUI) previously built for the Garazyk Scenario Dashboard. 

**Note on Transition**: The hand-rolled TUI (~2,600 lines of custom rendering, input, layout, and focus logic) is scheduled to be replaced by `@opentui/core`. OpenTUI provides a standard `yoga-layout` flexbox engine, built-in renderables (`Box`, `Text`, `ScrollBox`), mouse support, and a native Zig renderer. 

This documentation preserves the architectural decisions and API designs of the custom TUI, as it serves as a foundation for understanding terminal capabilities and the specific layout/focus needs of the Garazyk dashboard.

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
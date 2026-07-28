# Scenario Dashboard TUI (Terminal User Interface)

> **Status: historical reference.** `@opentui/core` replaces the hand-rolled TUI documented
> here, targeted for Q3 2026. These docs stay for the terminal rendering patterns the
> migration reuses, the TEA state bridge design that carries forward unchanged, and the theme
> system, which is framework-agnostic. For current work, use the `@opentui/core`
> documentation and the `opentui` skill.

## Documentation Index

- [Architecture & Event Loop](architecture.md)
- [Core Primitives (Renderer, Input, Focus)](core-primitives.md)
- [Layout & Components](components.md)
- [Theme Architecture](theme-architecture.md)
- [Runtime & State Bridge](runtime.md)

## Key Design Decisions

1. **Immediate-mode rendering.** The TUI uses a double-buffered `ScreenBuffer`. Each frame redraws the whole view into a new 2D array of `Cell` objects, then diffs it against the previous frame to emit the smallest set of ANSI escape sequences. The diff is what keeps the terminal from flickering.
2. **Synchronous TEA architecture.** The dashboard runs the Elm Architecture in `dashboard_state.ts`. The TUI subscribes to state changes through a `TuiRuntimeHandle` and re-renders synchronously on update.
3. **No external framework, initially.** The first implementation used only `Deno.stdin` and ANSI escape sequences, which kept out Node dependencies such as `blessed` and `ink`.
4. **Move to `@opentui/core`.** Hand-rolled input parsing, flexbox math, and multi-byte UTF-8 handling are expensive to maintain. `@opentui/core` handles them in a native runtime, and the TEA state bridge stays as-is.
# Bespoke TUI Refactoring Plan: Primitives over Features

## Goal
Refactor the custom `@garazyk/tui` package and `scenario-dashboard` to adhere to "Primitives over Features". We will draw architectural inspiration from the `Clay` C layout library—specifically decoupling layout math, generic render commands, text measuring, and rasterization into isolated, pure primitives.

---

## Research Synthesis (The "Why")

1. **Clay Library Principles**: High-performance UI separates layout constraints (flexbox, grow/fixed sizing) from pixel rasterization. It calculates positions and emits an array of generic `RenderCommands`.
2. **Double Buffering & Minimal ANSI Diffing**: TUIs prevent flickering by maintaining Offscreen and Current buffers, diffing them, and emitting minimal ANSI payload strings.
3. **Text Formatting Constraints**: TUI text wrapping relies on fixed cell grids (handling multi-byte UTF-8, ANSI escape sequences in strings, and double-width CJK characters). Inversion of control for text measuring allows the layout engine to wrap text safely without knowing how it will be drawn.

---

## Execution Phases

### Phase 1: Decouple Layout Math from ScreenBuffer
**Objective**: Build a pure layout engine that computes geometry but does no rendering.
- **Current State**: `layout.ts` computes fixed widths/heights and `view.ts` directly writes strings to the `ScreenBuffer` via absolute math.
- **Action**: Implement a tree-based layout solver (similar to Yoga/Clay). It takes a declarative tree of layout constraints (e.g., `.width = GROW`, `.direction = COLUMN`) and returns calculated `BoundingBox(x, y, w, h)` objects.

### Phase 2: Implement Render Command Pipeline
**Objective**: Intercept direct `ScreenBuffer` writes with pure data primitives.
- **Current State**: `renderNetworkPanel()` calls `buffer.write(x, y, text)`.
- **Action**: Panel functions should become pure functions that return `RenderCommand[]` (e.g., `TextCommand`, `RectCommand`, `BoxCommand`). 

### Phase 3: Extract Text Layout & Measuring
**Objective**: Handle wrapping, clipping, and multi-byte width logic universally.
- **Current State**: Manual substring slicing and absolute positioning logic scattered across panels.
- **Action**: Create a `MeasureText` primitive that understands Deno terminal grids (handling emojis/CJK). Create a `TextWrap` primitive that takes a string, a target width, and returns an array of chopped lines.

### Phase 4: Centralize Rasterization & ANSI Diffing
**Objective**: Turn the `RenderCommand[]` array into ANSI bytes efficiently.
- **Current State**: `ScreenBuffer.diff()` handles the ANSI diffing.
- **Action**: Write a `rasterize(commands, buffer)` function. It iterates over the `RenderCommand[]`, applying clipping regions (for ScrollBoxes), mapping colors, and delegating to `ScreenBuffer.write()`. Then the existing `ScreenBuffer.diff()` kicks in for terminal output.

---
*Reference: Opencode invariant "Changeability" — separating layout from rendering prevents domain coupling, allowing tests to verify UI layout without simulating terminal environments.*
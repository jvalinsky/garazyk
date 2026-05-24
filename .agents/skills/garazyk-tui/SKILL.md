---
name: garazyk-tui
description: Reusable Terminal User Interface primitives for Deno applications from the @garazyk/tui package. Use when building terminal UIs with ScreenBuffer, computing layouts, parsing key input, managing focus, or rendering with ANSI commands. Root module is pure — no Deno I/O.
---

# Garazyk TUI — Terminal UI Primitives

`@garazyk/tui` provides pure TUI primitives: screen buffer, layout tree solver, key parsing, focus ring, render commands, and theme system. No Deno I/O in the root module — use `@garazyk/tui/runtime` for terminal mode and key reading.

## When to Use

- Build a full-screen or inline terminal UI
- Compute a declarative layout tree for panels
- Parse keyboard input into typed `Key` objects
- Manage focus across panels with a circular ring
- Render screen content via ANSI escape sequences
- Apply a dark/light/classic theme to TUI output

## Quick Start

```ts
import { ScreenBuffer, solveLayout, parseKey, FocusRing, rasterize } from "@garazyk/tui";
import { darkTheme, getCurrentTheme } from "@garazyk/tui";
```

Runtime subpath (terminal I/O):

```ts
import { /* terminal mode, key reading, env queries */ } from "@garazyk/tui/runtime";
```

Testing subpath:

```ts
import { /* test helpers for UI logic */ } from "@garazyk/tui/testing";
```

## API Reference

### Screen Buffer

| Export | Type | Description |
|--------|------|-------------|
| `ScreenBuffer` | class | Core rendering surface (`new ScreenBuffer(width, height)`) |
| `Cell` | type | `{ char, style }` — single screen cell |
| `CellStyle` | type | `{ fg?, bg?, bold?, dim?, underline?, reverse? }` |
| `mergeStyles(base, override)` | function | Merge two CellStyle objects |
| `DEFAULT_STYLE` | const | Empty default style |

### ANSI Helpers

| Export | Type | Description |
|--------|------|-------------|
| `fg(color)` / `bg(color)` | function | Foreground/background color codes |
| `bold()` / `dim()` / `underline()` / `reverse()` | function | Style escape sequences |
| `CLEAR_SCREEN` / `CURSOR_HOME` | const | Screen control sequences |
| `ENTER_ALT_SCREEN` / `EXIT_ALT_SCREEN` | const | Alternate screen buffer |
| `HIDE_CURSOR` / `SHOW_CURSOR` | const | Cursor visibility |
| `RESET` | const | Reset all styles |

### Layout

| Export | Type | Description |
|--------|------|-------------|
| `solveLayout(root, width, height)` | → `ResolvedNode[]` | Compute layout from tree |
| `LayoutNode` | type | `{ id, direction, sizing, children? }` |
| `ResolvedNode` | type | Computed layout with bounding box |
| `dashboardLayoutTree()` | function | Predefined dashboard layout |
| `findResolvedNode(nodes, id)` | function | Find node by ID |
| `flattenResolvedNodes(nodes)` | function | Flatten tree to list |
| `BoundingBox` | type | `{ x, y, width, height }` |
| `PanelId` | type | Panel identifier type |
| `PANEL_IDS` / `PANEL_TITLES` | const | Panel metadata |
| `findPanel(nodes, id)` | function | Find panel by ID |
| `panelContentArea(panel)` | function | Get content area bounds |

### Key Input

| Export | Type | Description |
|--------|------|-------------|
| `parseKey(raw)` | → `Key` | Parse raw input to typed key |
| `isKey(key, name)` | → boolean | Check key identity |
| `isQuit(key)` | → boolean | Check if key is quit (q/Ctrl+C) |
| `isCtrl(key)` | → boolean | Check if key is Ctrl-modified |
| `Keys` | const | Key name constants |

### Focus

| Export | Type | Description |
|--------|------|-------------|
| `FocusRing` | class | Circular focus across panels (`next()`, `prev()`, `current`) |

### Render Commands

| Export | Type | Description |
|--------|------|-------------|
| `rasterize(commands, buffer, w, h)` | function | Convert commands to screen buffer |
| `RenderCommand` | type | Union of all command types |
| `BoxCommand` | type | Draw a box with border |
| `RectCommand` | type | Fill a rectangle |
| `TextCommand` | type | Write text at position |
| `ScrollBoxCommand` | type | Render a scrollable region |

### Themes

| Export | Type | Description |
|--------|------|-------------|
| `getCurrentTheme()` | → `Theme` | Get active theme (lazy init) |
| `setCurrentTheme(theme)` | function | Set active theme |
| `darkTheme` / `lightTheme` / `classicTheme` | const | Built-in themes |
| `COLORS` | const | Color palette |
| `themes` | const | Theme registry |

### Text Utilities

| Export | Type | Description |
|--------|------|-------------|
| `truncate(text, maxWidth)` | function | Truncate with ellipsis respecting width |
| `getCharWidth(char)` | function | Character width (handles CJK double-width) |

## Key Patterns

### Build a screen and render

```ts
import { ScreenBuffer, fg, bg, bold, CLEAR_SCREEN, CURSOR_HOME } from "@garazyk/tui";

const buf = new ScreenBuffer(80, 24);
buf.setCell(0, 0, "H", { fg: "green", bold: true });
const output = CLEAR_SCREEN + CURSOR_HOME + buf.render();
Deno.stdout.write(new TextEncoder().encode(output));
```

### Compute layout from a tree

```ts
import { solveLayout, dashboardLayoutTree, findPanel, panelContentArea } from "@garazyk/tui";

const nodes = solveLayout(dashboardLayoutTree(), 80, 24);
const sidebar = findPanel(nodes, "sidebar");
const area = panelContentArea(sidebar);
```

### Handle key input

```ts
import { parseKey, isQuit, isKey, Keys } from "@garazyk/tui";

const key = parseKey(rawInput);
if (isQuit(key)) { /* exit */ }
if (isKey(key, Keys.Tab)) { focusRing.next(); }
```

### Use render commands

```ts
import { rasterize, BoxCommand, TextCommand } from "@garazyk/tui";

const commands: RenderCommand[] = [
  { type: "box", x: 0, y: 0, w: 80, h: 3, style: { fg: "cyan" } },
  { type: "text", x: 2, y: 1, text: "Dashboard", style: { bold: true } },
];
rasterize(commands, buf, 80, 24);
```

## Boundary Rules

TUI root module is pure — no Deno I/O. All environment-dependent code lives in `@garazyk/tui/runtime`. The `@garazyk/tui/testing` subpath provides test helpers.

## Related Skills

- **tui-design** — General TUI design patterns and library comparisons
- **garazyk-hamownia** — Scenario orchestration with TUI progress display
- **garazyk-schemat** — Logging utilities used alongside TUI output

# @garazyk/tui

Terminal user interface primitives for Garazyk Deno tools.

The package provides screen buffers, ANSI styling helpers, key parsing, layout
solving, focus management, render-command rasterization, text-width helpers, and
a small testing harness for terminal UI components.

## Imports

```ts
import {
  dashboardLayoutTree,
  findResolvedNode,
  ScreenBuffer,
  solveLayout,
} from "jsr:@garazyk/tui@0.1.0-alpha.1";

import { readKeys } from "jsr:@garazyk/tui@0.1.0-alpha.1/runtime";
import { VirtualTuiHarness } from "jsr:@garazyk/tui@0.1.0-alpha.1/testing";
```

## Exports

- `@garazyk/tui` exports pure rendering, input, layout, focus, theme, and text
  utilities. It performs no terminal I/O.
- `@garazyk/tui/runtime` exports Deno runtime helpers for terminal mode, input
  reading, and terminal size discovery.
- `@garazyk/tui/testing` exports test harness utilities for rendering and
  inspecting virtual terminal UI output.

## Example

```ts
import {
  bold,
  dashboardLayoutTree,
  ScreenBuffer,
  solveLayout,
} from "jsr:@garazyk/tui@0.1.0-alpha.1";

const tree = dashboardLayoutTree(100, 30);
if (!tree) throw new Error("terminal is too small");

const layout = solveLayout(tree, { x: 0, y: 0, width: 100, height: 30 });
const screen = new ScreenBuffer(100, 30);

screen.write(2, 1, "Garazyk dashboard", bold());
for (const panel of layout) {
  screen.write(panel.x + 1, panel.y, panel.id);
}

console.log(screen.fullRedraw());
```

## Runtime Notes

The root module is pure and does not require permissions. The `runtime` module
uses Deno terminal APIs and may need the permissions required by the embedding
tool. The `testing` module is intentionally published as part of the package API
for downstream terminal UI tests.

## Stability

This package is currently versioned as `0.1.0-alpha.1`. Treat the exported modules above
as the public API for this alpha release.

## Repository

Garazyk source lives at <https://github.com/garazyk/garazyk>.

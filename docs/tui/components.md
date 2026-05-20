# Layout & Components

The custom TUI does not use flexbox. It uses absolute coordinate math calculated on every frame based on the terminal dimensions.

## Layout Engine (`layout.ts`)

The layout engine statically partitions the terminal width and height into a `DashboardLayout` object.

### API Highlights
- `type PanelId = "network" | "scenarios" | "run" | "history"`
- `interface PanelLayout { id: PanelId, x: number, y: number, w: number, h: number }`
- `computeLayout(cols, rows)`: Returns a pre-calculated layout.
  - **Wide mode** (`>= 100 cols`): 2x2 grid.
  - **Narrow mode** (`< 100 cols`): Vertical stack.
- `panelContentArea(panel)`: Returns the inset boundaries `(x+1, y+1, w-2, h-2)` for panel content.

## Panel Renderers (`panels/*.ts`)

Each panel is a pure function that takes the `ScreenBuffer`, its bounding box, and the relevant slice of the TEA state.

1. **Network Panel (`panels/network.ts`)**: Renders a table of services with status dots/badges.
2. **Scenarios Panel (`panels/scenarios.ts`)**: Renders category groups, search filters, and coverage statistics.
3. **Run Panel (`panels/run.ts`)**: Renders progress bars, elapsed time, and an activity indicator for the active test runner.
4. **History Panel (`panels/history.ts`)**: Renders a scrollable list of recent runs and container metrics.

## View Composition (`view.ts`)

The `renderView` function acts as the root component. It composes:
- The top Status Bar.
- The 4 panel borders and titles.
- The delegates for the 4 panel renderers.
- The bottom Hint Bar (keyboard shortcuts).
# Phase 1: Declarative Layout via Tree Solver

## Problem

`layout_engine.ts` has `computeLayout()` with hardcoded `computeWideLayout`/`computeNarrowLayout`
doing manual `Math.floor` arithmetic for a 2x2 grid and vertical stack. The tree solver
(`layout_tree.ts`) with `solveLayout()` exists but is unused by the dashboard.

## Approach

1. **Define `dashboardLayoutTree()`** — returns a `LayoutNode` given terminal dimensions.
   - Wide (cols >= 100): column root with status-bar row, 2x2 panel grid (two row children,
     each with two grow columns), hint-bar row. Gap=1 between panels.
   - Narrow (cols < 100): column root with status bar, four stacked grow panels, hint bar.
   - Returns null if cols < 40 or rows < 16.

2. **Replace `computeLayout()` calls** in `tui.ts` and `view.ts` with:
   ```typescript
   const tree = dashboardLayoutTree(cols, rows);
   const resolved = solveLayout(tree, { x: 0, y: 0, width: cols, height: rows });
   ```

3. **Update `view.ts`** to iterate `flattenResolvedNodes(resolved)` instead of
   `layout.panels`. Use `findResolvedNode(resolved, "network")` instead of
   `findPanel(layout, "network")`.

4. **Retire `computeLayout`/`computeWideLayout`/`computeNarrowLayout`** and the
   `DashboardLayout`/`PanelLayout` types. Keep `PanelGeometry`/`computePanelGeometry`/
   `overlaps`/`contains`/`clipBox`/`isValidBox`/`translateBox` (used by command pipeline).

5. **Update `panel_state.ts`** — `PanelStates` keyed by `PanelId` stays the same;
   tree node IDs match existing panel IDs.

## Files Changed

- `packages/tui/layout_engine.ts` — remove `computeLayout` family, keep geometry utils
- `packages/tui/layout.ts` — re-export from tree instead of engine
- `scripts/scenario-dashboard/tui.ts` — use `solveLayout` + `dashboardLayoutTree`
- `scripts/scenario-dashboard/tui/view.ts` — iterate resolved nodes
- `scripts/scenario-dashboard/tui/panels/*.ts` — accept `ResolvedNode` instead of `PanelLayout`

## Verification

- `deno task boundaries` — no boundary violations
- `deno check` — type-checks
- `deno test` — existing layout tests pass with tree-based results
- Compare pixel output of old `computeLayout` vs new `solveLayout` for sizes 80x24, 100x30, 200x60

## Risk

- Tree solver produces different pixel values than manual math — mitigated by comparison test

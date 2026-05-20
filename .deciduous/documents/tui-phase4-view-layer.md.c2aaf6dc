# Phase 4: Refined View Layer

## Problem

- Panel renderers receive `PanelLayout` (will be replaced by `ResolvedNode` in Phase 1)
- Hint bar shows the same 7 hints regardless of focused panel
- `?` key sets `helpOverlay = true` but just dismisses on next keypress
- No `NO_COLOR` support
- Scenarios list renders all items (no virtualization) — slow with 63+ scenarios

## Approach

1. **Panel renderers accept `ResolvedNode`** instead of `PanelLayout`:
   - `ResolvedNode` has same shape (`x, y, width, height`) plus `id` and `children`
   - Update `computePanelGeometry()` to accept `ResolvedNode`
   - Update all four panel renderers in `tui/panels/`

2. **Context-sensitive hint bar** — show panel-specific actions:
   - network: `s Start  p Start PDS2  x Stop`
   - scenarios: `/ Filter  Space Toggle  Enter Run`
   - run: `s Stop  r Restart`
   - history: `r Restart  v View Log`
   - always: `1-4 Panel  Tab Switch  q Quit`

3. **Help overlay** — render a full-screen overlay when `?` is pressed:
   - List all keybindings grouped by panel
   - Dismissed by any keypress
   - Uses reverse video for the overlay background

4. **`NO_COLOR` support**:
   - Check `Deno.env.get("NO_COLOR")` at startup
   - In `encodeStyle()`, skip all color codes when `NO_COLOR` is set
   - Keep bold/dim/reverse/underline attributes (they're not color)

5. **Virtualize scenarios list**:
   - Only render items visible in the scrollable area
   - Use `panelState.scrollOffset` and `visibleRows` to slice the item list
   - Already partially done (scroll offset exists), but renderers still produce
     commands for all items

## Files Changed

- `scripts/scenario-dashboard/tui/view.ts` — iterate resolved nodes, context hints
- `scripts/scenario-dashboard/tui/panels/network.ts` — accept `ResolvedNode`
- `scripts/scenario-dashboard/tui/panels/scenarios.ts` — accept `ResolvedNode`, virtualize
- `scripts/scenario-dashboard/tui/panels/run.ts` — accept `ResolvedNode`
- `scripts/scenario-dashboard/tui/panels/history.ts` — accept `ResolvedNode`
- `scripts/scenario-dashboard/tui.ts` — implement help overlay, NO_COLOR
- `packages/tui/renderer.ts` — NO_COLOR support in `encodeStyle()`

## Verification

- `deno task boundaries` — no violations
- `deno check` — type-checks
- Visual: 80x24, 200x60, with and without `NO_COLOR=1`
- Performance: scenarios panel with 100 items should render in <5ms

## Risk

- Context hints may not fit in narrow terminals — truncate gracefully
- Help overlay may not fit in small terminals — scroll or paginate

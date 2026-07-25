# TUI: Layout Tree Solver, Sans-IO, Theme System — Research Plan

## Package Summary
Reusable Terminal User Interface primitives for Deno applications. Pure types and functions in the main module, with terminal I/O in `@garazyk/tui/runtime`. Declarative layout tree solver, ANSI renderer, theme system.

## Key Techniques
1. **Declarative layout tree solver** — `solveLayout()` with fixed/grow sizing, row/column directions, gaps
2. **Sans-IO architecture** — Main module exports only pure types/functions; `runtime.ts` has terminal I/O
3. **ANSI 16-color theme system** — `Theme` interface with semantic tokens, dark/light/classic variants
4. **Screen buffer rendering** — `ScreenBuffer` with `Cell` grid, style merging, ANSI escape sequences
5. **Render command pattern** — `RenderCommand` + `rasterize()` for decoupled rendering
6. **Focus ring** — `FocusRing` for panel focus cycling
7. **Key parsing** — `parseKey()` for terminal key event normalization
8. **Lazy theme initialization** — `getCurrentTheme()` resolves from env on first call (no module-load I/O)
9. **COLORFGBG heuristic** — Terminal background detection via `COLORFGBG` env var
10. **Character width handling** — `getCharWidth()` for CJK/wide character support

## Research Queries (for sub-agents)

### Q1: TUI layout engines comparison
- Search: "terminal UI layout engine tree solver comparison"
- Search: "Bubble Tea vs Ink vs Ratatui layout system"
- Search: "Yoga Flexbox layout engine terminal UI adaptation"
- Focus: How does the tree solver compare to other TUI layout approaches? Are there missing features (flex wrap, aspect ratio, min/max constraints)?

### Q2: Sans-IO TUI architecture patterns
- Search: "sans-IO terminal UI architecture Elm TEA pattern"
- Search: "The Elm Architecture terminal UI TypeScript implementation"
- Focus: The sans-IO split — how does it compare to Elm's TEA pattern? Is the boundary clean?

### Q3: ANSI 16-color theme design for TUI
- Search: "ANSI 16 color terminal UI theme design best practices"
- Search: "terminal UI dark theme color palette design"
- Search: "COLORFGBG terminal background detection reliability"
- Focus: Is the 16-color palette sufficient? How do other TUI frameworks handle theme systems? Is COLORFGBG reliable?

### Q4: Terminal screen buffer rendering
- Search: "terminal screen buffer double buffering ANSI escape sequences"
- Search: "TUI rendering optimization diff-based rendering"
- Focus: Does `ScreenBuffer` do diff-based rendering? Or does it redraw the entire screen? Performance implications

### Q5: Terminal key event parsing
- Search: "terminal key event parsing escape sequences TypeScript"
- Search: "Deno terminal raw mode key reading best practices"
- Focus: `parseKey()` — does it handle all common escape sequences? Kitty keyboard protocol? Bracketed paste?

### Q6: Wide character handling in terminal UIs
- Search: "CJK wide character terminal UI rendering"
- Search: "Unicode width calculation terminal grid alignment"
- Focus: `getCharWidth()` — is it correct for all Unicode categories? Emoji, zero-width joiners, combining characters?

## Additional Code Review Concerns (from deep survey)
- `command.ts` `BoxCommand.clip` is ignored by `rasterize()` — nested clipped content renders incorrectly
- `command.ts` `translateCommand()` does not translate child clip rectangles
- `dashboard_layout.ts` 100-column breakpoint is fixed — no adaptation between "barely wide" and "very wide"
- `dashboard_layout.ts` terminals < 40x16 return `null` — no graceful degradation
- `focus.ts` `jump(index)` is 0-based but comments describe 1-based numeric keys — off-by-one risk
- `input.ts` intentionally partial parser — rare CSI variants, timing-sensitive Alt/ESC, long escape sequences may misparse
- `layout_engine.ts` `isValidBox()` rejects zero-sized boxes but `computePanelGeometry()` doesn't validate bounds are large enough for borders
- `layout_tree.ts` no validation that fixed sizes fit within bounds — oversized nodes can overflow or collapse growing children to zero
- `renderer.ts` `NO_COLOR` is read at import time — won't react to later env changes
- `renderer.ts` width handling is approximate for combining characters/emoji
- `renderer.ts` `box()`/`boxTitle()` don't guard against tiny boxes
- `text.ts` ANSI preservation is partial; `wrapWord()` can collapse spacing; width logic is not grapheme-aware
- `theme.ts` theme selection is global mutable state; environment detection happens only once

## Code Review Concerns to Investigate
- `solveLayout()` gives remainder pixels to the LAST growing child — could cause visual misalignment
- `ScreenBuffer` — does it handle terminal resize? Or does the caller need to recreate it?
- `COLORS` getter-based re-export is deprecated but still exported — cleanup needed?
- `lightTheme` has `textSecondary` and `textMuted` both as `BRIGHT_BLACK` — comment says "use dim() to differentiate" but is this actually done?
- `classicTheme` surface elevated is `BLUE` — may not work well on dark terminals with blue text
- `parseKey()` — how comprehensive is the escape sequence coverage?
- `runtime.ts` — what I/O does it do? Is it clean or does it have side effects at module load?
- `dashboardLayoutTree()` — is this the right place for dashboard-specific layout? Should it be in the dashboard package?
- `truncate()` — does it account for wide characters? Or does it just count code units?

## Deciduous Link
- Node 286: tui action

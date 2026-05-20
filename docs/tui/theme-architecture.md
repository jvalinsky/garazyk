# Theme Architecture

The TUI theme system translates the `.impeccable.md` design system (AppKit-inspired, OKLCH-based) into terminal UI constraints. Terminals are limited to 16 standard colors on basic terminals, 256-color on most modern ones, and true color on the newest. The system targets 16-color as the baseline.

## Design Principles

From `.impeccable.md`:

1. **AppKit fidelity** — clean, professional terminal UI
2. **Approachable clarity** — semantic color tokens instead of raw ANSI codes
3. **Progressive disclosure** — surface hierarchy for visual depth
4. **System-aware theming** — automatic light/dark mode detection
5. **Polish pride** — strawberry brand accent (MAGENTA, hue 15° in OKLCH) distinct from error RED

## ANSI 16-Color Reference

```
 0: Black          8: Bright Black (gray)
 1: Red            9: Bright Red
 2: Green         10: Bright Green
 3: Yellow        11: Bright Yellow
 4: Blue          12: Bright Blue
 5: Magenta       13: Bright Magenta
 6: Cyan          14: Bright Cyan
 7: White         15: Bright White
-1: Default (terminal foreground/background)
```

All theme token values are validated as being in the range `-1..15` at test time.

## Theme Interface

The `Theme` interface defines 20 semantic color tokens organized into seven categories:

### Surface Hierarchy
Three background shades for visual depth (progressive disclosure):

| Token | Purpose | Dark Value | Light Value |
|---|---|---|---|
| `surfaceBase` | Deepest layer: app background between panels | BLACK (0) | WHITE (7) |
| `surfacePanel` | Panel interiors | BRIGHT_BLACK (8) | DEFAULT (-1) |
| `surfaceElevated` | Cursor row, selected items, overlays | CYAN (6) | BLUE (4) |

Each layer must be visually distinct from its neighbors.

### Text
Three text levels for content hierarchy:

| Token | Purpose | Dark Value | Light Value |
|---|---|---|---|
| `textPrimary` | Body text, headings | DEFAULT (-1) | BLACK (0) |
| `textSecondary` | Supporting text, labels | WHITE (7) | BRIGHT_BLACK (8) |
| `textMuted` | Diminished text, empty states | BRIGHT_BLACK (8) | BRIGHT_BLACK (8) |

### Accent
MAGENTA (5) — the strawberry brand color. Used for keybindings, highlights, focused borders, running badges, and title text. The classic theme uses CYAN (6) for backward compatibility.

### Status Indicators
Standard traffic-light colors shared across all themes:

| Token | Value | Meaning |
|---|---|---|
| `statusOk` | GREEN (2) | Healthy, passed, connected |
| `statusWarn` | YELLOW (3) | Warning, degraded, starting |
| `statusErr` | RED (1) | Error, failed, disconnected |
| `statusMuted` | BRIGHT_BLACK (8) | Inactive, muted, unknown |

### Borders, Badges, Progress, Title

| Category | Tokens | Notes |
|---|---|---|
| Borders | `border`, `borderFocused` | Default = BRIGHT_BLACK; focused = accent color |
| Badges | `badgePassed`, `badgeFailed`, `badgeSkipped`, `badgeRunning` | GREEN/RED/YELLOW/accent |
| Progress | `progressBar`, `progressTrack` | Filled = GREEN; track darker than panel fill |
| Title | `title` | Matches accent color |

## Three Themes

### Dark (default)
Default for terminals with dark backgrounds. Used by ~90% of terminals.

- Surface: BLACK → BRIGHT_BLACK → CYAN (teal cursor)
- Text: DEFAULT → WHITE → BRIGHT_BLACK
- Accent: MAGENTA (strawberry)
- Progress track: BLACK (darker than BRIGHT_BLACK panel — a visible "cutout" effect)

### Light
For terminals with light backgrounds (`COLORFGBG` bg=7 or bg=15).

- Surface: WHITE → DEFAULT → BLUE
- Text: BLACK → BRIGHT_BLACK → BRIGHT_BLACK
- Accent: MAGENTA (same brand)
- Progress track: BRIGHT_BLACK (lighter than dark's BLACK, works on light panels)

**Note:** `textSecondary` and `textMuted` both resolve to BRIGHT_BLACK (8). The 16-color palette cannot express three distinct text levels on a light background while maintaining contrast. Use `dim()` to visually separate secondary from muted when needed.

### Classic
CYAN-accented palette preserved for users who prefer the pre-theme-system appearance.

- Surface: BLACK → BRIGHT_BLACK → BLUE (the original blue cursor)
- Text: DEFAULT → BRIGHT_BLACK → BRIGHT_BLACK
- Accent: CYAN (6) throughout — accent, borders, badges, title
- Progress track: BRIGHT_BLACK

**Note:** Same `textSecondary`/`textMuted` convergence as light theme.

## Theme Resolution

On module load, `resolveTheme()` determines the initial theme:

1. **`GARAZYK_TUI_THEME` env var** — explicit override (`"dark"`, `"light"`, `"classic"`)
2. **`COLORFGBG` env var heuristic** — terminal reports its background color; `bg=7` or `bg=15` → light theme; `bg=0` → dark theme
3. **Default** — dark theme (most terminals have dark backgrounds)

```typescript
// Explicit override
GARAZYK_TUI_THEME=light deno run -A tui.ts

// Runtime switching
import { setTheme, currentTheme } from "@garazyk/tui";
setTheme("classic");
console.log(currentTheme.name); // "classic"
```

## Runtime Switching

`setTheme(name)` updates `currentTheme` and returns the new theme. The `COLORS` getter object picks up the change immediately — no re-export or module reload needed.

```typescript
import { setTheme, COLORS } from "@garazyk/tui";

// COLORS.accent tracks the active theme in real time
setTheme("dark");
COLORS.accent;  // 5 (MAGENTA)

setTheme("classic");
COLORS.accent;  // 6 (CYAN)
```

Theme switching is idempotent and rounds-trip safe — switching to a theme and back restores all token values.

## The COLORS Backward-Compat Layer

The `COLORS` object is a `Readonly<Omit<Theme, "name">>` with getter properties that delegate to `currentTheme`. It exists for backward compatibility with existing panel code that imports `{ COLORS }`.

```typescript
// ✅ Convenient for panels — no need to pass theme through props
import { COLORS, fg, bg } from "@garazyk/tui";
buf.fillRect(x, y, w, h, " ", bg(COLORS.surfacePanel));

// ✅ Equivalent, more explicit
import { currentTheme, fg, bg } from "@garazyk/tui";
buf.fillRect(x, y, w, h, " ", bg(currentTheme.surfacePanel));
```

The `COLORS` object carries a `@deprecated` JSDoc tag encouraging direct `currentTheme` imports in new code.

## Panel Usage Patterns

### Surface Fills — Always Fill Before Writing

Every panel MUST fill its interior with `bg(COLORS.surfacePanel)` before writing text. This ensures the panel background is visible even when text doesn't cover every cell. Text written with styles that lack an explicit background will inherit the panel fill.

```typescript
// ✅ Correct: fill then write
const area = panelContentArea(resolvedNode);
buf.fillRect(area.x, area.y, area.width, area.height, " ", bg(COLORS.surfacePanel));
buf.writeClipped(x, y, "text", fg(COLORS.textPrimary), clip);

// ❌ Wrong: writing without a fill — transparent cells show surfaceBase
buf.writeClipped(x, y, "text", fg(COLORS.textPrimary), clip);
```

The `view.ts` renderer fills the full screen with `bg(COLORS.surfaceBase)` before rendering any panels.

### Text Hierarchy

```typescript
// Primary: body text, headings
buf.write(x, y, "Active Run", fg(COLORS.textPrimary));

// Secondary: labels, keybindings, metrics
buf.write(x, y, "Press q to quit", dim(fg(COLORS.textSecondary)));

// Muted: empty states, timestamps, less important info
buf.write(x, y, "(no data)", dim(fg(COLORS.textMuted)));
```

Always wrap secondary and muted text with `dim()` for consistent visual hierarchy regardless of which theme is active.

### Status Colors

```typescript
import { fg, COLORS } from "@garazyk/tui";

function statusStyle(status: string): CellStyle {
  if (status === "running") return fg(COLORS.statusOk);
  if (status === "warning") return fg(COLORS.statusWarn);
  if (status === "error")   return fg(COLORS.statusErr);
  return fg(COLORS.statusMuted);
}
```

### Progress Bars — Two-Color Rendering

Progress bars use two `text` commands — GREEN for the filled portion, progress track color for the unfilled portion:

```typescript
// Filled: GREEN draws attention to completion
cmds.push({
  type: "text", x: startX, y: rowY,
  text: `[${"█".repeat(filledWidth)}`,
  style: fg(COLORS.progressBar), clip,
});

// Unfilled + count: track color creates a cutout against the panel fill
cmds.push({
  type: "text", x: startX + 1 + filledWidth, y: rowY,
  text: `${"░".repeat(emptyWidth)}] ${completed}/${total}`,
  style: fg(COLORS.progressTrack), clip,
});
```

### Cursor and Selection Highlighting

```typescript
// Elevated surface for selected/cursor rows
const CURSOR_STYLE = { ...bg(COLORS.surfaceElevated), fg: -1 };
const CURSOR_TEXT_STYLE = { ...bg(COLORS.surfaceElevated), fg: -1, bold: true };

buf.fillRect(x, cursorY, width, 1, " ", CURSOR_STYLE);
buf.writeClipped(x, cursorY, itemName, CURSOR_TEXT_STYLE, clip);
```

### Accent Usage

Use `COLORS.accent` for interactive elements: keybindings, focused borders, running badges, and title text. Never use accent for status indicators — those have dedicated tokens.

```typescript
buf.write(x, y, "? help", fg(COLORS.accent));           // keybinding
buf.write(x, y, "│", fg(COLORS.borderFocused));          // focused panel border
buf.write(x, y, "[RUNNING]", fg(COLORS.badgeRunning));   // running badge
```

## Palette Convergence Limitations

The 16-color ANSI palette is a hard constraint. Some tokens converge to the same ANSI value:

| Theme | Tokens | Shared Value | Mitigation |
|---|---|---|---|
| Dark | `textSecondary` (7), `textMuted` (8) | Different | No convergence — distinct by design |
| Light | `textSecondary`, `textMuted` | Both BRIGHT_BLACK (8) | Use `dim()` for visual separation |
| Classic | `textSecondary`, `textMuted` | Both BRIGHT_BLACK (8) | Use `dim()` for visual separation |
| All | `statusMuted`, `border`, `textMuted` (dark) | BRIGHT_BLACK (8) | Different semantic roles — no visual conflict |

The `dim()` style modifier (ANSI SGR code 2) is the primary escape hatch: `dim(fg(COLORS.textSecondary))` is visually distinct from `dim(fg(COLORS.textMuted))` because `dim(WHITE)` differs from `dim(BRIGHT_BLACK)` on most terminals, even when both base colors are BRIGHT_BLACK in light/classic themes.

## Testing Strategy

Tests live in `packages/tui/theme_test.ts` (currently ~55 tests, part of the 227-test suite):

| Layer | What's Tested | Count |
|---|---|---|
| **Preset values** | Explicit ANSI number assertions for every token in every theme | ~20 tests |
| **ANSI range** | Every token in every theme (direct + via COLORS getters) is -1..15 | 3 tests |
| **Invariants** | Distinctness (surface layers differ, accent ≠ error, names unique) | ~10 tests |
| **Theme switching** | `setTheme` mutations, idempotency, round-trip safety, unknown-name errors | ~8 tests |
| **COLORS getters** | Backward-compat getters track theme switches for every token category | ~10 tests |
| **Edge cases** | Rapid switching, stale-value prevention, `COLORS.title === COLORS.accent` | ~4 tests |

Run: `deno test packages/tui/theme_test.ts --allow-env`

## Adding a Theme

To add a fourth theme:

1. Define a `const myTheme: Theme = { ... }` in `theme.ts`
2. Add it to the `themes` registry object
3. Add explicit value assertions to `theme_test.ts` for every token
4. Add an ANSI-range scan test for the new theme's COLORS getters
5. Optionally wire it into `resolveTheme()` (e.g., via a new env var value)

/**
 * TUI Theme System
 *
 * Translates the .impeccable.md design system (AppKit-inspired, OKLCH-based)
 * into terminal UI constraints. Terminals are limited to 16 standard colors
 * on basic terminals, 256-color on most modern ones, and true color on
 * the newest. We target 16-color as the baseline with 256-color enhancements
 * where possible.
 *
 * Design principles from .impeccable.md:
 *   1. AppKit fidelity → clean, professional terminal UI
 *   2. Approachable clarity → semantic color tokens
 *   3. Progressive disclosure → surface hierarchy for visual depth
 *   4. System-aware theming → light/dark mode detection
 *   5. Polish pride → strawberry brand accent (MAGENTA in terminal)
 *
 * Strawberry brand (hue 15° in OKLCH):
 *   In 16-color terminals, MAGENTA (color 5) is the closest approximation
 *   to a warm "strawberry" tone that is distinct from error RED (color 1).
 *
 * @module tui/theme
 */

// ---------------------------------------------------------------------------
// Theme interface
// ---------------------------------------------------------------------------

/** Semantic color tokens for a TUI theme. */
export interface Theme {
  /** Human-readable theme name. */
  name: string;

  // ── Surface hierarchy (background shades for visual depth) ─────────
  /** Deepest layer: app background, fills empty space between panels. */
  surfaceBase: number;
  /** Slightly elevated: panel interiors, subtle dark gray tint. */
  surfacePanel: number;
  /** Elevated/highlighted: cursor row, selected items. */
  surfaceElevated: number;

  // ── Text ──────────────────────────────────────────────────────────
  /** Primary body text. -1 means default terminal foreground. */
  textPrimary: number;
  /** Secondary/supporting text. */
  textSecondary: number;
  /** Muted/diminished text (less important). */
  textMuted: number;

  // ── Accent (brand color) ──────────────────────────────────────────
  /** Primary accent: keybindings, highlights, interactive elements.
   *  Strawberry brand → MAGENTA in 16-color terminals. */
  accent: number;

  // ── Status indicators ─────────────────────────────────────────────
  /** Healthy, passed, connected. */
  statusOk: number;
  /** Warning, degraded, starting. */
  statusWarn: number;
  /** Error, failed, disconnected. */
  statusErr: number;
  /** Inactive, muted, unknown. */
  statusMuted: number;

  // ── Borders ───────────────────────────────────────────────────────
  /** Default panel border. */
  border: number;
  /** Focused panel border (highlighted). */
  borderFocused: number;

  // ── Badges ────────────────────────────────────────────────────────
  /** Passed/test-success badge. */
  badgePassed: number;
  /** Failed/test-error badge. */
  badgeFailed: number;
  /** Skipped/warning badge. */
  badgeSkipped: number;
  /** Running/in-progress badge. */
  badgeRunning: number;

  // ── Progress ──────────────────────────────────────────────────────
  /** Filled portion of a progress bar. */
  progressBar: number;
  /** Track/unfilled portion of a progress bar. */
  progressTrack: number;

  // ── Title ─────────────────────────────────────────────────────────
  /** Title bar and heading text. */
  title: number;
}

// ---------------------------------------------------------------------------
// ANSI 16-color palette reference
// ---------------------------------------------------------------------------

/**
 * Standard ANSI 16-color palette.
 *
 *   0: Black          8: Bright Black (gray)
 *   1: Red            9: Bright Red
 *   2: Green         10: Bright Green
 *   3: Yellow        11: Bright Yellow
 *   4: Blue          12: Bright Blue
 *   5: Magenta       13: Bright Magenta
 *   6: Cyan          14: Bright Cyan
 *   7: White         15: Bright White
 */
const ANSI_COLORS = {
  BLACK: 0,
  RED: 1,
  GREEN: 2,
  YELLOW: 3,
  BLUE: 4,
  MAGENTA: 5,
  CYAN: 6,
  WHITE: 7,
  BRIGHT_BLACK: 8,
  BRIGHT_RED: 9,
  BRIGHT_GREEN: 10,
  BRIGHT_YELLOW: 11,
  BRIGHT_BLUE: 12,
  BRIGHT_MAGENTA: 13,
  BRIGHT_CYAN: 14,
  BRIGHT_WHITE: 15,
  DEFAULT: -1,
} as const;

// ---------------------------------------------------------------------------
// Dark theme (default)
// ---------------------------------------------------------------------------

/**
 * Dark theme — the default for terminals with dark backgrounds.
 *
 * Surface hierarchy:
 *   surfaceBase     → BLACK (0)         deep app background
 *   surfacePanel    → BRIGHT_BLACK (8)  subtle dark gray panel fill
 *   surfaceElevated → CYAN (6)          cursor/selected rows (teal)
 *
 * Accent: MAGENTA (5) — strawberry brand (hue 15° in OKLCH).
 *   Distinct from RED (1, used for errors) and CYAN (6, used for elevated surfaces).
 */
export const darkTheme: Theme = {
  name: "dark",

  // Surface hierarchy
  surfaceBase: ANSI_COLORS.BLACK,
  surfacePanel: ANSI_COLORS.BRIGHT_BLACK,
  surfaceElevated: ANSI_COLORS.CYAN,

  // Text
  textPrimary: ANSI_COLORS.DEFAULT,
  textSecondary: ANSI_COLORS.WHITE,
  textMuted: ANSI_COLORS.BRIGHT_BLACK,

  // Accent (strawberry brand)
  accent: ANSI_COLORS.MAGENTA,

  // Status
  statusOk: ANSI_COLORS.GREEN,
  statusWarn: ANSI_COLORS.YELLOW,
  statusErr: ANSI_COLORS.RED,
  statusMuted: ANSI_COLORS.BRIGHT_BLACK,

  // Borders
  border: ANSI_COLORS.BRIGHT_BLACK,
  borderFocused: ANSI_COLORS.MAGENTA,

  // Badges
  badgePassed: ANSI_COLORS.GREEN,
  badgeFailed: ANSI_COLORS.RED,
  badgeSkipped: ANSI_COLORS.YELLOW,
  badgeRunning: ANSI_COLORS.MAGENTA,

  // Progress
  progressBar: ANSI_COLORS.GREEN,
  progressTrack: ANSI_COLORS.BLACK,

  // Title
  title: ANSI_COLORS.MAGENTA,
};

// ---------------------------------------------------------------------------
// Light theme
// ---------------------------------------------------------------------------

/**
 * Light theme — for terminals with light backgrounds.
 *
 * Surface hierarchy (inverted):
 *   surfaceBase     → WHITE (7)         light app background
 *   surfacePanel    → default (-1)      slightly darker fill
 *   surfaceElevated → BLUE (4)          cursor/selected rows (works on light)
 *
 * Text colors use dark variants for contrast on light backgrounds.
 */
export const lightTheme: Theme = {
  name: "light",

  // Surface hierarchy
  surfaceBase: ANSI_COLORS.WHITE,
  surfacePanel: ANSI_COLORS.DEFAULT, // terminal default (usually white/light)
  surfaceElevated: ANSI_COLORS.BLUE,

  // Text — dark for contrast on light backgrounds.
  // NOTE: textSecondary and textMuted both map to BRIGHT_BLACK (8).
  // The 16-color palette cannot express three distinct text levels on a
  // light background while maintaining contrast. Callers should use `dim()`
  // to visually separate secondary from muted when needed.
  textPrimary: ANSI_COLORS.BLACK,
  textSecondary: ANSI_COLORS.BRIGHT_BLACK,
  textMuted: ANSI_COLORS.BRIGHT_BLACK,

  // Accent (strawberry brand — visible on light)
  accent: ANSI_COLORS.MAGENTA,

  // Status
  statusOk: ANSI_COLORS.GREEN,
  statusWarn: ANSI_COLORS.YELLOW,
  statusErr: ANSI_COLORS.RED,
  statusMuted: ANSI_COLORS.BRIGHT_BLACK,

  // Borders
  border: ANSI_COLORS.BRIGHT_BLACK,
  borderFocused: ANSI_COLORS.MAGENTA,

  // Badges
  badgePassed: ANSI_COLORS.GREEN,
  badgeFailed: ANSI_COLORS.RED,
  badgeSkipped: ANSI_COLORS.YELLOW,
  badgeRunning: ANSI_COLORS.MAGENTA,

  // Progress
  progressBar: ANSI_COLORS.GREEN,
  progressTrack: ANSI_COLORS.BRIGHT_BLACK,

  // Title
  title: ANSI_COLORS.MAGENTA,
};

// ---------------------------------------------------------------------------
// Classic theme (backward compat — CYAN accent)
// ---------------------------------------------------------------------------

/**
 * Classic theme — the original CYAN-accented palette preserved for
 * users who prefer the pre-theme-system appearance.
 */
export const classicTheme: Theme = {
  name: "classic",

  // Surface hierarchy (unchanged from original)
  surfaceBase: ANSI_COLORS.BLACK,
  surfacePanel: ANSI_COLORS.BRIGHT_BLACK,
  surfaceElevated: ANSI_COLORS.BLUE,

  // Text
  // NOTE: textSecondary and textMuted both map to BRIGHT_BLACK (8).
  // The 16-color palette cannot express three distinct text levels while
  // keeping BRIGHT_BLACK as the surface panel fill. Callers should use
  // `dim()` to visually separate secondary from muted when needed.
  textPrimary: ANSI_COLORS.DEFAULT,
  textSecondary: ANSI_COLORS.BRIGHT_BLACK,
  textMuted: ANSI_COLORS.BRIGHT_BLACK,

  // Accent (classic CYAN)
  accent: ANSI_COLORS.CYAN,

  // Status
  statusOk: ANSI_COLORS.GREEN,
  statusWarn: ANSI_COLORS.YELLOW,
  statusErr: ANSI_COLORS.RED,
  statusMuted: ANSI_COLORS.BRIGHT_BLACK,

  // Borders
  border: ANSI_COLORS.BRIGHT_BLACK,
  borderFocused: ANSI_COLORS.CYAN,

  // Badges
  badgePassed: ANSI_COLORS.GREEN,
  badgeFailed: ANSI_COLORS.RED,
  badgeSkipped: ANSI_COLORS.YELLOW,
  badgeRunning: ANSI_COLORS.CYAN,

  // Progress
  progressBar: ANSI_COLORS.GREEN,
  progressTrack: ANSI_COLORS.BRIGHT_BLACK,

  // Title
  title: ANSI_COLORS.CYAN,
};

// ---------------------------------------------------------------------------
// Theme registry and selection
// ---------------------------------------------------------------------------

/** All built-in themes. */
export const themes: Record<string, Theme> = {
  dark: darkTheme,
  light: lightTheme,
  classic: classicTheme,
};

/** The currently active theme. Use {@link getCurrentTheme} and {@link setCurrentTheme} to access. */
let _currentTheme: Theme | undefined;

/** Get the currently active theme. Lazily resolves from environment on first call. */
export function getCurrentTheme(): Theme {
  if (_currentTheme === undefined) {
    _currentTheme = resolveTheme({
      theme: Deno.env.get("GARAZYK_TUI_THEME"),
      colorfgbg: Deno.env.get("COLORFGBG"),
    });
  }
  return _currentTheme;
}

/** Set the active theme by name. */
export function setCurrentTheme(name: string): Theme {
  const theme = themes[name];
  if (!theme) throw new Error(`Unknown theme: ${name}. Available: ${Object.keys(themes).join(", ")}`);
  _currentTheme = theme;
  return theme;
}

/** Internal theme resolution options. */
export interface ThemeResolutionOptions {
  theme?: string;
  colorfgbg?: string;
}

/**
 * Resolve a theme based on provided options.
 */
export function resolveTheme(options: ThemeResolutionOptions = {}): Theme {
  // Explicit override
  if (options.theme && themes[options.theme]) {
    return themes[options.theme];
  }

  // Detect terminal background via COLORFGBG
  // Format: "fg;bg" where 0=black, 7=white, 15=bright white
  try {
    const colorfgbg = options.colorfgbg;
    if (colorfgbg) {
      const parts = colorfgbg.split(";");
      if (parts.length >= 2) {
        const bg = parseInt(parts[1]!, 10);
        // bg=0 or bg=default → dark terminal → dark theme
        // bg=7 or bg=15 → light terminal → light theme
        if (bg === 7 || bg === 15) return lightTheme;
        if (bg === 0) return darkTheme;
      }
    }
  } catch {
    // env access failed — use default
  }

  // Default: dark theme (most terminals have dark backgrounds)
  return darkTheme;
}

// ---------------------------------------------------------------------------
// COLORS re-export (backward compat)
// ---------------------------------------------------------------------------

/**
 * Semantic color tokens — derived from the active theme.
 *
 * @deprecated Prefer importing `getCurrentTheme()` directly. This object
 *   exists for backward compatibility with existing panel code.
 */
export const COLORS: Readonly<Omit<Theme, "name">> = {
  get surfaceBase() { return getCurrentTheme().surfaceBase; },
  get surfacePanel() { return getCurrentTheme().surfacePanel; },
  get surfaceElevated() { return getCurrentTheme().surfaceElevated; },
  get textPrimary() { return getCurrentTheme().textPrimary; },
  get textSecondary() { return getCurrentTheme().textSecondary; },
  get textMuted() { return getCurrentTheme().textMuted; },
  get accent() { return getCurrentTheme().accent; },
  get statusOk() { return getCurrentTheme().statusOk; },
  get statusWarn() { return getCurrentTheme().statusWarn; },
  get statusErr() { return getCurrentTheme().statusErr; },
  get statusMuted() { return getCurrentTheme().statusMuted; },
  get border() { return getCurrentTheme().border; },
  get borderFocused() { return getCurrentTheme().borderFocused; },
  get badgePassed() { return getCurrentTheme().badgePassed; },
  get badgeFailed() { return getCurrentTheme().badgeFailed; },
  get badgeSkipped() { return getCurrentTheme().badgeSkipped; },
  get badgeRunning() { return getCurrentTheme().badgeRunning; },
  get progressBar() { return getCurrentTheme().progressBar; },
  get progressTrack() { return getCurrentTheme().progressTrack; },
  get title() { return getCurrentTheme().title; },
};

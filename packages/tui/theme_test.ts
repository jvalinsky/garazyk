/**
 * Tests for the TUI theme system.
 *
 * @module tui/theme_test
 */

import { assertEquals, assertThrows, assert } from "@std/assert";
import {
  darkTheme,
  lightTheme,
  classicTheme,
  themes,
  currentTheme,
  setTheme,
  COLORS,
} from "./theme.ts";

// ---------------------------------------------------------------------------
// Theme presets — value correctness
// ---------------------------------------------------------------------------

Deno.test("theme: darkTheme has correct name", () => {
  assertEquals(darkTheme.name, "dark");
});

Deno.test("theme: lightTheme has correct name", () => {
  assertEquals(lightTheme.name, "light");
});

Deno.test("theme: classicTheme has correct name", () => {
  assertEquals(classicTheme.name, "classic");
});

Deno.test("theme: darkTheme uses MAGENTA (strawberry) accent", () => {
  assertEquals(darkTheme.accent, 5); // ANSI MAGENTA
});

Deno.test("theme: darkTheme accent != statusErr", () => {
  // Accent and error must be distinct colors visible on dark backgrounds
  assert(darkTheme.accent !== darkTheme.statusErr);
});

Deno.test("theme: darkTheme accent != statusOk", () => {
  assert(darkTheme.accent !== darkTheme.statusOk);
});

Deno.test("theme: classicTheme uses CYAN accent (backward compat)", () => {
  assertEquals(classicTheme.accent, 6); // ANSI CYAN
});

Deno.test("theme: classicTheme borderFocused uses CYAN", () => {
  assertEquals(classicTheme.borderFocused, 6);
});

Deno.test("theme: all theme color tokens are in valid ANSI range", () => {
  for (const theme of Object.values(themes)) {
    const tokens: Record<string, number> = {
      surfaceBase: theme.surfaceBase,
      surfacePanel: theme.surfacePanel,
      surfaceElevated: theme.surfaceElevated,
      textPrimary: theme.textPrimary,
      textSecondary: theme.textSecondary,
      textMuted: theme.textMuted,
      accent: theme.accent,
      statusOk: theme.statusOk,
      statusWarn: theme.statusWarn,
      statusErr: theme.statusErr,
      statusMuted: theme.statusMuted,
      border: theme.border,
      borderFocused: theme.borderFocused,
      badgePassed: theme.badgePassed,
      badgeFailed: theme.badgeFailed,
      badgeSkipped: theme.badgeSkipped,
      badgeRunning: theme.badgeRunning,
      progressBar: theme.progressBar,
      progressTrack: theme.progressTrack,
      title: theme.title,
    };
    for (const [key, value] of Object.entries(tokens)) {
      assert(
        value >= -1 && value <= 15,
        `${theme.name}.${key} = ${value}, expected -1..15`,
      );
    }
  }
});

Deno.test("theme: darkTheme surface hierarchy layers are distinct", () => {
  // Each surface layer must be visually distinct
  assert(darkTheme.surfaceBase !== darkTheme.surfacePanel);
  assert(darkTheme.surfacePanel !== darkTheme.surfaceElevated);
  assert(darkTheme.surfaceBase !== darkTheme.surfaceElevated);
});

Deno.test("theme: darkTheme has DEFAULT textPrimary (uses terminal default)", () => {
  assertEquals(darkTheme.textPrimary, -1);
});

Deno.test("theme: lightTheme text is dark for contrast on light background", () => {
  // Light theme must use BLACK (0) for text on white background
  assertEquals(lightTheme.textPrimary, 0);
});

Deno.test("theme: lightTheme surfaceBase is light", () => {
  assertEquals(lightTheme.surfaceBase, 7); // ANSI WHITE
});

Deno.test("theme: themes registry contains all three presets", () => {
  assertEquals(Object.keys(themes).sort(), ["classic", "dark", "light"]);
});

// ---------------------------------------------------------------------------
// setTheme — theme switching
// ---------------------------------------------------------------------------

Deno.test("theme: setTheme switches to light theme", () => {
  setTheme("dark"); // reset to known state
  const original = currentTheme;
  const newTheme = setTheme("light");
  assertEquals(newTheme, lightTheme);
  assertEquals(currentTheme, lightTheme);
  assert(currentTheme !== original);
  setTheme("dark"); // restore
});

Deno.test("theme: setTheme switches to classic theme", () => {
  setTheme("dark");
  const newTheme = setTheme("classic");
  assertEquals(newTheme, classicTheme);
  assertEquals(currentTheme, classicTheme);
  setTheme("dark");
});

Deno.test("theme: setTheme throws on unknown theme name", () => {
  assertThrows(
    () => setTheme("nonexistent"),
    Error,
    "Unknown theme",
  );
});

Deno.test("theme: setTheme returns the new theme", () => {
  setTheme("dark");
  const result = setTheme("light");
  assertEquals(result, lightTheme);
  assertEquals(result, currentTheme);
  setTheme("dark");
});

// ---------------------------------------------------------------------------
// COLORS — backward-compat getters track currentTheme
// ---------------------------------------------------------------------------

Deno.test("theme: COLORS.accent tracks dark theme", () => {
  setTheme("dark");
  assertEquals(COLORS.accent, 5); // MAGENTA
});

Deno.test("theme: COLORS.accent tracks light theme", () => {
  setTheme("light");
  assertEquals(COLORS.accent, 5); // MAGENTA (same accent in light)
  setTheme("dark");
});

Deno.test("theme: COLORS.accent tracks classic theme", () => {
  setTheme("classic");
  assertEquals(COLORS.accent, 6); // CYAN
  setTheme("dark");
});

Deno.test("theme: COLORS getters update when theme is switched", () => {
  setTheme("dark");
  assertEquals(COLORS.accent, 5);
  assertEquals(COLORS.statusOk, 2);

  setTheme("classic");
  assertEquals(COLORS.accent, 6);
  assertEquals(COLORS.statusOk, 2); // green is same in both

  setTheme("dark");
});

Deno.test("theme: COLORS has all expected keys", () => {
  setTheme("dark");
  const expectedKeys = [
    "surfaceBase",
    "surfacePanel",
    "surfaceElevated",
    "textPrimary",
    "textSecondary",
    "textMuted",
    "accent",
    "statusOk",
    "statusWarn",
    "statusErr",
    "statusMuted",
    "border",
    "borderFocused",
    "badgePassed",
    "badgeFailed",
    "badgeSkipped",
    "badgeRunning",
    "progressBar",
    "progressTrack",
    "title",
  ];
  for (const key of expectedKeys) {
    assert(key in COLORS, `COLORS.${key} should exist`);
  }
});

Deno.test("theme: COLORS surface tokens in dark theme", () => {
  setTheme("dark");
  assertEquals(COLORS.surfaceBase, 0);    // BLACK
  assertEquals(COLORS.surfacePanel, 8);   // BRIGHT_BLACK
  assertEquals(COLORS.surfaceElevated, 6); // CYAN (teal, better contrast than dark blue)
});

Deno.test("theme: COLORS status tokens in dark theme use standard colors", () => {
  setTheme("dark");
  assertEquals(COLORS.statusOk, 2);    // GREEN
  assertEquals(COLORS.statusWarn, 3);  // YELLOW
  assertEquals(COLORS.statusErr, 1);   // RED
});

Deno.test("theme: COLORS text tokens in dark theme", () => {
  setTheme("dark");
  assertEquals(COLORS.textPrimary, -1);    // DEFAULT (terminal fg)
  assertEquals(COLORS.textSecondary, 7);   // WHITE (brighter than dim, less than default)
  assertEquals(COLORS.textMuted, 8);       // BRIGHT_BLACK
});

Deno.test("theme: COLORS progress track is darker than panel fill", () => {
  setTheme("dark");
  assertEquals(COLORS.progressTrack, 0);  // BLACK — darker than surfacePanel (8)
  assertEquals(COLORS.progressBar, 2);    // GREEN
});

Deno.test("theme: COLORS border tokens in dark theme", () => {
  setTheme("dark");
  assertEquals(COLORS.border, 8);          // BRIGHT_BLACK (subtle gray)
  assertEquals(COLORS.borderFocused, 5);   // MAGENTA (strawberry)
});

Deno.test("theme: COLORS title uses accent in dark theme", () => {
  setTheme("dark");
  assertEquals(COLORS.title, COLORS.accent);
});

Deno.test("theme: COLORS all getters return valid ANSI after switching to light theme", () => {
  setTheme("light");
  const keys = Object.keys(COLORS) as (keyof typeof COLORS)[];
  for (const key of keys) {
    const value = COLORS[key];
    assert(value >= -1 && value <= 15,
      `COLORS.${key}=${value} out of range in light theme`);
  }
  setTheme("dark");
});

Deno.test("theme: COLORS all getters return valid ANSI after switching to classic theme", () => {
  setTheme("classic");
  const keys = Object.keys(COLORS) as (keyof typeof COLORS)[];
  for (const key of keys) {
    const value = COLORS[key];
    assert(value >= -1 && value <= 15,
      `COLORS.${key}=${value} out of range in classic theme`);
  }
  setTheme("dark");
});

Deno.test("theme: COLORS getters reflect light theme surface tokens after switching", () => {
  setTheme("light");
  assertEquals(COLORS.surfaceBase, 7);        // WHITE
  assertEquals(COLORS.surfacePanel, -1);       // DEFAULT
  assertEquals(COLORS.surfaceElevated, 4);     // BLUE
  setTheme("dark");
});

Deno.test("theme: COLORS getters reflect light theme text tokens after switching", () => {
  setTheme("light");
  assertEquals(COLORS.textPrimary, 0);         // BLACK
  assertEquals(COLORS.textSecondary, 8);       // BRIGHT_BLACK
  assertEquals(COLORS.textMuted, 8);            // BRIGHT_BLACK (converged)
  setTheme("dark");
});

Deno.test("theme: COLORS getters reflect classic theme CYAN tokens after switching", () => {
  setTheme("classic");
  assertEquals(COLORS.accent, 6);              // CYAN
  assertEquals(COLORS.borderFocused, 6);        // CYAN
  assertEquals(COLORS.badgeRunning, 6);         // CYAN
  assertEquals(COLORS.title, 6);                // CYAN
  setTheme("dark");
});

Deno.test("theme: COLORS getters reflect classic theme progress track after switching", () => {
  setTheme("classic");
  assertEquals(COLORS.progressBar, 2);         // GREEN
  assertEquals(COLORS.progressTrack, 8);       // BRIGHT_BLACK
  setTheme("dark");
});

Deno.test("theme: COLORS getters across all three themes have no stale values", () => {
  // Switch through all three themes and check a token that differs in each
  setTheme("dark");
  assertEquals(COLORS.surfaceElevated, 6);     // CYAN in dark
  assertEquals(COLORS.progressTrack, 0);       // BLACK in dark

  setTheme("light");
  assertEquals(COLORS.surfaceElevated, 4);     // BLUE in light
  assertEquals(COLORS.progressTrack, 8);       // BRIGHT_BLACK in light

  setTheme("classic");
  assertEquals(COLORS.surfaceElevated, 4);     // BLUE in classic
  assertEquals(COLORS.progressTrack, 8);       // BRIGHT_BLACK in classic

  // Switch back and verify no stale values
  setTheme("dark");
  assertEquals(COLORS.surfaceElevated, 6);     // restored correctly
  assertEquals(COLORS.progressTrack, 0);       // restored correctly
});

// ---------------------------------------------------------------------------
// GARAZYK_TUI_THEME env var detection — basic properties only
// (can't easily mock Deno.env.get at module load time, so test
//  the themes themselves and the setTheme path)
// ---------------------------------------------------------------------------

Deno.test("theme: theme switching is idempotent", () => {
  setTheme("dark");
  const t1 = currentTheme;
  setTheme("dark");
  const t2 = currentTheme;
  assertEquals(t1, t2);
});

Deno.test("theme: rapid theme switching via COLORS getter consistency", () => {
  setTheme("dark");
  const darkAccent = COLORS.accent;
  setTheme("classic");
  const classicAccent = COLORS.accent;
  setTheme("dark");
  const darkAccentAgain = COLORS.accent;
  assertEquals(darkAccent, darkAccentAgain);
  assert(darkAccent !== classicAccent);
});

Deno.test("theme: all themes have unique names", () => {
  const names = Object.values(themes).map((t) => t.name);
  assertEquals(new Set(names).size, names.length);
});

// ---------------------------------------------------------------------------
// Light theme — explicit token values (focus on what differs from dark)
// ---------------------------------------------------------------------------

Deno.test("theme: lightTheme surface hierarchy — white base, default panel, blue elevated", () => {
  assertEquals(lightTheme.surfaceBase, 7);       // WHITE
  assertEquals(lightTheme.surfacePanel, -1);      // DEFAULT (terminal bg)
  assertEquals(lightTheme.surfaceElevated, 4);    // BLUE
});

Deno.test("theme: lightTheme surface hierarchy layers are distinct", () => {
  assert(lightTheme.surfaceBase !== lightTheme.surfacePanel);
  assert(lightTheme.surfacePanel !== lightTheme.surfaceElevated);
  assert(lightTheme.surfaceBase !== lightTheme.surfaceElevated);
});

Deno.test("theme: lightTheme text tokens — dark text on light bg", () => {
  assertEquals(lightTheme.textPrimary, 0);        // BLACK
  assertEquals(lightTheme.textSecondary, 8);      // BRIGHT_BLACK (gray)
  assertEquals(lightTheme.textMuted, 8);          // BRIGHT_BLACK (gray)
});

Deno.test("theme: lightTheme uses MAGENTA accent (same brand as dark)", () => {
  assertEquals(lightTheme.accent, 5);             // MAGENTA
  assertEquals(lightTheme.borderFocused, 5);       // MAGENTA
  assertEquals(lightTheme.badgeRunning, 5);        // MAGENTA
  assertEquals(lightTheme.title, 5);               // MAGENTA
});

Deno.test("theme: lightTheme progress — GREEN bar, BRIGHT_BLACK track", () => {
  assertEquals(lightTheme.progressBar, 2);        // GREEN
  assertEquals(lightTheme.progressTrack, 8);      // BRIGHT_BLACK (lighter than dark's BLACK)
});

Deno.test("theme: lightTheme status tokens use standard traffic-light colors", () => {
  assertEquals(lightTheme.statusOk, 2);           // GREEN
  assertEquals(lightTheme.statusWarn, 3);         // YELLOW
  assertEquals(lightTheme.statusErr, 1);          // RED
  assertEquals(lightTheme.statusMuted, 8);        // BRIGHT_BLACK
});

Deno.test("theme: lightTheme border and badge tokens", () => {
  assertEquals(lightTheme.border, 8);              // BRIGHT_BLACK
  assertEquals(lightTheme.badgePassed, 2);         // GREEN
  assertEquals(lightTheme.badgeFailed, 1);         // RED
  assertEquals(lightTheme.badgeSkipped, 3);        // YELLOW
});

// ---------------------------------------------------------------------------
// Classic theme — explicit token values (focus on what differs from dark)
// ---------------------------------------------------------------------------

Deno.test("theme: classicTheme surface hierarchy — black, grey, blue", () => {
  assertEquals(classicTheme.surfaceBase, 0);       // BLACK (same as dark)
  assertEquals(classicTheme.surfacePanel, 8);      // BRIGHT_BLACK (same as dark)
  assertEquals(classicTheme.surfaceElevated, 4);   // BLUE (classic blue cursor)
});

Deno.test("theme: classicTheme surface hierarchy layers are distinct", () => {
  assert(classicTheme.surfaceBase !== classicTheme.surfacePanel);
  assert(classicTheme.surfacePanel !== classicTheme.surfaceElevated);
  assert(classicTheme.surfaceBase !== classicTheme.surfaceElevated);
});

Deno.test("theme: classicTheme text tokens", () => {
  assertEquals(classicTheme.textPrimary, -1);      // DEFAULT (terminal fg)
  assertEquals(classicTheme.textSecondary, 8);     // BRIGHT_BLACK
  assertEquals(classicTheme.textMuted, 8);         // BRIGHT_BLACK
});

Deno.test("theme: classicTheme CYAN throughout (accent, border, badge, title)", () => {
  assertEquals(classicTheme.accent, 6);            // CYAN
  assertEquals(classicTheme.borderFocused, 6);      // CYAN
  assertEquals(classicTheme.badgeRunning, 6);       // CYAN
  assertEquals(classicTheme.title, 6);              // CYAN
});

Deno.test("theme: classicTheme progress — GREEN bar, BRIGHT_BLACK track", () => {
  assertEquals(classicTheme.progressBar, 2);       // GREEN
  assertEquals(classicTheme.progressTrack, 8);     // BRIGHT_BLACK
});

Deno.test("theme: classicTheme status tokens use standard traffic-light colors", () => {
  assertEquals(classicTheme.statusOk, 2);          // GREEN
  assertEquals(classicTheme.statusWarn, 3);        // YELLOW
  assertEquals(classicTheme.statusErr, 1);         // RED
  assertEquals(classicTheme.statusMuted, 8);       // BRIGHT_BLACK
});

Deno.test("theme: classicTheme border and badge tokens", () => {
  assertEquals(classicTheme.border, 8);             // BRIGHT_BLACK
  assertEquals(classicTheme.badgePassed, 2);        // GREEN
  assertEquals(classicTheme.badgeFailed, 1);        // RED
  assertEquals(classicTheme.badgeSkipped, 3);       // YELLOW
});

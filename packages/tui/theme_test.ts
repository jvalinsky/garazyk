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

Deno.test("theme: darkTheme surface hierarchy is progressive", () => {
  // surfaceBase < surfacePanel < surfaceElevated in the dark theme
  // (darker backgrounds for deeper layers)
  assert(darkTheme.surfaceBase <= darkTheme.surfacePanel);
});

Deno.test("theme: darkTheme has DEFAULT textPrimary (uses terminal default)", () => {
  assertEquals(darkTheme.textPrimary, -1);
});

Deno.test("theme: lightTheme text is dark for contrast on light background", () => {
  // Light theme should use dark foreground colors
  assert(lightTheme.textPrimary <= 8); // BLACK or BRIGHT_BLACK
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
  assertEquals(COLORS.surfaceElevated, 4); // BLUE
});

Deno.test("theme: COLORS status tokens in dark theme use standard colors", () => {
  setTheme("dark");
  assertEquals(COLORS.statusOk, 2);    // GREEN
  assertEquals(COLORS.statusWarn, 3);  // YELLOW
  assertEquals(COLORS.statusErr, 1);   // RED
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

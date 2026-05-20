/**
 * Reusable Terminal User Interface primitives for Deno applications.
 *
 * This module exports only pure types and functions — no Deno I/O.
 * For terminal mode, key reading, and environment queries, import
 * from `@garazyk/tui/runtime` instead.
 *
 * @module
 */

// ── Screen buffer and cell types ──────────────────────────────────────────
export type { CellStyle, Cell } from "./renderer.ts";
export {
  DEFAULT_STYLE,
  ScreenBuffer,
  ANSI,
  RESET,
  ENTER_ALT_SCREEN,
  EXIT_ALT_SCREEN,
  HIDE_CURSOR,
  SHOW_CURSOR,
  CLEAR_SCREEN,
  CURSOR_HOME,
  fg,
  bg,
  bold,
  dim,
  reverse,
  underline,
  mergeStyles,
} from "./renderer.ts";

// ── Theme system ───────────────────────────────────────────────────────────
export type { Theme } from "./theme.ts";
export { COLORS, getCurrentTheme, setCurrentTheme, darkTheme, lightTheme, classicTheme, themes } from "./theme.ts";

// ── Key types and parsing (pure) ───────────────────────────────────────────
export type { Key } from "./input.ts";
export { Keys, parseKey, isKey, isCtrl, isQuit } from "./input.ts";

// ── Layout ─────────────────────────────────────────────────────────────────
export type { LayoutNode, ResolvedNode, Direction, Sizing } from "./layout_tree.ts";
export { solveLayout, findResolvedNode, flattenResolvedNodes } from "./layout_tree.ts";
export type { BoundingBox, PanelId } from "./layout_engine.ts";
export { PANEL_IDS, PANEL_TITLES, panelContentArea, findPanel } from "./layout.ts";
export { dashboardLayoutTree } from "./dashboard_layout.ts";

// ── Focus ──────────────────────────────────────────────────────────────────
export { FocusRing } from "./focus.ts";

// ── Render commands ────────────────────────────────────────────────────────
export type { RenderCommand } from "./command.ts";
export { rasterize } from "./command.ts";

// ── Text utilities ────────────────────────────────────────────────────────
export { truncate, getCharWidth } from "./text.ts";

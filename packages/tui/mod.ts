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
export type { Cell, CellStyle } from "./renderer.ts";
export {
  ANSI,
  bg,
  bold,
  CLEAR_SCREEN,
  CURSOR_HOME,
  DEFAULT_STYLE,
  dim,
  ENTER_ALT_SCREEN,
  EXIT_ALT_SCREEN,
  fg,
  HIDE_CURSOR,
  mergeStyles,
  RESET,
  reverse,
  ScreenBuffer,
  SHOW_CURSOR,
  underline,
} from "./renderer.ts";

// ── Theme system ───────────────────────────────────────────────────────────
export type { Theme } from "./theme.ts";
export {
  classicTheme,
  COLORS,
  darkTheme,
  getCurrentTheme,
  lightTheme,
  setCurrentTheme,
  themes,
} from "./theme.ts";

// ── Key types and parsing (pure) ───────────────────────────────────────────
export type { Key } from "./input.ts";
export { isCtrl, isKey, isQuit, Keys, parseKey } from "./input.ts";

// ── Layout ─────────────────────────────────────────────────────────────────
export type {
  Direction,
  LayoutNode,
  ResolvedNode,
  Sizing,
} from "./layout_tree.ts";
export {
  findResolvedNode,
  flattenResolvedNodes,
  solveLayout,
} from "./layout_tree.ts";
export type { BoundingBox, PanelId } from "./layout_engine.ts";
export {
  findPanel,
  PANEL_IDS,
  PANEL_TITLES,
  panelContentArea,
} from "./layout.ts";
export { dashboardLayoutTree } from "./dashboard_layout.ts";

// ── Focus ──────────────────────────────────────────────────────────────────
export { FocusRing } from "./focus.ts";

// ── Render commands ────────────────────────────────────────────────────────
export type {
  BoxCommand,
  RectCommand,
  RenderCommand,
  ScrollBoxCommand,
  TextCommand,
} from "./command.ts";
export { rasterize } from "./command.ts";

// ── Text utilities ────────────────────────────────────────────────────────
export { getCharWidth, truncate } from "./text.ts";

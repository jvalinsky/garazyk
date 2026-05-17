/**
 * TUI module — terminal UI for the Garazyk scenario dashboard.
 *
 * @module tui
 */

export { ScreenBuffer, ANSI, COLORS, DEFAULT_STYLE, RESET, ENTER_ALT_SCREEN, EXIT_ALT_SCREEN, HIDE_CURSOR, SHOW_CURSOR, CLEAR_SCREEN, CURSOR_HOME, fg, bg, bold, dim, reverse, underline, mergeStyles, enterTerminalMode, exitTerminalMode, writeToTerminal, isTerminal, getTerminalSize } from "./renderer.ts";
export type { CellStyle, Cell } from "./renderer.ts";

export { readKeys, Keys, isKey, isCtrl, isQuit } from "./input.ts";
export type { Key } from "./input.ts";

export { computeLayout, panelContentArea, findPanel, PANEL_IDS, PANEL_TITLES } from "./layout.ts";
export type { PanelId, PanelLayout, DashboardLayout } from "./layout.ts";

export { FocusRing } from "./focus.ts";

export { createPanelStates, createPanelState, moveCursorUp, moveCursorDown, clampPanelState } from "./panel_state.ts";
export type { PanelState, PanelStates } from "./panel_state.ts";

export { createTuiRuntime } from "./runtime.ts";
export type { TuiRuntimeHandle } from "./runtime.ts";

export { renderView } from "./view.ts";

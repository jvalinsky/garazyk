/**
 * Panel State — per-panel cursor and scroll tracking
 *
 * Each panel tracks its own cursor row (for arrow-key navigation)
 * and scroll offset (for when content exceeds the visible area).
 *
 * @module tui/panel_state
 */

import type { PanelId } from "@garazyk/tui";
import { PANEL_IDS } from "@garazyk/tui";

/** State for a single panel. */
export interface PanelState {
  /** Currently selected row index (0-based, relative to panel content). */
  cursor: number;
  /** Scroll offset: first visible row of content. */
  scrollOffset: number;
  /** Total number of selectable items in this panel. */
  itemCount: number;
}

/** Create a default panel state. */
export function createPanelState(itemCount = 0): PanelState {
  return { cursor: 0, scrollOffset: 0, itemCount };
}

/** All four panel states keyed by panel ID. */
export type PanelStates = Record<PanelId, PanelState>;

/** Create default panel states for all four panels. */
export function createPanelStates(): PanelStates {
  const states: Partial<PanelStates> = {};
  for (const id of PANEL_IDS) {
    states[id] = createPanelState();
  }
  return states as PanelStates;
}

/** Move cursor up by one row, scrolling if needed. */
export function moveCursorUp(state: PanelState, visibleRows: number): PanelState {
  if (state.cursor <= 0) return state;
  const newCursor = state.cursor - 1;
  const newOffset = newCursor < state.scrollOffset
    ? newCursor
    : state.scrollOffset;
  return { ...state, cursor: newCursor, scrollOffset: newOffset };
}

/** Move cursor down by one row, scrolling if needed. */
export function moveCursorDown(state: PanelState, visibleRows: number): PanelState {
  if (state.cursor >= state.itemCount - 1) return state;
  const newCursor = state.cursor + 1;
  const newOffset = newCursor >= state.scrollOffset + visibleRows
    ? newCursor - visibleRows + 1
    : state.scrollOffset;
  return { ...state, cursor: newCursor, scrollOffset: Math.max(0, newOffset) };
}

/** Clamp cursor and scroll after itemCount changes. Ensures cursor remains visible. */
export function clampPanelState(state: PanelState, itemCount: number, visibleRows: number): PanelState {
  const maxCursor = Math.max(0, itemCount - 1);
  const cursor = Math.min(state.cursor, maxCursor);
  // Clamp scroll offset to valid range
  const maxOffset = Math.max(0, itemCount - visibleRows);
  let scrollOffset = Math.min(state.scrollOffset, maxOffset);
  // Enforce cursor visibility invariant: scrollOffset <= cursor < scrollOffset + visibleRows
  if (cursor < scrollOffset) {
    scrollOffset = cursor;
  } else if (visibleRows > 0 && cursor >= scrollOffset + visibleRows) {
    scrollOffset = cursor - visibleRows + 1;
  }
  return { ...state, cursor, scrollOffset, itemCount };
}

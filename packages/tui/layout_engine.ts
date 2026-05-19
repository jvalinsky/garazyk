/**
 * Pure Layout Engine
 *
 * Provides pure layout computation functions that calculate panel geometry
 * without performing any rendering operations. Separates layout math from
 * rendering concerns following "Primitives over Features" principles.
 *
 * @module tui/layout_engine
 */

import type { BoundingBox } from "./command.ts";

// Re-export BoundingBox for convenience
export type { BoundingBox };

/** Panel identifier. */
export type PanelId = "network" | "scenarios" | "run" | "history";

/** All panel IDs in focus order. */
export const PANEL_IDS: PanelId[] = ["network", "scenarios", "run", "history"];

/** Panel display titles. */
export const PANEL_TITLES: Record<PanelId, string> = {
  network: "Network",
  scenarios: "Scenarios",
  run: "Active Run",
  history: "Run History",
};

/** Computed position and size for a single panel. */
export interface PanelLayout {
  id: PanelId;
  x: number;
  y: number;
  width: number;
  height: number;
}

/** Full layout: all panels + status bar + hint bar. */
export interface DashboardLayout {
  /** All panel positions */
  panels: PanelLayout[];
  /** Status bar position */
  statusBar: { x: number; y: number; width: number };
  /** Hint bar position */
  hintBar: { x: number; y: number; width: number };
  /** Total terminal dimensions */
  cols: number;
  rows: number;
}

/** Minimum terminal size for wide (2x2) layout. */
const WIDE_THRESHOLD = 100;

/** Minimum terminal size for reasonable display. */
const MIN_COLS = 40;
const MIN_ROWS = 16;

/** Status bar height. */
const STATUS_BAR_H = 1;

/** Hint bar height. */
const HINT_BAR_H = 1;

/** Gap between panels. */
const GAP = 1;

/**
 * Compute panel layout for the given terminal dimensions.
 *
 * Returns null if the terminal is too small (cols < 40 or rows < 16).
 * Uses a 2x2 grid layout for wide terminals (cols >= 100) and a
 * vertical stack for narrow terminals.
 *
 * @param cols - Terminal column count
 * @param rows - Terminal row count
 * @returns DashboardLayout with 4 non-overlapping panels, or null if too small
 */
export function computeLayout(cols: number, rows: number): DashboardLayout | null {
  if (cols < MIN_COLS || rows < MIN_ROWS) return null;

  const statusBar = { x: 0, y: 0, width: cols };
  const hintBar = { x: 0, y: rows - 1, width: cols };

  // Available space for panels (between status bar and hint bar)
  const availRows = rows - STATUS_BAR_H - HINT_BAR_H;
  const availCols = cols;

  if (cols >= WIDE_THRESHOLD) {
    return computeWideLayout(availCols, availRows, STATUS_BAR_H, statusBar, hintBar, cols, rows);
  } else {
    return computeNarrowLayout(availCols, availRows, STATUS_BAR_H, statusBar, hintBar, cols, rows);
  }
}

/**
 * Compute 2x2 grid layout for wide terminals (cols >= 100).
 *
 * Arranges panels as:
 * ```
 * [network  ] [run    ]
 * [scenarios] [history]
 * ```
 *
 * @param availCols - Available columns for panels
 * @param availRows - Available rows for panels
 * @param startY - Y offset where panels begin (after status bar)
 * @param statusBar - Status bar position descriptor
 * @param hintBar - Hint bar position descriptor
 * @param cols - Total terminal columns
 * @param rows - Total terminal rows
 * @returns DashboardLayout with 2x2 panel arrangement
 */
export function computeWideLayout(
  availCols: number,
  availRows: number,
  startY: number,
  statusBar: { x: number; y: number; width: number },
  hintBar: { x: number; y: number; width: number },
  cols: number,
  rows: number,
): DashboardLayout {
  const halfCols = Math.floor((availCols - GAP) / 2);
  const halfRows = Math.floor((availRows - GAP) / 2);

  const leftX = 0;
  const rightX = halfCols + GAP;
  const topY = startY;
  const bottomY = startY + halfRows + GAP;

  // Right column gets remaining width
  const rightWidth = availCols - rightX;

  const panels: PanelLayout[] = [
    { id: "network", x: leftX, y: topY, width: halfCols, height: halfRows },
    { id: "scenarios", x: leftX, y: bottomY, width: halfCols, height: availRows - halfRows - GAP },
    { id: "run", x: rightX, y: topY, width: rightWidth, height: halfRows },
    { id: "history", x: rightX, y: bottomY, width: rightWidth, height: availRows - halfRows - GAP },
  ];

  return { panels, statusBar, hintBar, cols, rows };
}

/**
 * Compute vertical stack layout for narrow terminals (cols < 100).
 *
 * Arranges all four panels in a single column, each taking roughly
 * one quarter of the available rows.
 *
 * @param availCols - Available columns for panels
 * @param availRows - Available rows for panels
 * @param startY - Y offset where panels begin (after status bar)
 * @param statusBar - Status bar position descriptor
 * @param hintBar - Hint bar position descriptor
 * @param cols - Total terminal columns
 * @param rows - Total terminal rows
 * @returns DashboardLayout with vertical stack panel arrangement
 */
export function computeNarrowLayout(
  availCols: number,
  availRows: number,
  startY: number,
  statusBar: { x: number; y: number; width: number },
  hintBar: { x: number; y: number; width: number },
  cols: number,
  rows: number,
): DashboardLayout {
  // Each panel gets roughly 1/4 of available rows
  const panelHeight = Math.floor((availRows - 3 * GAP) / 4);
  const panelWidth = availCols;

  const panels: PanelLayout[] = PANEL_IDS.map((id, i) => ({
    id,
    x: 0,
    y: startY + i * (panelHeight + GAP),
    width: panelWidth,
    height: panelHeight,
  }));

  // Fix last panel height to fill remaining space
  const lastPanel = panels[3]!;
  lastPanel.height = startY + availRows - lastPanel.y;

  return { panels, statusBar, hintBar, cols, rows };
}

/**
 * Complete geometry for a panel including outer bounds, inner content area,
 * and scrollable region.
 */
export interface PanelGeometry {
  /** Full panel including borders */
  outer: BoundingBox;
  /** Content area inside borders */
  inner: BoundingBox;
  /** Area for scrollable content (inner minus action hints if present) */
  scrollable: BoundingBox;
}

/** Border width (1 cell on each side). */
const BORDER = 1;

/** Action hints row height. */
const ACTION_HINTS_HEIGHT = 1;

/**
 * Compute complete geometry for a panel.
 *
 * Takes a panel layout and computes three bounding boxes:
 * - outer: The full panel including borders
 * - inner: The content area inside borders
 * - scrollable: The area available for scrollable content (inner minus action hints)
 *
 * @param panel - Panel layout with position and dimensions
 * @param hasActionHints - Whether the panel displays action hints (reduces scrollable height)
 * @returns Complete panel geometry with outer, inner, and scrollable bounds
 *
 * @example
 * ```typescript
 * const panel = { id: "network", x: 0, y: 1, width: 50, height: 20 };
 * const geometry = computePanelGeometry(panel, true);
 * // geometry.outer = { x: 0, y: 1, width: 50, height: 20 }
 * // geometry.inner = { x: 1, y: 2, width: 48, height: 18 }
 * // geometry.scrollable = { x: 1, y: 2, width: 48, height: 17 }
 * ```
 */
export function computePanelGeometry(
  panel: PanelLayout,
  hasActionHints = false,
): PanelGeometry {
  const outer: BoundingBox = {
    x: panel.x,
    y: panel.y,
    width: panel.width,
    height: panel.height,
  };

  const inner: BoundingBox = {
    x: panel.x + BORDER,
    y: panel.y + BORDER,
    width: Math.max(0, panel.width - 2 * BORDER),
    height: Math.max(0, panel.height - 2 * BORDER),
  };

  const scrollableHeight = hasActionHints
    ? Math.max(0, inner.height - ACTION_HINTS_HEIGHT)
    : inner.height;

  const scrollable: BoundingBox = {
    x: inner.x,
    y: inner.y,
    width: inner.width,
    height: scrollableHeight,
  };

  return { outer, inner, scrollable };
}

/**
 * Check if two bounding boxes overlap.
 *
 * Two boxes overlap if they share any interior points. Boxes that only
 * touch at edges or corners are not considered overlapping.
 *
 * @param a - First bounding box
 * @param b - Second bounding box
 * @returns true if boxes overlap, false otherwise
 *
 * @example
 * ```typescript
 * const box1 = { x: 0, y: 0, width: 10, height: 10 };
 * const box2 = { x: 5, y: 5, width: 10, height: 10 };
 * overlaps(box1, box2); // true
 *
 * const box3 = { x: 10, y: 0, width: 10, height: 10 };
 * overlaps(box1, box3); // false (only touching at edge)
 * ```
 */
export function overlaps(a: BoundingBox, b: BoundingBox): boolean {
  return (
    a.x < b.x + b.width &&
    a.x + a.width > b.x &&
    a.y < b.y + b.height &&
    a.y + a.height > b.y
  );
}

/**
 * Check if a bounding box is contained within another bounding box.
 *
 * Box `inner` is contained in `outer` if all points of `inner` are
 * within or on the boundary of `outer`.
 *
 * @param inner - The box that should be contained
 * @param outer - The containing box
 * @returns true if inner is fully contained within outer
 *
 * @example
 * ```typescript
 * const outer = { x: 0, y: 0, width: 100, height: 50 };
 * const inner = { x: 10, y: 10, width: 20, height: 20 };
 * contains(inner, outer); // true
 *
 * const partial = { x: 50, y: 40, width: 60, height: 20 };
 * contains(partial, outer); // false (extends beyond outer)
 * ```
 */
export function contains(inner: BoundingBox, outer: BoundingBox): boolean {
  return (
    inner.x >= outer.x &&
    inner.y >= outer.y &&
    inner.x + inner.width <= outer.x + outer.width &&
    inner.y + inner.height <= outer.y + outer.height
  );
}

/**
 * Check if a point is within a bounding box.
 *
 * @param x - X coordinate of the point
 * @param y - Y coordinate of the point
 * @param box - Bounding box to test against
 * @returns true if point is within box bounds
 *
 * @example
 * ```typescript
 * const box = { x: 10, y: 10, width: 20, height: 20 };
 * pointInBox(15, 15, box); // true
 * pointInBox(5, 5, box);   // false
 * pointInBox(30, 30, box); // false (on boundary)
 * ```
 */
export function pointInBox(x: number, y: number, box: BoundingBox): boolean {
  return (
    x >= box.x &&
    x < box.x + box.width &&
    y >= box.y &&
    y < box.y + box.height
  );
}

/**
 * Clip a bounding box to fit within another bounding box.
 *
 * Returns the intersection of the two boxes. If the boxes don't overlap,
 * returns a box with zero width or height.
 *
 * @param box - Box to be clipped
 * @param clipRegion - Clipping region
 * @returns Clipped bounding box
 *
 * @example
 * ```typescript
 * const box = { x: 0, y: 0, width: 100, height: 50 };
 * const clip = { x: 50, y: 25, width: 100, height: 50 };
 * const clipped = clipBox(box, clip);
 * // clipped = { x: 50, y: 25, width: 50, height: 25 }
 * ```
 */
export function clipBox(box: BoundingBox, clipRegion: BoundingBox): BoundingBox {
  const x1 = Math.max(box.x, clipRegion.x);
  const y1 = Math.max(box.y, clipRegion.y);
  const x2 = Math.min(box.x + box.width, clipRegion.x + clipRegion.width);
  const y2 = Math.min(box.y + box.height, clipRegion.y + clipRegion.height);

  return {
    x: x1,
    y: y1,
    width: Math.max(0, x2 - x1),
    height: Math.max(0, y2 - y1),
  };
}

/**
 * Validate that a bounding box has valid dimensions.
 *
 * A valid bounding box must have:
 * - Non-negative x and y coordinates
 * - Positive width and height
 *
 * @param box - Bounding box to validate
 * @returns true if box is valid
 *
 * @example
 * ```typescript
 * isValidBox({ x: 0, y: 0, width: 10, height: 10 }); // true
 * isValidBox({ x: -1, y: 0, width: 10, height: 10 }); // false
 * isValidBox({ x: 0, y: 0, width: 0, height: 10 }); // false
 * ```
 */
export function isValidBox(box: BoundingBox): boolean {
  return box.x >= 0 && box.y >= 0 && box.width > 0 && box.height > 0;
}

/**
 * Translate a bounding box by an offset.
 *
 * @param box - Box to translate
 * @param dx - Horizontal offset
 * @param dy - Vertical offset
 * @returns New bounding box at translated position
 *
 * @example
 * ```typescript
 * const box = { x: 10, y: 10, width: 20, height: 20 };
 * const translated = translateBox(box, 5, -3);
 * // translated = { x: 15, y: 7, width: 20, height: 20 }
 * ```
 */
export function translateBox(box: BoundingBox, dx: number, dy: number): BoundingBox {
  return {
    x: box.x + dx,
    y: box.y + dy,
    width: box.width,
    height: box.height,
  };
}

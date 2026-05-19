/**
 * Panel Layout Engine
 *
 * Computes panel positions and sizes based on terminal dimensions.
 * Uses a widget dashboard layout (2x2 grid) on wide terminals,
 * and a vertical stack on narrow terminals.
 *
 * @module tui/layout
 */

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

/** Border padding (1 cell each side). */
const BORDER = 1;

/** Gap between panels. */
const GAP = 1;

/**
 * Compute panel layout for the given terminal dimensions.
 * Returns null if the terminal is too small.
 */
export function computeLayout(cols: number, rows: number): DashboardLayout | null {
  if (cols < MIN_COLS || rows < MIN_ROWS) return null;

  const statusBar = { x: 0, y: 0, width: cols };
  const hintBar = { x: 0, y: rows - 1, width: cols };

  // Available space for panels (between status bar and hint bar)
  const availRows = rows - STATUS_BAR_H - HINT_BAR_H;
  const availCols = cols;

  if (cols >= WIDE_THRESHOLD) {
    return wideLayout(availCols, availRows, STATUS_BAR_H, statusBar, hintBar, cols, rows);
  } else {
    return narrowLayout(availCols, availRows, STATUS_BAR_H, statusBar, hintBar, cols, rows);
  }
}

/** 2x2 grid layout for wide terminals. */
function wideLayout(
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

/** Vertical stack layout for narrow terminals. */
function narrowLayout(
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
    height: i === 3
      ? availRows - 3 * (panelHeight + GAP) - panelHeight + panelHeight // last panel gets remaining
      : panelHeight,
  }));

  // Fix last panel height to fill remaining space
  const lastPanel = panels[3]!;
  lastPanel.height = startY + availRows - lastPanel.y;

  return { panels, statusBar, hintBar, cols, rows };
}

/**
 * Get the inner content area of a panel (inside borders).
 */
export function panelContentArea(panel: PanelLayout): {
  x: number;
  y: number;
  width: number;
  height: number;
} {
  return {
    x: panel.x + BORDER,
    y: panel.y + BORDER,
    width: Math.max(0, panel.width - 2 * BORDER),
    height: Math.max(0, panel.height - 2 * BORDER),
  };
}

/**
 * Find a panel layout by ID.
 */
export function findPanel(layout: DashboardLayout, id: PanelId): PanelLayout | undefined {
  return layout.panels.find((p) => p.id === id);
}

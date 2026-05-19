/**
 * Panel Layout Engine
 *
 * Computes panel positions and sizes based on terminal dimensions.
 * Uses a widget dashboard layout (2x2 grid) on wide terminals,
 * and a vertical stack on narrow terminals.
 *
 * Layout computation is delegated to `layout_engine.ts`. This module
 * re-exports the public API for backwards compatibility.
 *
 * @module tui/layout
 */

export type {
  DashboardLayout,
  PanelId,
  PanelLayout,
} from "./layout_engine.ts";

export {
  computeLayout,
  computeNarrowLayout,
  computeWideLayout,
  PANEL_IDS,
  PANEL_TITLES,
} from "./layout_engine.ts";

import type { DashboardLayout, PanelId, PanelLayout } from "./layout_engine.ts";

/** Border padding (1 cell each side). */
const BORDER = 1;

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

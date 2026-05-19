/**
 * Dashboard Layout Tree Definition
 *
 * Builds a declarative LayoutNode tree for the scenario dashboard.
 * The tree is resolved by `solveLayout()` from `layout_tree.ts`
 * to produce absolute panel coordinates.
 *
 * Wide terminals (cols >= 100) get a 2x2 grid:
 *   [status-bar                              ]
 *   [network  ] [run    ]
 *   [scenarios] [history]
 *   [hint-bar                               ]
 *
 * Narrow terminals (cols < 100) get a vertical stack:
 *   [status-bar]
 *   [network   ]
 *   [scenarios ]
 *   [run       ]
 *   [history   ]
 *   [hint-bar  ]
 *
 * @module tui/dashboard_layout
 */

import type { LayoutNode } from "./layout_tree.ts";

/** Minimum terminal size for reasonable display. */
const MIN_COLS = 40;
const MIN_ROWS = 16;

/** Wide layout threshold. */
const WIDE_THRESHOLD = 100;

/** Status bar height in rows. */
const STATUS_BAR_H = 1;

/** Hint bar height in rows. */
const HINT_BAR_H = 1;

/** Gap between panels in cells. */
const GAP = 1;

/**
 * Build the dashboard layout tree for the given terminal dimensions.
 *
 * Returns null if the terminal is too small (cols < 40 or rows < 16).
 * The returned tree should be passed to `solveLayout()` to compute
 * absolute coordinates for all panels.
 *
 * @param cols - Terminal column count
 * @param rows - Terminal row count
 * @returns LayoutNode tree for the dashboard, or null if too small
 */
export function dashboardLayoutTree(
  cols: number,
  rows: number,
): LayoutNode | null {
  if (cols < MIN_COLS || rows < MIN_ROWS) return null;

  if (cols >= WIDE_THRESHOLD) {
    return wideLayoutTree();
  } else {
    return narrowLayoutTree();
  }
}

/**
 * Build the wide (2x2 grid) layout tree.
 *
 * Structure:
 *   column root
 *     row "status-bar" (height: 1)
 *     row (height: grow, gap: 1)
 *       column (width: grow, gap: 1)
 *         "network"  (height: grow)
 *         "scenarios" (height: grow)
 *       column (width: grow, gap: 1)
 *         "run"      (height: grow)
 *         "history"  (height: grow)
 *     row "hint-bar" (height: 1)
 */
function wideLayoutTree(): LayoutNode {
  return {
    direction: "column",
    children: [
      { id: "status-bar", height: STATUS_BAR_H },
      {
        direction: "row",
        height: "grow",
        gap: GAP,
        children: [
          {
            direction: "column",
            width: "grow",
            gap: GAP,
            children: [
              { id: "network", height: "grow" },
              { id: "scenarios", height: "grow" },
            ],
          },
          {
            direction: "column",
            width: "grow",
            gap: GAP,
            children: [
              { id: "run", height: "grow" },
              { id: "history", height: "grow" },
            ],
          },
        ],
      },
      { id: "hint-bar", height: HINT_BAR_H },
    ],
  };
}

/**
 * Build the narrow (vertical stack) layout tree.
 *
 * Structure:
 *   column root
 *     row "status-bar" (height: 1)
 *     column (height: grow, gap: 1) — panel area
 *       "network"   (height: grow)
 *       "scenarios" (height: grow)
 *       "run"       (height: grow)
 *       "history"   (height: grow)
 *     row "hint-bar" (height: 1)
 */
function narrowLayoutTree(): LayoutNode {
  return {
    direction: "column",
    children: [
      { id: "status-bar", height: STATUS_BAR_H },
      {
        direction: "column",
        height: "grow",
        gap: GAP,
        children: [
          { id: "network", height: "grow" },
          { id: "scenarios", height: "grow" },
          { id: "run", height: "grow" },
          { id: "history", height: "grow" },
        ],
      },
      { id: "hint-bar", height: HINT_BAR_H },
    ],
  };
}

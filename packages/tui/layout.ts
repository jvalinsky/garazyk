/**
 * Panel Layout — Public API
 *
 * Re-exports layout types and utilities. Layout tree construction
 * is in `dashboard_layout.ts` and tree solving is in `layout_tree.ts`.
 *
 * @module tui/layout
 */

export type { PanelId, PanelLayout } from "./layout_engine.ts";

export { PANEL_IDS, PANEL_TITLES } from "./layout_engine.ts";

export { dashboardLayoutTree } from "./dashboard_layout.ts";

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

import type { ResolvedNode } from "./layout_tree.ts";

/** Border padding (1 cell each side). */
const BORDER = 1;

/**
 * Get the inner content area of a resolved panel node (inside borders).
 *
 * @param node - A resolved layout node with absolute coordinates
 * @returns The inner content area inside the 1-cell border
 */
export function panelContentArea(node: ResolvedNode): {
  x: number;
  y: number;
  width: number;
  height: number;
} {
  return {
    x: node.x + BORDER,
    y: node.y + BORDER,
    width: Math.max(0, node.width - 2 * BORDER),
    height: Math.max(0, node.height - 2 * BORDER),
  };
}

/**
 * Find a resolved panel node by ID in the tree.
 *
 * @param root - The resolved layout tree
 * @param id - The panel ID to search for
 * @returns The found node or undefined
 */
export function findPanel(
  root: ResolvedNode,
  id: string,
): ResolvedNode | undefined {
  if (root.id === id) return root;
  for (const child of root.children) {
    const found = findPanel(child, id);
    if (found) return found;
  }
  return undefined;
}

/**
 * Generic Tree-Based Layout Solver
 *
 * Implements a declarative layout engine inspired by Yoga and Clay.
 * Computes bounding boxes for a tree of nodes with fixed or growing
 * dimensions, supporting both row and column directions with gaps.
 *
 * @module tui/layout_tree
 */

import type { BoundingBox } from "./command.ts";

/** Layout direction for children of a node. */
export type Direction = "row" | "column";

/** Sizing constraint for a dimension. */
export type Sizing = number | "grow";

/** A node in the layout tree. */
export interface LayoutNode {
  /** Optional identifier for the resolved node. */
  id?: string;
  /** Layout direction for children (default: "column"). */
  direction?: Direction;
  /** Width constraint (default: "grow"). */
  width?: Sizing;
  /** Height constraint (default: "grow"). */
  height?: Sizing;
  /** Space between children (default: 0). */
  gap?: number;
  /** Child nodes. */
  children?: LayoutNode[];
}

/** A resolved layout node with absolute coordinates. */
export interface ResolvedNode extends BoundingBox {
  /** Identifier from the layout node. */
  id?: string;
  /** Resolved child nodes. */
  children: ResolvedNode[];
}

/**
 * Solve the layout tree starting from a root container.
 *
 * Calculates absolute positions and dimensions for the entire tree
 * within the given root bounding box.
 *
 * @param root - The layout tree definition
 * @param bounds - The bounding box to fit the tree into
 * @returns A tree of resolved nodes with absolute coordinates
 */
export function solveLayout(root: LayoutNode, bounds: BoundingBox): ResolvedNode {
  const resolvedChildren: ResolvedNode[] = [];
  const children = root.children || [];
  const direction = root.direction || "column";
  const gap = root.gap || 0;

  if (children.length > 0) {
    const isRow = direction === "row";
    const totalGap = Math.max(0, (children.length - 1) * gap);
    
    // Calculate fixed sizes and count growing children
    let fixedSize = totalGap;
    let growCount = 0;
    for (const child of children) {
      const size = isRow ? child.width : child.height;
      if (typeof size === "number") {
        fixedSize += size;
      } else {
        growCount++;
      }
    }

    // Distribute remaining space among growing children.
    // Floor the base size and give remainder pixels to the last growing child
    // to ensure all coordinates are integers (terminal cells are discrete).
    const availSize = isRow ? bounds.width : bounds.height;
    const totalGrow = growCount > 0 ? Math.max(0, availSize - fixedSize) : 0;
    const baseGrowSize = growCount > 0 ? Math.floor(totalGrow / growCount) : 0;
    const remainder = growCount > 0 ? totalGrow - baseGrowSize * growCount : 0;

    let offset = 0;
    let growIndex = 0;
    for (const child of children) {
      const isGrow = isRow
        ? typeof child.width !== "number"
        : typeof child.height !== "number";

      // Last growing child gets the remainder pixels
      const extra = (isGrow && growIndex === growCount - 1) ? remainder : 0;
      const childWidth = typeof child.width === "number"
        ? child.width
        : (isRow ? baseGrowSize + extra : bounds.width);
      const childHeight = typeof child.height === "number"
        ? child.height
        : (isRow ? bounds.height : baseGrowSize + extra);

      if (isGrow) growIndex++;

      const childBounds: BoundingBox = {
        x: bounds.x + (isRow ? offset : 0),
        y: bounds.y + (isRow ? 0 : offset),
        width: childWidth,
        height: childHeight,
      };

      resolvedChildren.push(solveLayout(child, childBounds));
      offset += (isRow ? childWidth : childHeight) + gap;
    }
  }

  return {
    id: root.id,
    x: bounds.x,
    y: bounds.y,
    width: bounds.width,
    height: bounds.height,
    children: resolvedChildren,
  };
}

/**
 * Find a resolved node by ID in the tree.
 *
 * @param root - The resolved layout tree
 * @param id - The ID to search for
 * @returns The found node or undefined
 */
export function findResolvedNode(root: ResolvedNode, id: string): ResolvedNode | undefined {
  if (root.id === id) return root;
  for (const child of root.children) {
    const found = findResolvedNode(child, id);
    if (found) return found;
  }
  return undefined;
}

/**
 * Flatten a resolved tree into a flat array of nodes.
 *
 * Useful for iterating over all panels to draw them.
 *
 * @param root - The resolved layout tree
 * @returns Flat array of all nodes in the tree
 */
export function flattenResolvedNodes(root: ResolvedNode): ResolvedNode[] {
  const result = [root];
  for (const child of root.children) {
    result.push(...flattenResolvedNodes(child));
  }
  return result;
}

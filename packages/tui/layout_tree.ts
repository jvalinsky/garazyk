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
  /** Minimum width constraint. */
  minWidth?: number;
  /** Maximum width constraint. */
  maxWidth?: number;
  /** Minimum height constraint. */
  minHeight?: number;
  /** Maximum height constraint. */
  maxHeight?: number;
  /** Space between children (default: 0). */
  gap?: number;
  /** Padding inside the node (default: 0). */
  padding?: number | {
    top?: number;
    right?: number;
    bottom?: number;
    left?: number;
  };
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
export function solveLayout(
  root: LayoutNode,
  bounds: BoundingBox,
): ResolvedNode {
  const resolvedChildren: ResolvedNode[] = [];
  const children = root.children || [];
  const direction = root.direction || "column";
  const gap = root.gap || 0;

  // Resolve padding
  const p = typeof root.padding === "number"
    ? {
      top: root.padding,
      right: root.padding,
      bottom: root.padding,
      left: root.padding,
    }
    : {
      top: root.padding?.top || 0,
      right: root.padding?.right || 0,
      bottom: root.padding?.bottom || 0,
      left: root.padding?.left || 0,
    };

  // Content area within padding
  const contentX = bounds.x + p.left;
  const contentY = bounds.y + p.top;
  const contentWidth = Math.max(0, bounds.width - p.left - p.right);
  const contentHeight = Math.max(0, bounds.height - p.top - p.bottom);

  if (children.length > 0) {
    const isRow = direction === "row";
    const totalGap = Math.max(0, (children.length - 1) * gap);
    const mainAxisSize = isRow ? contentWidth : contentHeight;
    const crossAxisSize = isRow ? contentHeight : contentWidth;

    // Step 1: Initialize child sizes and identify growing children
    const childMainSizes = new Array(children.length).fill(0);
    const growingIndices: number[] = [];

    let consumedMainSize = totalGap;

    for (let i = 0; i < children.length; i++) {
      const child = children[i];
      const size = isRow ? child.width : child.height;
      const min = isRow ? child.minWidth : child.minHeight;
      const max = isRow ? child.maxWidth : child.maxHeight;

      if (typeof size === "number") {
        let s = size;
        if (min !== undefined) s = Math.max(s, min);
        if (max !== undefined) s = Math.min(s, max);
        childMainSizes[i] = s;
        consumedMainSize += s;
      } else {
        growingIndices.push(i);
        // "grow" children start with their minimum size (if any)
        const s = min || 0;
        childMainSizes[i] = s;
        consumedMainSize += s;
      }
    }

    // Step 2: Distribute remaining space among growing children
    let remainingSpace = mainAxisSize - consumedMainSize;

    if (remainingSpace > 0 && growingIndices.length > 0) {
      // Iteratively distribute to respect maxWidth
      let activeIndices = [...growingIndices];
      while (remainingSpace > 0 && activeIndices.length > 0) {
        const perChild = Math.floor(remainingSpace / activeIndices.length);
        if (perChild === 0) break; // Remainder pixels handled below

        let DistributedAny = false;
        const nextActiveIndices: number[] = [];

        for (const idx of activeIndices) {
          const child = children[idx];
          const max = isRow ? child.maxWidth : child.maxHeight;
          const current = childMainSizes[idx];

          if (max !== undefined && current >= max) {
            // Already at max
            continue;
          }

          const canTake = max !== undefined ? max - current : Infinity;
          const take = Math.min(perChild, canTake);

          if (take > 0) {
            childMainSizes[idx] += take;
            remainingSpace -= take;
            DistributedAny = true;
          }

          if (max === undefined || childMainSizes[idx] < max) {
            nextActiveIndices.push(idx);
          }
        }

        if (!DistributedAny) break;
        activeIndices = nextActiveIndices;
      }

      // Step 3: Distribute remainder pixels to the last growing child that can still take them
      if (remainingSpace > 0) {
        for (let i = growingIndices.length - 1; i >= 0; i--) {
          const idx = growingIndices[i];
          const child = children[idx];
          const max = isRow ? child.maxWidth : child.maxHeight;
          if (max === undefined || childMainSizes[idx] < max) {
            childMainSizes[idx] += remainingSpace;
            remainingSpace = 0;
            break;
          }
        }
      }
    }

    // Step 4: Resolve cross-axis sizes and child positions
    let offset = 0;
    for (let i = 0; i < children.length; i++) {
      const child = children[i];
      const mainSize = childMainSizes[i];

      const crossSizeRaw = isRow ? child.height : child.width;
      const crossMin = isRow ? child.minHeight : child.minWidth;
      const crossMax = isRow ? child.maxHeight : child.maxWidth;

      let crossSize: number;
      if (typeof crossSizeRaw === "number") {
        crossSize = crossSizeRaw;
      } else {
        crossSize = crossAxisSize;
      }

      if (crossMin !== undefined) crossSize = Math.max(crossSize, crossMin);
      if (crossMax !== undefined) crossSize = Math.min(crossSize, crossMax);

      const childWidth = isRow ? mainSize : crossSize;
      const childHeight = isRow ? crossSize : mainSize;

      const childBounds: BoundingBox = {
        x: isRow ? contentX + offset : contentX,
        y: isRow ? contentY : contentY + offset,
        width: childWidth,
        height: childHeight,
      };

      resolvedChildren.push(solveLayout(child, childBounds));
      offset += mainSize + gap;
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
export function findResolvedNode(
  root: ResolvedNode,
  id: string,
): ResolvedNode | undefined {
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

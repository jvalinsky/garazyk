/**
 * Terminal DOM (TDOM) Serializer
 *
 * Provides functions to serialize physical layout boundaries (ResolvedNodes)
 * combined with their rendered character grids in the ScreenBuffer into a structured,
 * queryable tree format. Excellent for semantic testing and LLM visual grounding.
 *
 * @module tui/testing/tdom
 */

import type { ScreenBuffer } from "../renderer.ts";
import type { ResolvedNode } from "../layout_tree.ts";
import type { BoundingBox } from "../command.ts";

/** A single semantic node in the Terminal DOM (TDOM). */
export interface TdomElement {
  /** The identifier of the node (e.g. "scenarios-list", "header"). */
  id?: string;
  /** Absolute x position in terminal cell columns. */
  x: number;
  /** Absolute y position in terminal cell rows. */
  y: number;
  /** Width of the component area. */
  width: number;
  /** Height of the component area. */
  height: number;
  /** Consolidated clean text visible inside the component bounds. */
  text: string;
  /** Hierarchical child components. */
  children: TdomElement[];
}

/** Extracts text content from a ScreenBuffer within a specific bounding region. */
export function extractTextFromBounds(
  buf: ScreenBuffer,
  bounds: BoundingBox,
): string {
  const lines: string[] = [];
  const startX = Math.max(0, bounds.x);
  const startY = Math.max(0, bounds.y);
  const endX = Math.min(buf.width, bounds.x + bounds.width);
  const endY = Math.min(buf.height, bounds.y + bounds.height);

  for (let y = startY; y < endY; y++) {
    let line = "";
    for (let x = startX; x < endX; x++) {
      const cell = buf.getCell(x, y);
      line += cell ? (cell.char || " ") : " ";
    }
    const trimmed = line.trim();
    if (trimmed.length > 0) {
      lines.push(trimmed);
    }
  }

  return lines.join("\n");
}

/**
 * Serializes a solved layout tree (ResolvedNode) into a TdomElement tree
 * by reading character contents directly from the ScreenBuffer.
 */
export function serializeTdom(
  buf: ScreenBuffer,
  layout: ResolvedNode,
): TdomElement {
  const text = extractTextFromBounds(buf, layout);
  const children = (layout.children || []).map((child) =>
    serializeTdom(buf, child)
  );

  return {
    id: layout.id,
    x: layout.x,
    y: layout.y,
    width: layout.width,
    height: layout.height,
    text,
    children,
  };
}

/** Renders a TDOM tree as a structured, indented XML string for LLMs. */
export function renderTdomToXml(element: TdomElement, depth = 0): string {
  const indent = "  ".repeat(depth);
  const tag = element.id || "div";
  const attrs =
    `x="${element.x}" y="${element.y}" w="${element.width}" h="${element.height}"`;

  if (element.children.length === 0) {
    if (!element.text) {
      return `${indent}<${tag} ${attrs} />`;
    }
    // Inline text content
    const escapedText = element.text.replace(/</g, "&lt;").replace(
      />/g,
      "&gt;",
    );
    return `${indent}<${tag} ${attrs}>${escapedText}</${tag}>`;
  }

  const childXml = element.children.map((c) => renderTdomToXml(c, depth + 1))
    .join("\n");
  const baseXml = `${indent}<${tag} ${attrs}>\n${childXml}\n${indent}</${tag}>`;
  return baseXml;
}

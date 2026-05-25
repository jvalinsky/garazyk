import { extractTree } from "../scenario-dashboard/tui_scanner.ts";
import type { TuiElement } from "../scenario-dashboard/tui_types.ts";
import type { TuiSession } from "./session.ts";
import type { ElementMeta } from "../scenario-dashboard/tui_types.ts";

export interface SnapshotOptions {
  boxes?: boolean;
  panel?: string;
}

export function buildSnapshot(
  session: TuiSession,
  metaMap: Map<string, ElementMeta>,
  options: SnapshotOptions,
): string {
  const root = extractTree(session.harness.buffer, metaMap);
  const lines: string[] = [];

  if (root.children.length === 0) {
    return '- state "empty screen"';
  }

  let targetNode: TuiElement | null = root;
  if (options.panel) {
    const panelRef = normalizePanelRef(options.panel);
    targetNode = findElementById(root, panelRef);
    if (!targetNode) {
      throw new Error(`Panel scope not found: ${options.panel}`);
    }
  }

  // We skip emitting the root element itself, just its children
  if (targetNode === root) {
    for (const child of root.children) {
      formatTreeToYaml(child, lines, options.boxes, 0);
    }
  } else {
    formatTreeToYaml(targetNode, lines, options.boxes, 0);
  }

  return lines.join("\n");
}

function normalizePanelRef(panel: string): string {
  return panel.startsWith("panel.") ? panel : `panel.${panel}`;
}

function findElementById(node: TuiElement, id: string): TuiElement | null {
  if (node.id === id) return node;
  for (const child of node.children) {
    const found = findElementById(child, id);
    if (found) return found;
  }
  return null;
}

function formatTreeToYaml(
  el: TuiElement,
  lines: string[],
  includeBoxes = false,
  indent = 0,
): string {
  const prefix = "  ".repeat(indent) + "- ";

  const attrs: string[] = [];

  if (el.id && !el.id.startsWith("layer2_")) {
    attrs.push(`ref=${el.id}`);
  }

  if (el.interactable) {
    attrs.push("interactable");
  }

  if (el.focused) {
    attrs.push("focused");
  }

  for (const state of el.states) {
    attrs.push(state);
  }

  if (includeBoxes) {
    attrs.push(
      `box=${el.bounds.x},${el.bounds.y},${el.bounds.width},${el.bounds.height}`,
    );
  }

  const attrStr = attrs.length > 0 ? ` [${attrs.join("] [")}]` : "";
  let nameStr = el.label ? ` "${el.label}"` : "";
  if (!el.label && el.content) {
    nameStr = ` "${el.content}"`;
  }

  lines.push(`${prefix}${el.type}${nameStr}${attrStr}`);

  for (const child of el.children) {
    formatTreeToYaml(child, lines, includeBoxes, indent + 1);
  }

  return lines.join("\n");
}

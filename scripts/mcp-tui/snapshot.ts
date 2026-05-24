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
    return "- state \"empty screen\"";
  }

  // Find target panel if scope is provided
  let targetNode: TuiElement | null = null;
  if (options.panel) {
    for (const child of root.children) {
      if (child.id === options.panel) {
        targetNode = child;
        break;
      }
    }
  }

  const nodeToFormat = targetNode || root;

  // We skip emitting the root element itself, just its children
  if (nodeToFormat === root) {
    for (const child of root.children) {
      formatTreeToYaml(child, lines, options.boxes, 0);
    }
  } else {
    formatTreeToYaml(nodeToFormat, lines, options.boxes, 0);
  }

  return lines.join("\n");
}

function formatTreeToYaml(el: TuiElement, lines: string[], includeBoxes = false, indent = 0): string {
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
    attrs.push(`box=${el.bounds.x},${el.bounds.y},${el.bounds.width},${el.bounds.height}`);
  }
  
  let attrStr = attrs.length > 0 ? ` [${attrs.join("] [")}]` : "";
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

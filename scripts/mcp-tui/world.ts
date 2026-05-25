import {
  buildTuiWorldFromElements,
  type TuiWorld,
  type WorldElementInput,
} from "@garazyk/tui/testing";
import { extractTree } from "../scenario-dashboard/tui_scanner.ts";
import type {
  ElementMeta,
  TuiElement,
} from "../scenario-dashboard/tui_types.ts";
import type { VirtualTuiHarness } from "@garazyk/tui/testing";

function stateFromElement(element: TuiElement): Record<string, unknown> {
  const state: Record<string, unknown> = {
    interactable: element.interactable,
    focused: element.focused,
  };
  if (element.states.length > 0) {
    state.states = element.states;
  }
  for (const value of element.states) {
    if (/^[A-Za-z_][A-Za-z0-9_:-]*$/.test(value)) {
      state[value] = true;
    }
  }
  if (element.cursorPosition) {
    state.cursorPosition = element.cursorPosition;
  }
  return state;
}

function flattenElements(root: TuiElement): WorldElementInput[] {
  const inputs: WorldElementInput[] = [];
  const visit = (element: TuiElement, sourceIndex: number) => {
    if (element.role !== "application") {
      inputs.push({
        ref: element.id,
        source: element.id.startsWith("layer2_")
          ? "detector:tui_scanner"
          : "metadata:dashboard",
        sourceIndex,
        role: element.role,
        domain: element.role === "table"
          ? "table"
          : element.interactable
          ? "form"
          : "generic",
        label: element.label ?? element.content ?? element.id,
        content: element.content,
        bounds: element.bounds,
        state: stateFromElement(element),
        actions: element.actions,
        confidence: element.id.startsWith("layer2_") ? 0.65 : 0.95,
      });
    }
    element.children.forEach((child, index) =>
      visit(child, inputs.length + index)
    );
  };
  visit(root, 0);
  return inputs;
}

export function buildDashboardWorld(
  harness: VirtualTuiHarness,
  metaMap: Map<string, ElementMeta>,
  frameId = "dashboard:current",
): TuiWorld {
  const root = extractTree(harness.buffer, metaMap);
  return buildTuiWorldFromElements({
    frameId,
    viewport: { width: harness.buffer.width, height: harness.buffer.height },
    sourceId: "metadata:dashboard",
    elements: flattenElements(root),
  });
}

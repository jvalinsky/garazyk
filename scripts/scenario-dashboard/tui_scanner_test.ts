import { assertEquals, assert } from "@std/assert";
import { ScreenBuffer } from "@garazyk/tui";
import { classifyChar, classifyBuffer, findContainers, extractTree } from "./tui_scanner.ts";
import type { ElementMeta, CharToken, Rect } from "./tui_types.ts";

Deno.test("tui_scanner - classifyChar maps Unicode accurately", () => {
  const dummyStyle = { fg: -1, bg: -1, bold: false, underline: false, reverse: false, dim: false };

  // Box drawing corners
  assertEquals(classifyChar("┌", dummyStyle), "corner_tl");
  assertEquals(classifyChar("┐", dummyStyle), "corner_tr");
  assertEquals(classifyChar("└", dummyStyle), "corner_bl");
  assertEquals(classifyChar("┘", dummyStyle), "corner_br");

  // Edges
  assertEquals(classifyChar("─", dummyStyle), "edge_h");
  assertEquals(classifyChar("│", dummyStyle), "edge_v");

  // Block shading
  assertEquals(classifyChar("█", dummyStyle), "block_full");
  assertEquals(classifyChar("░", dummyStyle), "shade_light");
  assertEquals(classifyChar("▒", dummyStyle), "shade_med");
  assertEquals(classifyChar("▓", dummyStyle), "shade_dark");

  // Interactive markers
  assertEquals(classifyChar("☐", dummyStyle), "checkbox_off");
  assertEquals(classifyChar("☑", dummyStyle), "checkbox_on");
  assertEquals(classifyChar("☒", dummyStyle), "checkbox_off"); // Mixed maps to off
  
  assertEquals(classifyChar("●", dummyStyle), "radio_on");
  assertEquals(classifyChar("○", dummyStyle), "radio_off");
  
  assertEquals(classifyChar("▶", dummyStyle), "expand_collapsed");
  assertEquals(classifyChar("▼", dummyStyle), "expand_expanded");

  // Arrows
  assertEquals(classifyChar("↑", dummyStyle), "scroll_up");
  assertEquals(classifyChar("↓", dummyStyle), "scroll_down");

  // Fallbacks
  assertEquals(classifyChar(" ", dummyStyle), "whitespace");
  assertEquals(classifyChar("A", dummyStyle), "text");
});

Deno.test("tui_scanner - extractTree generic Layer 2 fallback", () => {
  const buf = new ScreenBuffer(40, 10, { noColor: true });
  
  // Draw a container manually
  buf.write(2, 2, "┌────────────────┐");
  buf.write(2, 3, "│ [X] Option 1   │");
  buf.write(2, 4, "│ ( ) Option 2   │");
  buf.write(2, 5, "│ <Submit>       │");
  buf.write(2, 6, "└────────────────┘");

  const root = extractTree(buf);
  
  // Root should be a container sized 40x10
  assertEquals(root.type, "container");
  assertEquals(root.bounds.width, 40);
  assertEquals(root.bounds.height, 10);
  
  // Should have one direct child (the 18x5 layer2 container)
  assertEquals(root.children.length, 1);
  const c = root.children[0];
  assertEquals(c.type, "container");
  assertEquals(c.bounds.x, 2);
  assertEquals(c.bounds.y, 2);
  assertEquals(c.bounds.width, 18);
  assertEquals(c.bounds.height, 5);
  
  // Inside the container, there should be interactable elements detected via Layer 2 heuristics
  // [X] checkbox, ( ) radio, <Submit> button
  const checkbox = c.children.find(el => el.type === "checkbox");
  assert(checkbox, "Checkbox not detected");
  assertEquals(checkbox.states, ["checked"]);
  
  const radio = c.children.find(el => el.type === "radio");
  assert(radio, "Radio not detected");
  assertEquals(radio.states, ["unchecked"]);
  
  const button = c.children.find(el => el.type === "button");
  assert(button, "Button not detected");
  assertEquals(button.label, "Submit");
});

Deno.test("tui_scanner - extractTree merges Layer 1 meta", () => {
  const buf = new ScreenBuffer(40, 10, { noColor: true });
  
  // Draw a container manually
  buf.write(2, 2, "┌────────────────┐");
  buf.write(2, 3, "│ Hello World    │");
  buf.write(2, 4, "└────────────────┘");

  const metaMap = new Map<string, ElementMeta>();
  metaMap.set("panel.main", {
    role: "panel",
    interactable: true,
    focused: true,
    states: ["active"],
    bounds: { x: 2, y: 2, width: 18, height: 3 },
    ref: "panel.main",
    label: "Main Panel",
    actions: ["click"]
  });

  const root = extractTree(buf, metaMap);
  
  assertEquals(root.children.length, 1);
  const panel = root.children[0];
  assertEquals(panel.id, "panel.main");
  assertEquals(panel.type, "container");
  assertEquals(panel.role, "panel");
  assertEquals(panel.interactable, true);
  assertEquals(panel.focused, true);
  assertEquals(panel.states, ["active"]);
});

Deno.test("tui_scanner - table and list detection heuristics", () => {
  const buf = new ScreenBuffer(40, 10, { noColor: true });
  
  // Draw a table
  buf.write(2, 2, "┌────┬────┐");
  buf.write(2, 3, "│ A  │ B  │");
  buf.write(2, 4, "├────┼────┤"); // This cross activates the table heuristic
  buf.write(2, 5, "│ 1  │ 2  │");
  buf.write(2, 6, "└────┴────┘");
  
  // Draw a list
  buf.write(20, 2, "┌─────────┐");
  buf.write(20, 3, "│ • Item 1│");
  buf.write(20, 4, "│ • Item 2│");
  buf.write(20, 5, "└─────────┘");

  const root = extractTree(buf);
  
  const table = root.children.find(el => el.bounds.x === 2);
  assert(table, "Table container not found");
  assertEquals(table.type, "table");
  
  const list = root.children.find(el => el.bounds.x === 20);
  assert(list, "List container not found");
  assertEquals(list.type, "list");
});

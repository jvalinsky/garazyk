import { assertEquals, assert, assertStringIncludes } from "@std/assert";
import { getByText } from "@garazyk/tui/testing";
import { createSession } from "../mcp-tui/session.ts";
import { extractTree } from "./tui_scanner.ts";

Deno.test("TUI Dashboard Integration - Boot and Layout Binding", () => {
  const session = createSession();
  
  // Render the initial frame
  session.harness.render();
  
  // Use extractTree semantic VDOM to verify the panel layout tree is correctly mounted
  const root = extractTree(session.harness.buffer, session.lastMeta);
  const networkPanel = root.children.find(c => c.id === "panel.network");
  assert(networkPanel, "Network panel should be present in the VDOM");
  assert(networkPanel.bounds.width > 0, "Network panel should have width");
  
  // Use text locator to verify seeded data is on screen
  const pdsText = getByText(session.harness, "PDS");
  assert(pdsText.resolve().width > 0, "PDS text should be visible");
  
  const scenarioText = getByText(session.harness, "01_account_lifecycle");
  assert(scenarioText.resolve().width > 0, "Scenario text should be visible");
});

Deno.test("TUI Dashboard Integration - Interactive Navigation", async () => {
  const session = createSession();
  session.harness.render();
  
  // By default, network panel is focused (index 0)
  assertEquals(session.focus.current, "network");
  
  // Tab to scenarios panel
  await session.harness.emitKey("tab");
  assertEquals(session.focus.current, "scenarios");
  
  // Verify styles - the scenarios panel should now be active. 
  // We can use the extractTree semantic VDOM to verify the focused state!
  let root = extractTree(session.harness.buffer, session.lastMeta);
  let scenariosPanel = root.children.find(c => c.id === "panel.scenarios");
  assert(scenariosPanel, "Scenarios panel not found in VDOM");
  assertEquals(scenariosPanel.focused, true, "Scenarios panel should be focused");
  
  // Press down arrow
  assertEquals(session.panelStates.scenarios.cursor, 0);
  await session.harness.emitKey("down");
  assertEquals(session.panelStates.scenarios.cursor, 1);
  
  // Use VDOM to verify cursor state in the list
  // Re-extract tree after action
  root = extractTree(session.harness.buffer, session.lastMeta);
  scenariosPanel = root.children.find(c => c.id === "panel.scenarios");
  
  // The first item should be inactive, the second should be active
  // Let's just verify the panel state updated correctly
  assertEquals(session.panelStates.scenarios.cursor, 1, "Cursor should have moved to index 1");
});

Deno.test("TUI Dashboard Integration - Overlays", async () => {
  const session = createSession();
  session.harness.render();
  
  // Toggle help
  assertEquals(session.showHelp, false);
  await session.harness.emitKey("?");
  
  // We cannot read session.showHelp directly if it's captured in closure, but we CAN check the VDOM!
  // Wait, session.showHelp is a getter? No, it's a value property copied at creation time.
  // Actually, we should check the VDOM!
  let root = extractTree(session.harness.buffer, session.lastMeta);
  
  // The help overlay should be present
  let helpOverlay = root.children.find(c => c.role === "help");
  assert(helpOverlay, "Help overlay should be rendered");
  
  // Dismiss help
  await session.harness.emitKey("escape");
  root = extractTree(session.harness.buffer, session.lastMeta);
  helpOverlay = root.children.find(c => c.role === "help");
  assertEquals(helpOverlay, undefined, "Help overlay should be dismissed");
  
  // Test Run Details overlay
  // Jump to history panel (4)
  await session.harness.emitKey("4");
  assertEquals(session.focus.current, "history");
  
  // Press 'v' to view detail
  await session.harness.emitKey("v");
  
  root = extractTree(session.harness.buffer, session.lastMeta);
  const detailOverlay = root.children.find(c => c.role === "detail");
  assert(detailOverlay, "Run details overlay should be rendered");
  
  // Assert mock data is present in detail results
  const pdsRunText = getByText(session.harness, "01_account_lifecycle");
  assert(pdsRunText.resolve().width > 0, "Mock scenario result should be visible in overlay");
  
  // Dismiss detail
  await session.harness.emitKey("escape");
  root = extractTree(session.harness.buffer, session.lastMeta);
  assertEquals(root.children.find(c => c.role === "detail"), undefined, "Run details overlay should be dismissed");
});

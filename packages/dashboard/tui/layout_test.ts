/**
 * Tests for the layout engine.
 *
 * @module tui/layout_test
 */

import { assertEquals, assert } from "jsr:@std/assert";
import { computeLayout, panelContentArea, findPanel, PANEL_IDS, PANEL_TITLES } from "./layout.ts";

Deno.test("computeLayout: returns null for too-small terminal", () => {
  assertEquals(computeLayout(39, 20), null);
  assertEquals(computeLayout(80, 15), null);
  assertEquals(computeLayout(20, 10), null);
});

Deno.test("computeLayout: wide layout (100+ cols)", () => {
  const layout = computeLayout(120, 30);
  assert(layout !== null);
  assertEquals(layout!.cols, 120);
  assertEquals(layout!.rows, 30);
  assertEquals(layout!.panels.length, 4);

  // Status bar at top
  assertEquals(layout!.statusBar.y, 0);
  // Hint bar at bottom
  assertEquals(layout!.hintBar.y, 29);

  // All panels should have positive dimensions
  for (const panel of layout!.panels) {
    assert(panel.width > 0, `Panel ${panel.id} width should be > 0`);
    assert(panel.height > 0, `Panel ${panel.id} height should be > 0`);
  }

  // Network and Run should be in top row
  const network = findPanel(layout!, "network")!;
  const run = findPanel(layout!, "run")!;
  assert(network.y <= run.y, "Network should be at or above Run");

  // Scenarios and History should be below
  const scenarios = findPanel(layout!, "scenarios")!;
  const history = findPanel(layout!, "history")!;
  assert(scenarios.y >= network.y + network.height - 1, "Scenarios should be below Network");
});

Deno.test("computeLayout: narrow layout (< 100 cols)", () => {
  const layout = computeLayout(80, 30);
  assert(layout !== null);
  assertEquals(layout!.panels.length, 4);

  // All panels should be stacked vertically
  for (let i = 1; i < layout!.panels.length; i++) {
    const prev = layout!.panels[i - 1]!;
    const curr = layout!.panels[i]!;
    assert(curr.y > prev.y, `Panel ${curr.id} should be below ${prev.id}`);
  }
});

Deno.test("computeLayout: all four panel IDs present", () => {
  const layout = computeLayout(120, 30);
  assert(layout !== null);
  const ids = layout!.panels.map((p) => p.id);
  assertEquals(ids.sort(), ["history", "network", "run", "scenarios"]);
});

Deno.test("panelContentArea: returns inner area inside borders", () => {
  const panel = { id: "network" as const, x: 5, y: 2, width: 30, height: 10 };
  const area = panelContentArea(panel);
  assertEquals(area.x, 6);
  assertEquals(area.y, 3);
  assertEquals(area.width, 28);
  assertEquals(area.height, 8);
});

Deno.test("panelContentArea: handles small panels", () => {
  const panel = { id: "network" as const, x: 0, y: 0, width: 2, height: 2 };
  const area = panelContentArea(panel);
  assertEquals(area.width, 0);
  assertEquals(area.height, 0);
});

Deno.test("findPanel: finds panel by ID", () => {
  const layout = computeLayout(120, 30)!;
  const network = findPanel(layout, "network");
  assert(network !== undefined);
  assertEquals(network.id, "network");
});

Deno.test("findPanel: returns undefined for unknown ID", () => {
  const layout = computeLayout(120, 30)!;
  assertEquals(findPanel(layout, "unknown" as never), undefined);
});

Deno.test("PANEL_IDS: has 4 entries in correct order", () => {
  assertEquals(PANEL_IDS, ["network", "scenarios", "run", "history"]);
});

Deno.test("PANEL_TITLES: maps all IDs to display names", () => {
  for (const id of PANEL_IDS) {
    assert(PANEL_TITLES[id].length > 0, `Panel ${id} should have a title`);
  }
});

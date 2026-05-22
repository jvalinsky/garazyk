/**
 * Tests for the layout module.
 *
 * @module tui/layout_test
 */

import { assert, assertEquals } from "@std/assert";
import {
  dashboardLayoutTree,
  findPanel,
  PANEL_IDS,
  PANEL_TITLES,
  panelContentArea,
  solveLayout,
} from "./layout.ts";

Deno.test("dashboardLayoutTree: returns null for too-small terminal", () => {
  assertEquals(dashboardLayoutTree(39, 20), null);
  assertEquals(dashboardLayoutTree(80, 15), null);
  assertEquals(dashboardLayoutTree(20, 10), null);
});

Deno.test("dashboardLayoutTree + solveLayout: wide layout (100+ cols)", () => {
  const tree = dashboardLayoutTree(120, 30);
  assert(tree !== null);
  const layout = solveLayout(tree, { x: 0, y: 0, width: 120, height: 30 });

  // Status bar at top
  const statusBar = findPanel(layout, "status-bar");
  assert(statusBar !== undefined);
  assertEquals(statusBar.y, 0);
  assertEquals(statusBar.height, 1);

  // Hint bar at bottom
  const hintBar = findPanel(layout, "hint-bar");
  assert(hintBar !== undefined);
  assertEquals(hintBar.y, 29);
  assertEquals(hintBar.height, 1);

  // All four panels should have positive dimensions
  for (const id of PANEL_IDS) {
    const panel = findPanel(layout, id);
    assert(panel !== undefined, `Panel ${id} should exist`);
    assert(panel.width > 0, `Panel ${id} width should be > 0`);
    assert(panel.height > 0, `Panel ${id} height should be > 0`);
  }

  // Network and Run should be in top row
  const network = findPanel(layout, "network")!;
  const run = findPanel(layout, "run")!;
  assert(network.y <= run.y, "Network should be at or above Run");

  // Scenarios and History should be below
  const scenarios = findPanel(layout, "scenarios")!;
  assert(
    scenarios.y >= network.y + network.height - 1,
    "Scenarios should be below Network",
  );
});

Deno.test("dashboardLayoutTree + solveLayout: narrow layout (< 100 cols)", () => {
  const tree = dashboardLayoutTree(80, 30);
  assert(tree !== null);
  const layout = solveLayout(tree, { x: 0, y: 0, width: 80, height: 30 });

  // All four panels should be stacked vertically
  const panelPositions = PANEL_IDS.map((id) => findPanel(layout, id)!);
  for (let i = 1; i < panelPositions.length; i++) {
    const prev = panelPositions[i - 1]!;
    const curr = panelPositions[i]!;
    assert(curr.y > prev.y, `Panel ${curr.id} should be below ${prev.id}`);
  }
});

Deno.test("dashboardLayoutTree + solveLayout: all four panel IDs present", () => {
  const tree = dashboardLayoutTree(120, 30);
  assert(tree !== null);
  const layout = solveLayout(tree, { x: 0, y: 0, width: 120, height: 30 });

  const ids = PANEL_IDS.filter((id) => findPanel(layout, id) !== undefined);
  assertEquals(ids.sort(), ["history", "network", "run", "scenarios"]);
});

Deno.test("panelContentArea: returns inner area inside borders", () => {
  const node = {
    id: "network" as const,
    x: 5,
    y: 2,
    width: 30,
    height: 10,
    children: [] as never[],
  };
  const area = panelContentArea(node);
  assertEquals(area.x, 6);
  assertEquals(area.y, 3);
  assertEquals(area.width, 28);
  assertEquals(area.height, 8);
});

Deno.test("panelContentArea: handles small panels", () => {
  const node = {
    id: "network" as const,
    x: 0,
    y: 0,
    width: 2,
    height: 2,
    children: [] as never[],
  };
  const area = panelContentArea(node);
  assertEquals(area.width, 0);
  assertEquals(area.height, 0);
});

Deno.test("findPanel: finds panel by ID", () => {
  const tree = dashboardLayoutTree(120, 30)!;
  const layout = solveLayout(tree, { x: 0, y: 0, width: 120, height: 30 });
  const network = findPanel(layout, "network");
  assert(network !== undefined);
  assertEquals(network.id, "network");
});

Deno.test("findPanel: returns undefined for unknown ID", () => {
  const tree = dashboardLayoutTree(120, 30)!;
  const layout = solveLayout(tree, { x: 0, y: 0, width: 120, height: 30 });
  assertEquals(findPanel(layout, "unknown"), undefined);
});

Deno.test("PANEL_IDS: has 4 entries in correct order", () => {
  assertEquals(PANEL_IDS, ["network", "scenarios", "run", "history"]);
});

Deno.test("PANEL_TITLES: maps all IDs to display names", () => {
  for (const id of PANEL_IDS) {
    assert(PANEL_TITLES[id].length > 0, `Panel ${id} should have a title`);
  }
});

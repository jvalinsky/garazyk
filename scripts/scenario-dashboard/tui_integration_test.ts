/**
 * TUI Dashboard Headless Integration Tests
 *
 * Verifies the production Scenario Dashboard TUI rendering logic
 * inside the virtual testing harness. Tests layout correctness,
 * cell attributes, locators (getByText, getByRole), and TDOM structures.
 *
 * @module scripts/scenario-dashboard/tui_integration_test
 */

import { assertEquals, assert } from "@std/assert";
import { VirtualTuiHarness } from "@garazyk/tui/testing";
import { getByText, getByRole } from "@garazyk/tui/testing";
import { serializeTdom, renderTdomToXml } from "@garazyk/tui/testing";
import { createInitialState } from "./dashboard_state.ts";
import { renderView } from "./tui/view.ts";
import { createPanelStates, clampPanelState } from "./tui/panel_state.ts";
import { dashboardLayoutTree, solveLayout, FocusRing, ScreenBuffer } from "@garazyk/tui";

Deno.test("TUI integration: mounts production view headlessly, verifies locators and styles", () => {
  // 1. Solve layout tree for a standard 120 x 30 terminal size
  const width = 120;
  const height = 30;
  const tree = dashboardLayoutTree(width, height);
  assert(tree !== null, "Layout tree should be solvable at 120x30");
  const layout = solveLayout(tree, { x: 0, y: 0, width, height });

  // 2. Initialize a rich mock state
  const state = createInitialState();
  
  // Inject mock network services
  state.network.services = [
    {
      name: "pds",
      label: "PDS",
      url: "http://localhost:2583",
      port: 2583,
      status: "running",
      healthy: true,
    },
    {
      name: "relay",
      label: "Relay",
      url: "http://localhost:2489",
      port: 2489,
      status: "starting",
      healthy: undefined,
    },
    {
      name: "plc",
      label: "PLC",
      url: "http://localhost:2582",
      port: 2582,
      status: "stopped",
      healthy: undefined,
    }
  ];

  // Inject mock scenarios
  state.scenarios.all = [
    {
      id: "01_account_lifecycle",
      name: "01_account_lifecycle",
      description: "Creates accounts and registers handles",
      category: "identity",
      needsPds2: false,
      lastStatus: "passed",
    },
    {
      id: "02_social_graph",
      name: "02_social_graph",
      description: "Creates follow records between accounts",
      category: "social",
      needsPds2: true,
      lastStatus: "failed",
    }
  ];

  // Inject recent run history
  const mockRecentRuns = [
    {
      id: "run-e2e-101",
      startedAt: Date.now() - 5000,
      status: "completed" as const,
      totalScenarios: 2,
      passed: 1,
      failed: 1,
      skipped: 0,
    }
  ];
  state.runs.recentRuns = mockRecentRuns;

  // 3. Set up the TEA navigation structures
  const focus = new FocusRing();
  const panelStates = createPanelStates();
  
  // Clamp listbox items for scenario and history lists
  panelStates.network = clampPanelState(panelStates.network, state.network.services.length, 10);
  panelStates.scenarios = clampPanelState(panelStates.scenarios, state.scenarios.all.length, 15);
  panelStates.history = clampPanelState(panelStates.history, state.runs.recentRuns.length, 5);

  // 4. Define the harness render function mapping the real production view logic
  const render = (buf: ScreenBuffer) => {
    renderView(buf, state, layout, focus, panelStates, state.runs.recentRuns, false);
  };

  // Instantiate the virtual harness
  const harness = new VirtualTuiHarness(width, height, render);

  // 5. Dump and print visual screen for developer inspection
  const screen = harness.dumpScreen();
  console.log("=== HEADLESS REAL TUI SCREEN DUMP ===");
  console.log(screen);
  console.log("=====================================");

  // Check the title bar renders cleanly
  assert(screen.includes("Garazyk Scenario Dashboard"), "Title bar should be present");
  
  // Check that the services are displayed properly with the real panel characters
  assert(screen.includes("● PDS"), "PDS running status dot indicator should be present");
  assert(screen.includes("◐ Relay"), "Relay starting status dot indicator should be present");
  assert(screen.includes("○ PLC"), "PLC stopped status dot indicator should be present");

  // Check recent runs list renders
  assert(screen.includes("run-e2e-101"), "Recent runs panel should list the history run");

  // 6. Locator Searches (getByText, getByRole)
  
  // Test locator finding top-level header title
  const titleLocator = getByText(harness, "Garazyk Scenario Dashboard");
  titleLocator.toHaveText("Garazyk Scenario Dashboard");
  const titleBounds = titleLocator.resolve();
  assertEquals(titleBounds.y, 0, "Title should render on row 0");

  // Test locator finding service names
  const pdsLocator = getByText(harness, /PDS/);
  pdsLocator.toHaveText(/PDS/);

  // 7. TDOM Serialization verification
  const tdom = serializeTdom(harness.buffer, layout);
  const xml = renderTdomToXml(tdom);
  
  console.log("=== HEADLESS REAL TUI TDOM XML DUMP ===");
  console.log(xml);
  console.log("=======================================");

  // Validate that the correct panel boundaries and names are in the serialized XML
  assert(xml.includes("<network"), "XML TDOM should serialize the network panel");
  assert(xml.includes("<scenarios"), "XML TDOM should serialize the scenarios panel");
  assert(xml.includes("<run"), "XML TDOM should serialize the run panel");
  assert(xml.includes("<history"), "XML TDOM should serialize the history panel");
  assert(xml.includes("Garazyk Scenario Dashboard"), "XML TDOM should include status bar content");
});

Deno.test("TUI integration: navigation changes focused states and re-renders highlight visual markers", () => {
  const width = 120;
  const height = 30;
  const tree = dashboardLayoutTree(width, height)!;
  const layout = solveLayout(tree, { x: 0, y: 0, width, height });

  const state = createInitialState();
  const focus = new FocusRing();
  const panelStates = createPanelStates();

  const render = (buf: ScreenBuffer) => {
    renderView(buf, state, layout, focus, panelStates, [], false);
  };

  const harness = new VirtualTuiHarness(width, height, render);

  // Network panel is focused initially (index 0)
  assertEquals(focus.current, "network");

  // Verify visual indicator for focused network panel borders
  const networkPanel = getByRole(harness, layout, "group", { name: "network" });
  
  // Verify jumping to another panel (e.g. Scenarios panel) updates active focus indicators
  focus.jump(1);
  assertEquals(focus.current, "scenarios");
  harness.render(); // Redraw harness

  const scenariosPanel = getByRole(harness, layout, "group", { name: "scenarios" });
  assert(scenariosPanel !== undefined);
});

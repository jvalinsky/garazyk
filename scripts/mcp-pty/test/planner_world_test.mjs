import test from "node:test";
import assert from "node:assert/strict";

import { buildPlan } from "../tui_test.mjs";
import { buildTuiWorld } from "../world.mjs";

function snapshotWithWorld(overrides = {}) {
  const snapshot = {
    sessionId: "planner-fixture",
    frameId: "planner-fixture:semantic",
    viewport: { width: 80, height: 10 },
    cursor: { x: 0, y: 0 },
    capabilities: {
      navigate: { keys: [] },
      tabs: { available: false, keys: [] },
      actions: [],
      dismiss: { keys: [] },
      help: { keys: [] },
      quit: { keys: [] },
    },
    facts: [],
    tables: [],
    regions: [],
    controls: [],
    tabs: [],
    panes: [],
    lists: [],
    statusBars: [],
    popups: [],
    gameElements: [],
    charts: [],
    ...overrides,
  };
  snapshot.world = buildTuiWorld(snapshot, { viewport: snapshot.viewport });
  return snapshot;
}

test("buildPlan resolves panel navigation through TuiWorld tab actions", () => {
  const snapshot = snapshotWithWorld({
    tabs: [{
      id: "tabs",
      role: "tab_bar",
      tabs: [
        { index: 1, label: "Network", active: true, col: 0 },
        { index: 2, label: "Scenarios", active: false, col: 12 },
      ],
      bounds: { startX: 0, endX: 24, startY: 0, endY: 0 },
      confidence: 0.9,
    }],
    capabilities: {
      navigate: { keys: [] },
      tabs: { available: true, keys: ["tab"] },
      actions: [],
      dismiss: { keys: [] },
      help: { keys: [] },
      quit: { keys: [] },
    },
  });

  const plan = buildPlan({
    name: "planner world tabs",
    steps: [{ type: "navigate_panel", target: "Scenarios" }],
  }, snapshot);

  assert.equal(plan.planMeta.usedWorld, true);
  assert.equal(plan.steps[0].key, "2");
});

test("buildPlan prefers TuiWorld actions for dismiss and quit", () => {
  const snapshot = snapshotWithWorld({
    statusBars: [{
      id: "status",
      role: "status_bar",
      keyActions: [{ key: "q", action: "quit" }],
      bounds: { startX: 0, endX: 20, startY: 9, endY: 9 },
      confidence: 0.9,
    }],
    popups: [{
      id: "help",
      role: "popup",
      title: "Help",
      bounds: { startX: 10, endX: 40, startY: 2, endY: 6 },
      confidence: 0.9,
    }],
    capabilities: {
      navigate: { keys: [] },
      tabs: { available: false, keys: [] },
      actions: [],
      dismiss: { keys: ["x"] },
      help: { keys: [] },
      quit: { keys: ["x"] },
    },
  });

  const plan = buildPlan({
    name: "planner world actions",
    steps: [
      { type: "dismiss_overlay" },
      { type: "quit" },
    ],
  }, snapshot);

  assert.equal(plan.steps[0].key, "escape");
  assert.ok(plan.steps[0].targetRef);
  assert.equal(plan.steps[1].key, "q");
  assert.ok(plan.steps[1].actionRef);
});

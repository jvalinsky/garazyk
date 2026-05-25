import test from "node:test";
import assert from "node:assert/strict";
import path from "node:path";

import { buildTuiWorld } from "../world.mjs";
import {
  executeStep,
  normalizeScenarioArgs,
  parseYaml,
  splitArgsScalar,
} from "../corpus/runner.mjs";

function baseSnapshot(overrides = {}) {
  return {
    sessionId: "fixture",
    frameId: "fixture:semantic",
    viewport: { width: 40, height: 10 },
    cols: 40,
    rows: 10,
    cursor: { x: 0, y: 0 },
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
}

function fakeSession(world) {
  const pressed = [];
  return {
    pressed,
    async settle() {},
    semanticSnapshot() {
      return { snapshot: { world } };
    },
    async pressKey(key) {
      pressed.push(key);
    },
  };
}

test("normalizeScenarioArgs handles arrays, comma scalars, quotes, and fixture paths", () => {
  const dir = path.join(process.cwd(), "scripts/mcp-pty/corpus/edge_cases");

  assert.deepEqual(normalizeScenarioArgs(["-u", "1.1.1.1"], dir), [
    "-u",
    "1.1.1.1",
  ]);
  assert.deepEqual(normalizeScenarioArgs("task, tui", dir), ["task", "tui"]);
  assert.deepEqual(splitArgsScalar("--title 'hello world'"), [
    "--title",
    "hello world",
  ]);
  assert.deepEqual(normalizeScenarioArgs("fixtures/long_lines.md", dir), [
    path.join(dir, "fixtures/long_lines.md"),
  ]);
});

test("parseYaml accepts generated inline arrays", () => {
  const parsed = parseYaml(`
name: dashboard
command: deno
args: [task, tui]
steps:
  - type: observe
    label: Observe
`);

  assert.deepEqual(parsed.args, ["task", "tui"]);
  assert.equal(parsed.steps.length, 1);
});

test("executeStep supports world node, action, validation, and primary activation steps", async () => {
  const world = buildTuiWorld(baseSnapshot({
    controls: [{
      role: "button",
      label: "Save",
      bounds: { startX: 2, endX: 7, startY: 2, endY: 2 },
      confidence: 0.95,
    }],
  }));
  const session = fakeSession(world);
  const context = {};

  assert.equal(
    (await executeStep(
      {
        type: "assert_world_node",
        role: "button",
        name: "Save",
      },
      session,
      context,
    )).passed,
    true,
  );

  assert.equal(
    (await executeStep(
      {
        type: "assert_world_action",
        role: "button",
        name: "Save",
        kind: "activate",
        key: "enter",
      },
      session,
      context,
    )).passed,
    true,
  );

  assert.equal(
    (await executeStep(
      {
        type: "assert_world_valid",
        maxSeverity: "warning",
      },
      session,
      context,
    )).passed,
    true,
  );

  assert.equal(
    (await executeStep(
      {
        type: "activate_primary",
        role: "button",
        name: "Save",
      },
      session,
      context,
    )).passed,
    true,
  );
  assert.deepEqual(session.pressed, ["enter"]);
});

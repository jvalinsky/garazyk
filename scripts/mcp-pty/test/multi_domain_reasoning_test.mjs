import test from "node:test";
import assert from "node:assert";

import { detectControls, detectGameElements } from "../semantic.mjs";
import {
  actionsFor,
  buildTuiWorld,
  explain,
  getByRole,
  locator,
  nearest,
  primaryAction,
  related,
  validate,
  worldQuery,
} from "../world.mjs";

function gridFromLines(lines, cols = Math.max(...lines.map((line) => line.length), 1)) {
  return lines.map((line) =>
    Array.from({ length: cols }, (_, x) => ({ char: line[x] || " ", fg: -1, bg: -1 }))
  );
}

function baseSnapshot(overrides = {}) {
  const rows = overrides.rows || 6;
  const cols = overrides.cols || 64;
  return {
    sessionId: "fixture",
    frameId: "fixture:semantic",
    viewport: { width: cols, height: rows },
    cols,
    rows,
    cursor: overrides.cursor || { x: 0, y: 0 },
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

test("TuiWorld answers directional card queries from normalized card nodes", () => {
  const lines = [
    "",
    "  K♠                 A♥",
    "",
    "  Q♥",
    "",
  ];
  const grid = gridFromLines(lines, 32);
  const gameElements = detectGameElements(grid, lines);
  const world = buildTuiWorld(baseSnapshot({
    rows: lines.length,
    cols: 32,
    viewport: { width: 32, height: lines.length },
    cursor: { x: 2, y: 1 },
    gameElements,
  }));

  const king = getByRole(world, "cardFace", { name: "K♠" });
  const below = nearest(world, king.ref, { direction: "below", role: "cardFace" });
  const cardGame = getByRole(world, "cardGame");
  const containedCards = related(world, cardGame.ref, { kind: "contains", role: "cardFace" });

  assert.strictEqual(below?.label, "Q♥");
  assert.ok(containedCards.some((entry) => entry.node.label === "K♠"));
  assert.deepStrictEqual(validate(world).filter((d) => d.severity === "error"), []);
});

test("TuiWorld role lookup is strict by default and explainable when ambiguous", () => {
  const lines = ["  < OK >    < OK >"];
  const controls = detectControls(gridFromLines(lines, 24), lines);
  const world = buildTuiWorld(baseSnapshot({
    rows: 1,
    cols: 24,
    viewport: { width: 24, height: 1 },
    controls,
  }));

  assert.throws(
    () => getByRole(world, "button", { name: "OK" }),
    /Ambiguous TuiWorld role "button"/,
  );
  assert.throws(
    () => locator(world).getByRole("button", { name: "OK" }).resolve(),
    (error) => error.code === "ambiguous" && error.candidates.length === 2,
  );
  assert.strictEqual(getByRole(world, "button", { name: "OK", strict: false }).length, 2);
  assert.strictEqual(worldQuery(world, { op: "find", role: "button" }).nodes.length, 2);
});

test("TuiWorld records selection relationships and invariant diagnostics", () => {
  const world = buildTuiWorld(baseSnapshot({
    rows: 4,
    cols: 32,
    lists: [
      {
        id: "list_container_1",
        role: "list",
        label: "Actions",
        bounds: { startX: 2, endX: 14, startY: 1, endY: 2 },
        confidence: 0.8,
      },
      {
        id: "list_1",
        role: "list_item",
        label: "Run",
        selected: true,
        marker: ">",
        bounds: { startX: 2, endX: 7, startY: 1, endY: 1 },
        confidence: 0.9,
      },
    ],
  }));

  const selected = getByRole(world, "list_item", { name: "Run" });
  const owner = related(world, selected.ref, { kind: "selectedBy", role: "list" });
  const details = explain(world, selected.ref);

  assert.strictEqual(owner.length, 1);
  assert.strictEqual(owner[0].node.label, "Actions");
  assert.ok(details.outgoing.some((edge) => edge.kind === "selectedBy"));

  const orphanWorld = buildTuiWorld(baseSnapshot({
    rows: 2,
    cols: 24,
    lists: [{
      id: "list_0",
      role: "list_item",
      label: "Orphan",
      selected: true,
      bounds: { startX: 0, endX: 6, startY: 0, endY: 0 },
      confidence: 0.9,
    }],
  }));

  assert.ok(orphanWorld.diagnostics.some((d) => d.code === "selected_item_without_collection"));
});

test("TuiWorld exposes node actions and primary action selection", () => {
  const lines = ["  < Save >"];
  const controls = detectControls(gridFromLines(lines, 16), lines);
  const world = buildTuiWorld(baseSnapshot({
    rows: 1,
    cols: 16,
    viewport: { width: 16, height: 1 },
    controls,
  }));

  const button = locator(world).getByRole("button", { name: "Save" }).resolve();
  const actions = actionsFor(world, button.ref);
  const primary = primaryAction(world, button.ref);
  const queried = worldQuery(world, { op: "primaryAction", ref: button.ref });

  assert.strictEqual(actions.length, 1);
  assert.strictEqual(primary.kind, "activate");
  assert.strictEqual(primary.key, "enter");
  assert.strictEqual(queried.action.kind, "activate");
});

test("TuiWorld query returns structured ambiguity errors", () => {
  const lines = ["  < OK >    < OK >"];
  const controls = detectControls(gridFromLines(lines, 24), lines);
  const world = buildTuiWorld(baseSnapshot({
    rows: 1,
    cols: 24,
    viewport: { width: 24, height: 1 },
    controls,
  }));

  assert.throws(
    () => worldQuery(world, { op: "getByRole", role: "button", name: "OK" }),
    (error) => error.code === "ambiguous" && error.candidates.length === 2,
  );

  const nonStrict = worldQuery(world, {
    op: "getByRole",
    role: "button",
    name: "OK",
    strict: false,
  });
  assert.strictEqual(nonStrict.nodes.length, 2);
});

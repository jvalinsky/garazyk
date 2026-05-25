import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { buildTuiWorld, getByRole, nearest, worldQuery } from "../world.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const schemaPath = path.resolve(
  __dirname,
  "..",
  "..",
  "..",
  "packages",
  "tui",
  "testing",
  "world_schema.json",
);
const worldSchema = JSON.parse(fs.readFileSync(schemaPath, "utf8"));

const REQUIRED_RELATIONS = new Set([
  "contains",
  "sameRow",
  "sameColumn",
  "leftOf",
  "rightOf",
  "above",
  "below",
]);

function baseSnapshot(overrides = {}) {
  return {
    sessionId: "fixture",
    frameId: "fixture:contract",
    viewport: { width: 40, height: 12 },
    cols: 40,
    rows: 12,
    cursor: { x: 2, y: 2 },
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

function requiredFields(defName) {
  return worldSchema.$defs[defName].required;
}

function assertHasFields(value, fields, label) {
  for (const field of fields) {
    assert.ok(
      Object.hasOwn(value, field),
      `${label} should include field ${field}`,
    );
  }
}

function assertWorldContract(world) {
  assertHasFields(world, worldSchema.required, "world");
  assertHasFields(world.viewport, worldSchema.properties.viewport.required, "viewport");
  assert.ok(world.nodes.length > 0, "world should contain nodes");
  assert.ok(world.edges.length > 0, "world should contain edges");
  assert.ok(world.sources.length > 0, "world should contain source layers");

  for (const source of world.sources) {
    assertHasFields(source, requiredFields("sourceLayer"), `source ${source.id}`);
  }
  for (const node of world.nodes) {
    assertHasFields(node, requiredFields("node"), `node ${node.ref}`);
    assertHasFields(node.bounds, requiredFields("rect"), `bounds ${node.ref}`);
    assert.ok(node.confidence >= 0 && node.confidence <= 1);
    assert.ok(Array.isArray(node.evidence), "node evidence should be an array");
  }
  for (const edge of world.edges) {
    assertHasFields(edge, requiredFields("edge"), `edge ${edge.id}`);
  }
  for (const action of world.actions) {
    assertHasFields(action, requiredFields("action"), `action ${action.id}`);
  }
  for (const diagnostic of world.diagnostics) {
    assertHasFields(diagnostic, requiredFields("diagnostic"), `diagnostic ${diagnostic.id}`);
  }
}

function contractWorld() {
  return buildTuiWorld(baseSnapshot({
    popups: [{
      role: "popup",
      title: "Editor",
      bounds: { startX: 1, endX: 30, startY: 1, endY: 8 },
      confidence: 0.9,
    }],
    controls: [
      {
        role: "button",
        label: "Save",
        bounds: { startX: 2, endX: 7, startY: 2, endY: 2 },
        confidence: 0.95,
      },
      {
        role: "button",
        label: "Save Draft",
        bounds: { startX: 12, endX: 22, startY: 2, endY: 2 },
        confidence: 0.45,
      },
      {
        role: "button",
        label: "Cancel",
        bounds: { startX: 2, endX: 9, startY: 4, endY: 4 },
        confidence: 0.9,
      },
      {
        role: "button",
        label: "Hidden",
        hidden: true,
        bounds: { startX: 2, endX: 9, startY: 6, endY: 6 },
        confidence: 0.9,
      },
    ],
  }));
}

test("PTY TuiWorld conforms to the shared JSON contract", () => {
  const world = contractWorld();
  assertWorldContract(world);

  const relationNames = new Set(world.edges.map((edge) => edge.kind));
  for (const relation of REQUIRED_RELATIONS) {
    assert.ok(relationNames.has(relation), `missing ${relation} relation`);
  }

  const validation = worldQuery(world, { op: "validate" });
  assert.deepEqual(
    validation.diagnostics.filter((diagnostic) => diagnostic.severity === "error"),
    [],
  );
});

test("PTY TuiWorld query semantics support exact, confidence, and visible filters", () => {
  const world = contractWorld();

  assert.throws(
    () => getByRole(world, "button", { name: "Save" }),
    (error) => error.code === "ambiguous" && error.candidates.length === 2,
  );

  const exact = worldQuery(world, {
    op: "getByRole",
    role: "button",
    name: "Save",
    exact: true,
  });
  assert.equal(exact.nodes.length, 1);
  assert.equal(exact.nodes[0].label, "Save");

  const highConfidence = worldQuery(world, {
    op: "find",
    role: "button",
    name: "Save",
    minConfidence: 0.8,
  });
  assert.deepEqual(highConfidence.nodes.map((node) => node.label), ["Save"]);

  const visible = worldQuery(world, {
    op: "find",
    role: "button",
    visible: true,
  });
  assert.ok(!visible.nodes.some((node) => node.label === "Hidden"));
});

test("PTY TuiWorld nearest uses deterministic tie-breaking", () => {
  const world = buildTuiWorld(baseSnapshot({
    controls: [
      {
        role: "button",
        label: "Source",
        bounds: { startX: 10, endX: 10, startY: 1, endY: 1 },
        confidence: 0.9,
      },
      {
        role: "button",
        label: "Lower Low",
        bounds: { startX: 8, endX: 8, startY: 3, endY: 3 },
        confidence: 0.6,
      },
      {
        role: "button",
        label: "Lower High",
        bounds: { startX: 12, endX: 12, startY: 3, endY: 3 },
        confidence: 0.95,
      },
    ],
  }));

  const source = getByRole(world, "button", { name: "Source" });
  const found = nearest(world, source.ref, { direction: "below", role: "button" });
  assert.equal(found.label, "Lower High");
});

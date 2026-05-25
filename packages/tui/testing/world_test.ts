import { assertEquals, assertThrows } from "@std/assert";
import {
  buildTuiWorldFromElements,
  getWorldByRole,
  validate,
  worldQuery,
} from "./mod.ts";
import type { TuiWorld } from "./mod.ts";

Deno.test("TuiWorld testing helpers preserve strict ambiguity semantics", () => {
  const world = buildTuiWorldFromElements({
    frameId: "fixture",
    viewport: { width: 40, height: 10 },
    elements: [
      {
        role: "button",
        label: "OK",
        bounds: { x: 2, y: 2, width: 4, height: 1 },
        actions: ["enter"],
      },
      {
        role: "button",
        label: "OK",
        bounds: { x: 10, y: 2, width: 4, height: 1 },
        actions: ["enter"],
      },
    ],
  });

  assertThrows(
    () => getWorldByRole(world, "button", { name: "OK" }),
    Error,
    "Ambiguous TuiWorld role",
  );

  const result = worldQuery(world, {
    op: "getByRole",
    role: "button",
    name: "OK",
    strict: false,
  }) as { nodes: Array<unknown> };
  assertEquals(result.nodes.length, 2);
});

Deno.test("TuiWorld testing helpers expose actions and validation", () => {
  const world = buildTuiWorldFromElements({
    frameId: "fixture",
    viewport: { width: 40, height: 10 },
    elements: [{
      role: "button",
      label: "Save",
      bounds: { x: 2, y: 2, width: 6, height: 1 },
      actions: ["enter"],
    }],
  });

  const button = getWorldByRole(world, "button", { name: "Save" });
  const action = worldQuery(world, {
    op: "primaryAction",
    ref: Array.isArray(button) ? button[0].ref : button.ref,
  }) as { action: { kind: string; key?: string } };
  const validation = worldQuery(world, { op: "validate" }) as {
    diagnostics: Array<{ severity: string }>;
  };

  assertEquals(action.action.kind, "activate");
  assertEquals(action.action.key, "enter");
  assertEquals(
    validation.diagnostics.filter((d) => d.severity === "error"),
    [],
  );
});

Deno.test("validate warns when a non-trivial world has zero spatial edges", () => {
  const world: TuiWorld = {
    frameId: "fixture",
    viewport: { width: 40, height: 10 },
    sources: [{ id: "detector:test", kind: "detector", count: 4 }],
    nodes: [
      {
        id: "n1", ref: "g:table:items:0,1", source: "detector:test", sourceIndex: 0,
        domain: "table", role: "table", label: "Items",
        bounds: { x: 1, y: 1, w: 10, h: 5 }, boundsAccuracy: "exact",
        state: {}, confidence: 1, evidence: [],
      },
      {
        id: "n2", ref: "g:table:users:0,2", source: "detector:test", sourceIndex: 1,
        domain: "table", role: "table", label: "Users",
        bounds: { x: 15, y: 1, w: 10, h: 5 }, boundsAccuracy: "exact",
        state: {}, confidence: 1, evidence: [],
      },
      {
        id: "n3", ref: "g:button:save:5,8", source: "detector:test", sourceIndex: 2,
        domain: "form", role: "button", label: "Save",
        bounds: { x: 1, y: 7, w: 6, h: 1 }, boundsAccuracy: "exact",
        state: {}, confidence: 1, evidence: [],
      },
      {
        id: "n4", ref: "g:button:cancel:12,8", source: "detector:test", sourceIndex: 3,
        domain: "form", role: "button", label: "Cancel",
        bounds: { x: 12, y: 7, w: 8, h: 1 }, boundsAccuracy: "exact",
        state: {}, confidence: 1, evidence: [],
      },
    ],
    edges: [],
    actions: [],
    diagnostics: [],
  };
  const diagnostics = validate(world);
  assertEquals(
    diagnostics.filter((d) => d.severity === "error"),
    [],
  );
  const relationWarning = diagnostics.find((d) => d.code === "low_relation_count");
  assertEquals(relationWarning?.severity, "warning");
});

Deno.test("validate does not warn for worlds with 3 or fewer visible nodes", () => {
  const world: TuiWorld = {
    frameId: "fixture",
    viewport: { width: 40, height: 10 },
    sources: [{ id: "detector:test", kind: "detector", count: 3 }],
    nodes: [
      {
        id: "n1", ref: "n1", source: "detector:test", sourceIndex: 0,
        domain: "generic", role: "screen", label: "screen",
        bounds: { x: 0, y: 0, w: 40, h: 10 }, boundsAccuracy: "exact",
        state: {}, confidence: 1, evidence: [],
      },
      {
        id: "n2", ref: "n2", source: "detector:test", sourceIndex: 1,
        domain: "generic", role: "status_bar", label: "Ready",
        bounds: { x: 0, y: 9, w: 40, h: 1 }, boundsAccuracy: "exact",
        state: {}, confidence: 1, evidence: [],
      },
      {
        id: "n3", ref: "n3", source: "detector:test", sourceIndex: 2,
        domain: "generic", role: "cursor", label: "cursor",
        bounds: { x: 0, y: 0, w: 1, h: 1 }, boundsAccuracy: "exact",
        state: {}, confidence: 1, evidence: [],
      },
    ],
    edges: [],
    actions: [],
    diagnostics: [],
  };
  const diagnostics = validate(world);
  assertEquals(diagnostics.filter((d) => d.code === "low_relation_count"), []);
});

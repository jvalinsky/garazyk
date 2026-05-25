import { assertEquals, assertThrows } from "@std/assert";
import {
  buildTuiWorldFromElements,
  getWorldByRole,
  worldQuery,
} from "./mod.ts";

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

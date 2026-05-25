import { assert, assertEquals, assertThrows } from "@std/assert";
import {
  buildTuiWorldFromElements,
  getWorldByRole,
  nearest,
  type TuiWorld,
  worldQuery,
} from "@garazyk/tui/testing";
import { createSession, sessionWorld } from "./session.ts";

const schemaUrl = new URL(
  "../../packages/tui/testing/world_schema.json",
  import.meta.url,
);

const REQUIRED_RELATIONS = new Set([
  "contains",
  "sameRow",
  "sameColumn",
  "leftOf",
  "rightOf",
  "above",
  "below",
]);

function assertHasFields(
  value: Record<string, unknown>,
  fields: string[],
  label: string,
) {
  for (const field of fields) {
    assert(field in value, `${label} should include field ${field}`);
  }
}

async function assertWorldContract(world: TuiWorld) {
  const schema = JSON.parse(await Deno.readTextFile(schemaUrl));
  assertHasFields(
    world as unknown as Record<string, unknown>,
    schema.required,
    "world",
  );
  assertHasFields(
    world.viewport as unknown as Record<string, unknown>,
    schema.properties.viewport.required,
    "viewport",
  );

  for (const source of world.sources) {
    assertHasFields(
      source as unknown as Record<string, unknown>,
      schema.$defs.sourceLayer.required,
      source.id,
    );
  }
  for (const node of world.nodes) {
    assertHasFields(
      node as unknown as Record<string, unknown>,
      schema.$defs.node.required,
      node.ref,
    );
    assertHasFields(
      node.bounds as unknown as Record<string, unknown>,
      schema.$defs.rect.required,
      `${node.ref} bounds`,
    );
    assert(node.confidence >= 0 && node.confidence <= 1);
    assert(Array.isArray(node.evidence));
  }
  for (const edge of world.edges) {
    assertHasFields(
      edge as unknown as Record<string, unknown>,
      schema.$defs.edge.required,
      edge.id,
    );
  }
  for (const action of world.actions) {
    assertHasFields(
      action as unknown as Record<string, unknown>,
      schema.$defs.action.required,
      action.id,
    );
  }
  for (const diagnostic of world.diagnostics) {
    assertHasFields(
      diagnostic as unknown as Record<string, unknown>,
      schema.$defs.diagnostic.required,
      diagnostic.id,
    );
  }
}

function contractWorld(): TuiWorld {
  return buildTuiWorldFromElements({
    frameId: "dashboard:contract",
    viewport: { width: 40, height: 12 },
    sourceId: "metadata:dashboard",
    elements: [
      {
        role: "dialog",
        label: "Editor",
        bounds: { x: 1, y: 1, width: 30, height: 8 },
      },
      {
        role: "button",
        label: "Save",
        bounds: { x: 2, y: 2, width: 6, height: 1 },
        actions: ["enter"],
        confidence: 0.95,
      },
      {
        role: "button",
        label: "Save Draft",
        bounds: { x: 12, y: 2, width: 11, height: 1 },
        actions: ["enter"],
        confidence: 0.45,
      },
      {
        role: "button",
        label: "Cancel",
        bounds: { x: 2, y: 4, width: 8, height: 1 },
        actions: ["escape"],
      },
      {
        role: "button",
        label: "Hidden",
        bounds: { x: 2, y: 6, width: 8, height: 1 },
        state: { hidden: true },
        actions: ["enter"],
      },
    ],
  });
}

Deno.test("dashboard TuiWorld conforms to the shared JSON contract", async () => {
  const world = contractWorld();
  await assertWorldContract(world);

  const relationNames = new Set(world.edges.map((edge) => edge.kind));
  for (const relation of REQUIRED_RELATIONS) {
    assert(relationNames.has(relation), `missing ${relation} relation`);
  }

  const validation = worldQuery(world, { op: "validate" }) as {
    diagnostics: Array<{ severity: string }>;
  };
  assertEquals(
    validation.diagnostics.filter((diagnostic) =>
      diagnostic.severity === "error"
    ),
    [],
  );
});

Deno.test("dashboard adapter output follows the shared world contract", async () => {
  const world = sessionWorld(createSession());
  await assertWorldContract(world);

  const panels = worldQuery(world, {
    op: "find",
    role: "panel",
    visible: true,
  }) as { nodes: Array<{ ref: string }> };
  assert(panels.nodes.length > 0);
});

Deno.test("dashboard TuiWorld query semantics support exact, confidence, and visible filters", () => {
  const world = contractWorld();

  assertThrows(
    () => getWorldByRole(world, "button", { name: "Save" }),
    Error,
    "Ambiguous TuiWorld role",
  );

  const exact = worldQuery(world, {
    op: "getByRole",
    role: "button",
    name: "Save",
    exact: true,
  }) as { nodes: Array<{ label?: string }> };
  assertEquals(exact.nodes.map((node) => node.label), ["Save"]);

  const highConfidence = worldQuery(world, {
    op: "find",
    role: "button",
    name: "Save",
    minConfidence: 0.8,
  }) as { nodes: Array<{ label?: string }> };
  assertEquals(highConfidence.nodes.map((node) => node.label), ["Save"]);

  const visible = worldQuery(world, {
    op: "find",
    role: "button",
    visible: true,
  }) as { nodes: Array<{ label?: string }> };
  assert(!visible.nodes.some((node) => node.label === "Hidden"));
});

Deno.test("dashboard TuiWorld nearest uses deterministic tie-breaking", () => {
  const world = buildTuiWorldFromElements({
    frameId: "dashboard:nearest",
    viewport: { width: 30, height: 8 },
    elements: [
      {
        role: "button",
        label: "Source",
        bounds: { x: 10, y: 1, width: 1, height: 1 },
        confidence: 0.9,
      },
      {
        role: "button",
        label: "Lower Low",
        bounds: { x: 8, y: 3, width: 1, height: 1 },
        confidence: 0.6,
      },
      {
        role: "button",
        label: "Lower High",
        bounds: { x: 12, y: 3, width: 1, height: 1 },
        confidence: 0.95,
      },
    ],
  });

  const source = getWorldByRole(world, "button", { name: "Source" });
  assert(!Array.isArray(source));
  const found = nearest(world, source.ref, {
    direction: "below",
    role: "button",
  });
  assertEquals(found?.label, "Lower High");
});

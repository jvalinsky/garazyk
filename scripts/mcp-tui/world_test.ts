import { assert, assertEquals } from "@std/assert";
import { worldQuery } from "@garazyk/tui/testing";
import { createSession, sessionWorld } from "./session.ts";

Deno.test("MCP TUI world: dashboard metadata converts to TuiWorld", () => {
  const session = createSession();
  const world = sessionWorld(session);

  assertEquals(world.viewport.width, 120);
  assert(world.nodes.some((node) => node.role === "screen"));
  assert(
    world.nodes.some((node) =>
      node.role === "panel" && node.ref === "panel.network"
    ),
  );
  assert(world.edges.some((edge) => edge.kind === "contains"));
});

Deno.test("MCP TUI world: query API finds panels and validates graph", () => {
  const session = createSession();
  const world = sessionWorld(session);

  const panels = worldQuery(world, {
    op: "find",
    role: "panel",
    visible: true,
  }) as { nodes: Array<{ ref: string }> };
  const network = worldQuery(world, {
    op: "getByRole",
    role: "panel",
    name: "Network",
  }) as { nodes: Array<{ ref: string }> };
  const validation = worldQuery(world, { op: "validate" }) as {
    diagnostics: Array<{ severity: string }>;
  };

  assertEquals(panels.nodes.length, 4);
  assertEquals(network.nodes[0].ref, "panel.network");
  assertEquals(
    validation.diagnostics.filter((d) => d.severity === "error"),
    [],
  );
});

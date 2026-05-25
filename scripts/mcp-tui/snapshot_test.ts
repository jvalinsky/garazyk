import { assert, assertStringIncludes, assertThrows } from "@std/assert";
import { createSession, sessionSnapshot } from "./session.ts";

Deno.test("MCP TUI snapshot: full snapshot includes every dashboard panel", () => {
  const session = createSession();
  const snapshot = sessionSnapshot(session);

  for (
    const panel of [
      "panel.network",
      "panel.scenarios",
      "panel.run",
      "panel.history",
    ]
  ) {
    assertStringIncludes(snapshot, `ref=${panel}`);
  }
});

Deno.test("MCP TUI snapshot: panel scope returns only the requested panel", () => {
  const session = createSession();
  const snapshot = sessionSnapshot(session, { panel: "network" });

  assertStringIncludes(snapshot, "ref=panel.network");
  assert(
    !snapshot.includes("ref=panel.scenarios"),
    "network scope should exclude scenarios panel",
  );
  assert(
    !snapshot.includes("ref=panel.run"),
    "network scope should exclude run panel",
  );
  assert(
    !snapshot.includes("ref=panel.history"),
    "network scope should exclude history panel",
  );
});

Deno.test("MCP TUI snapshot: full panel refs remain valid", () => {
  const session = createSession();

  assertStringIncludes(
    sessionSnapshot(session, { panel: "panel.network" }),
    "ref=panel.network",
  );
});

Deno.test("MCP TUI snapshot: unknown panel scope errors", () => {
  const session = createSession();

  assertThrows(
    () => sessionSnapshot(session, { panel: "missing" }),
    Error,
    "Panel scope not found: missing",
  );
});

/**
 * Unit tests for docker_health.ts — waitForHttp using ephemeral local servers.
 *
 * waitForService/waitForServiceCLI require Docker; they are tested via a
 * lightweight subprocess smoke test only.
 *
 * @module docker_health_test
 */

import { assertEquals } from "@std/assert";
import { waitForHttp } from "./docker_health.ts";

// ---------------------------------------------------------------------------
// waitForHttp
// ---------------------------------------------------------------------------

Deno.test({ name: "waitForHttp: returns true when server responds 200 on first attempt", sanitizeResources: false }, async () => {
  const server = Deno.serve({ port: 0, hostname: "127.0.0.1" }, () => new Response("ok"));
  const { port } = server.addr as Deno.NetAddr;
  try {
    const ok = await waitForHttp(`http://127.0.0.1:${port}/health`, "TEST", 5);
    assertEquals(ok, true);
  } finally {
    await server.shutdown();
  }
});

Deno.test({ name: "waitForHttp: returns true after initial non-ok responses", sanitizeResources: false }, async () => {
  let calls = 0;
  const server = Deno.serve({ port: 0, hostname: "127.0.0.1" }, () => {
    calls++;
    return calls < 3
      ? new Response("not ready", { status: 503 })
      : new Response("ok", { status: 200 });
  });
  const { port } = server.addr as Deno.NetAddr;
  try {
    const ok = await waitForHttp(`http://127.0.0.1:${port}/health`, "TEST", 10);
    assertEquals(ok, true);
    assertEquals(calls >= 3, true);
  } finally {
    await server.shutdown();
  }
});

Deno.test(
  "waitForHttp: returns false when timeout expires without 200",
  { sanitizeOps: false, sanitizeResources: false },
  async () => {
    const server = Deno.serve(
      { port: 0, hostname: "127.0.0.1" },
      () => new Response("not ready", { status: 503 }),
    );
    const { port } = server.addr as Deno.NetAddr;
    try {
      const start = Date.now();
      const ok = await waitForHttp(`http://127.0.0.1:${port}/health`, "TEST", 1);
      assertEquals(ok, false);
      // Should resolve within a few seconds of the 1s deadline
      assertEquals(Date.now() - start < 4000, true);
    } finally {
      await server.shutdown();
    }
  },
);

Deno.test({ name: "waitForHttp: forwards custom headers to the server", sanitizeResources: false }, async () => {
  let receivedHeader = "";
  const server = Deno.serve({ port: 0, hostname: "127.0.0.1" }, (req) => {
    receivedHeader = req.headers.get("x-test-token") ?? "";
    return new Response("ok", { status: 200 });
  });
  const { port } = server.addr as Deno.NetAddr;
  try {
    await waitForHttp(
      `http://127.0.0.1:${port}/health`,
      "TEST",
      5,
      { "x-test-token": "secret-abc" },
    );
    assertEquals(receivedHeader, "secret-abc");
  } finally {
    await server.shutdown();
  }
});

Deno.test("waitForHttp: returns false on network error without throwing", async () => {
  // Port 1 is almost certainly not listening
  const ok = await waitForHttp("http://127.0.0.1:1/health", "TEST", 1);
  assertEquals(ok, false);
});

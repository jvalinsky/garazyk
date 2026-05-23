import { assertEquals, assertExists } from "@std/assert";
import {
  type MockTwilioServer,
  startMockTwilioServer,
  stopMockTwilioServer,
} from "./mock_twilio.ts";

Deno.test("MockTwilioServer end-to-end", async (t) => {
  let server: MockTwilioServer;

  await t.step(
    "startMockTwilioServer spawns process and waits for health",
    async () => {
      server = await startMockTwilioServer();
      assertExists(server);
      assertEquals(server.url.startsWith("http://127.0.0.1:"), true);
      const healthy = await server.getHealth();
      assertEquals(healthy, true);
    },
  );

  await t.step("getHealth returns true when server is running", async () => {
    const healthy = await server!.getHealth();
    assertEquals(healthy, true);
  });

  await t.step("setCode stores a verification code on the server", async () => {
    await server!.setCode("+1555client", "123456");
    const state = await server!.getState();
    assertEquals(state.store["+1555client"].code, "123456");
  });

  await t.step("setAlwaysApprove updates always-approve codes", async () => {
    await server!.setAlwaysApprove(["testcode"]);
    const state = await server!.getState();
    assertEquals(state.alwaysApproveCodes, ["testcode"]);
  });

  await t.step("getState returns store and alwaysApproveCodes", async () => {
    const state = await server!.getState();
    assertExists(state.store);
    assertExists(state.alwaysApproveCodes);
  });

  await t.step("reset clears all state on the server", async () => {
    await server!.setCode("+1555resetme", "987654");
    await server!.reset();
    const state = await server!.getState();
    assertEquals(state.store["+1555resetme"], undefined);
  });

  await t.step("stopMockTwilioServer kills the subprocess", async () => {
    stopMockTwilioServer(server!);
    await new Promise((r) => setTimeout(r, 500));
    const healthy = await server!.getHealth();
    assertEquals(healthy, false);
  });
});

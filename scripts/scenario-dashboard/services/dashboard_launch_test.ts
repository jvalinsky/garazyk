import { assertEquals } from "@std/assert";
import { isAgentLaunchFromEnv } from "./dashboard_launch.ts";

Deno.test("isAgentLaunchFromEnv: false by default", () => {
  Deno.env.delete("GARAZYK_DASHBOARD_AGENT_LAUNCH");
  Deno.env.delete("CURSOR_AGENT");
  assertEquals(isAgentLaunchFromEnv(), false);
});

Deno.test("isAgentLaunchFromEnv: true for GARAZYK_DASHBOARD_AGENT_LAUNCH=1", () => {
  Deno.env.set("GARAZYK_DASHBOARD_AGENT_LAUNCH", "1");
  try {
    assertEquals(isAgentLaunchFromEnv(), true);
  } finally {
    Deno.env.delete("GARAZYK_DASHBOARD_AGENT_LAUNCH");
  }
});

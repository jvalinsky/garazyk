import { assertEquals } from "@std/assert";
import { readAgentLaunchFromUrl } from "./client_launch.ts";

Deno.test("readAgentLaunchFromUrl: detects agentLaunch=1", () => {
  assertEquals(readAgentLaunchFromUrl("?agentLaunch=1"), true);
});

Deno.test("readAgentLaunchFromUrl: ignores missing param", () => {
  assertEquals(readAgentLaunchFromUrl(""), false);
});

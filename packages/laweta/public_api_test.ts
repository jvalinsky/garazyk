import { assert, assertEquals } from "@std/assert";
import {
  buildDockerRunnerArgs,
  ContainerEventWatcher,
  DockerApiClient,
  waitForHttp,
} from "./mod.ts";
import { neededPorts, serviceUrl } from "./atproto_runtime.ts";

Deno.test("laweta root exposes generic Docker primitives", () => {
  assertEquals(typeof DockerApiClient, "function");
  assertEquals(typeof ContainerEventWatcher.create, "function");
  assertEquals(typeof waitForHttp, "function");
  assert(
    buildDockerRunnerArgs({
      repoRoot: "/repo",
      composeProject: "garazyk-test",
      networkName: "garazyk-test_default",
      internalUrls: {},
      capabilities: new Set(),
      scenarioPath: "/repo/scenario.ts",
      timeoutSeconds: 30,
    }).includes("garazyk-test_default"),
  );
});

Deno.test("laweta ATProto runtime helpers are off the root export", () => {
  assertEquals(serviceUrl("pds"), "http://127.0.0.1:2583");
  assert(neededPorts({ withPds2: true }).includes(2587));
});

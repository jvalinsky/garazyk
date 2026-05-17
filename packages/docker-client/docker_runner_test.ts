import { assertEquals } from "jsr:@std/assert";
import {
  buildDockerRunnerArgs,
  DOCKER_RUNNER_TIMEOUT_EXIT_CODE,
} from "./docker_runner.ts";

Deno.test("buildDockerRunnerArgs omits invalid Deno timeout flag", () => {
  const args = buildDockerRunnerArgs({
    repoRoot: "/repo",
    composeProject: "garazyk",
    internalUrls: { pds: "http://local-pds:2583" },
    capabilities: new Set(["createAccount"]),
    scenarioPath: "/repo/scripts/scenarios/scenarios/01_smoke.ts",
    timeoutSeconds: 30,
    containerName: "scenario-runner-test",
  });

  assertEquals(args.includes("--timeout=30000"), false);
  assertEquals(args.includes("scenario-runner-test"), true);
  assertEquals(args.slice(-3), [
    "run",
    "-A",
    "/workspace/scripts/scenarios/scenarios/01_smoke.ts",
  ]);
  assertEquals(args.includes("PDS_URL=http://local-pds:2583"), true);
});

Deno.test("Docker runner timeout exit code follows conventional timeout status", () => {
  assertEquals(DOCKER_RUNNER_TIMEOUT_EXIT_CODE, 124);
});

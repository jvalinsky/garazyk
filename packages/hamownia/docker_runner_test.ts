import { assertEquals } from "@std/assert";
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
    containerName: "hamownia-test",
    // Generic mapper: pds → PDS_URL (uppercase + _URL)
    roleEnvMapper: (role) => role.toUpperCase() + "_URL",
  });

  assertEquals(args.includes("--timeout=30000"), false);
  assertEquals(args.includes("hamownia-test"), true);
  assertEquals(args.slice(-3), [
    "run",
    "-A",
    "/workspace/scripts/scenarios/scenarios/01_smoke.ts",
  ]);
  assertEquals(args.includes("PDS_URL=http://local-pds:2583"), true);
});

Deno.test("buildDockerRunnerArgs uses generic fallback when no mapper provided", () => {
  const args = buildDockerRunnerArgs({
    repoRoot: "/repo",
    composeProject: "garazyk",
    internalUrls: { appview: "http://local-appview:2584" },
    capabilities: new Set(),
    scenarioPath: "/repo/scenarios/test.ts",
    timeoutSeconds: 30,
  });

  // Generic fallback: appview → APPVIEW_URL
  assertEquals(args.includes("APPVIEW_URL=http://local-appview:2584"), true);
});

Deno.test("Docker runner timeout exit code follows conventional timeout status", () => {
  assertEquals(DOCKER_RUNNER_TIMEOUT_EXIT_CODE, 124);
});

import { assertEquals, assertStringIncludes, assertThrows } from "@std/assert";
import {
  buildDockerRunnerArgs,
  DOCKER_RUNNER_TIMEOUT_EXIT_CODE,
  runScenarioInDocker,
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

Deno.test("buildDockerRunnerArgs rejects scenario paths outside repo root", () => {
  assertThrows(
    () =>
      buildDockerRunnerArgs({
        repoRoot: "/repo",
        composeProject: "garazyk",
        internalUrls: {},
        capabilities: new Set(),
        scenarioPath: "/tmp/escape.ts",
        timeoutSeconds: 30,
      }),
    Error,
    "Scenario path escapes repo root",
  );
});

Deno.test("runScenarioInDocker returns 124 and force-removes container on timeout", async () => {
  const dir = await Deno.makeTempDir({ prefix: "hamownia-fake-docker-" });
  const dockerPath = `${dir}/docker`;
  const logPath = `${dir}/docker.log`;
  const oldPath = Deno.env.get("PATH");

  await Deno.writeTextFile(
    dockerPath,
    `#!/bin/sh
printf '%s\\n' "$*" >> "${logPath}"
if [ "$1" = "run" ]; then
  sleep 10
fi
exit 0
`,
  );
  await Deno.chmod(dockerPath, 0o755);

  try {
    Deno.env.set("PATH", oldPath ? `${dir}:${oldPath}` : dir);
    const code = await runScenarioInDocker({
      repoRoot: "/repo",
      composeProject: "garazyk",
      internalUrls: {},
      capabilities: new Set(),
      scenarioPath: "/repo/scenario.ts",
      timeoutSeconds: 0.01,
      containerName: "hamownia-timeout-test",
    });

    assertEquals(code, DOCKER_RUNNER_TIMEOUT_EXIT_CODE);
    const calls = await Deno.readTextFile(logPath);
    assertStringIncludes(calls, "hamownia-timeout-test");
    assertStringIncludes(calls, "rm -f hamownia-timeout-test");
  } finally {
    if (oldPath === undefined) {
      Deno.env.delete("PATH");
    } else {
      Deno.env.set("PATH", oldPath);
    }
    await Deno.remove(dir, { recursive: true });
  }
});

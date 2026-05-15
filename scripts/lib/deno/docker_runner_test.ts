import { assert, assertEquals, assertRejects } from "jsr:@std/assert";
import {
  type CommandInvocation,
  type CommandRunner,
  runScenarioInDocker,
} from "./docker_runner.ts";

function baseOptions(commandRunner: CommandRunner) {
  return {
    repoRoot: "/repo",
    runId: "run-1",
    composeProject: "garazyk-e2e-run-1",
    networkName: "garazyk-e2e-run-1_local_net",
    internalUrls: { pds: "http://local-pds:2583" },
    capabilities: new Set(["pds"]),
    scenarioId: "01",
    scenarioPath: "/repo/scripts/scenarios/scenarios/01_account.ts",
    timeoutSeconds: 10,
    commandRunner,
  };
}

Deno.test("docker runner command omits invalid deno --timeout and uses --no-prompt", async () => {
  const invocations: CommandInvocation[] = [];
  const result = await runScenarioInDocker(baseOptions(async (invocation) => {
    invocations.push(invocation);
    return { code: 0 };
  }));

  assertEquals(result.code, 0);
  assertEquals(invocations.length, 1);
  const args = invocations[0].args;
  assertEquals(args.includes("--no-prompt"), true);
  assertEquals(args.some((arg) => arg.startsWith("--timeout=")), false);
});

Deno.test("docker runner timeout aborts and removes named container", async () => {
  const invocations: CommandInvocation[] = [];
  const result = await runScenarioInDocker({
    ...baseOptions((invocation) => {
      invocations.push(invocation);
      if (invocation.args[0] === "rm") return Promise.resolve({ code: 0 });
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => resolve({ code: 0 }), 1000);
        invocation.signal?.addEventListener("abort", () => {
          clearTimeout(timer);
          reject(new DOMException("aborted", "AbortError"));
        });
      });
    }),
    timeoutSeconds: 0.01,
  });

  assertEquals(result.timedOut, true);
  assertEquals(result.code, 124);
  assert(result.message?.includes("timed out"));
  assertEquals(invocations.length, 2);
  assertEquals(invocations[1].args[0], "rm");
  assertEquals(invocations[1].args[1], "-f");
});

Deno.test("docker runner non-zero exit code is returned", async () => {
  const result = await runScenarioInDocker(baseOptions(async () => ({ code: 7 })));

  assertEquals(result.code, 7);
  assertEquals(result.timedOut, false);
});

Deno.test("docker runner rejects scenario paths outside repo root", async () => {
  await assertRejects(
    () =>
      runScenarioInDocker({
        ...baseOptions(async () => ({ code: 0 })),
        scenarioPath: "/etc/passwd",
      }),
    Error,
    "escapes repo root",
  );
});

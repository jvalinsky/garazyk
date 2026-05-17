/** Scenario execution — host runner and Docker runner modes with timeout support. @module scenario_runner */
import type { ScenarioInfo } from "./scenario_metadata.ts";
import type { RunnerArgs } from "./run_scenarios_types.ts";
import type { Topology } from "@garazyk/atproto-topology";
import { ScenarioResult } from "./runner.ts";
import { runScenarioInDocker } from "@garazyk/docker-client";
import { withSpan } from "./otel.ts";

/**
 * Race a promise against a timeout
 * @typeParam T - The expected result type
 * @param promise - The promise to race against the timeout
 * @param timeoutSeconds - Maximum wait time in seconds
 * @param label - Description for the timeout error message
 * @returns The resolved value
 * @throws Error if the timeout elapses before the promise resolves
 */
export async function withTimeout<T>(
  promise: Promise<T>,
  timeoutSeconds: number,
  label: string,
): Promise<T> {
  let timeoutId: number | undefined;
  const timeout = new Promise<never>((_resolve, reject) => {
    timeoutId = setTimeout(
      () => reject(new Error(`${label} timed out after ${timeoutSeconds}s`)),
      timeoutSeconds * 1000,
    );
  });
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    if (timeoutId !== undefined) clearTimeout(timeoutId);
  }
}

/**
 * Run a scenario in the configured execution mode
 * @param scenario - The scenario to execute
 * @param timeoutSeconds - Maximum allowed runtime in seconds
 * @param args - Runner arguments
 * @param topology - The resolved topology
 * @param repoRoot - The repository root path
 * @param composeProject - The Docker Compose project name
 * @returns The completed scenario result
 * @throws {Error} If the scenario run() export is missing or execution fails fatally.
 */
export async function runScenario(
  scenario: ScenarioInfo,
  timeoutSeconds: number,
  args: RunnerArgs,
  topology: Topology,
  repoRoot: string,
  composeProject: string,
): Promise<ScenarioResult> {
  // Docker runner mode: execute the scenario inside a container
  if (args.runner === "docker") {
    try {
      const exitCode = await runScenarioInDocker({
        repoRoot,
        composeProject,
        networkName: topology.manifest
          ? `${composeProject}_${topology.manifest.networkName}`
          : `${composeProject}_local_net`,
        internalUrls: topology.internalUrls,
        dockerRunnerEnv: topology.manifest?.env?.dockerRunner,
        capabilities: topology.capabilities,
        scenarioPath: scenario.path,
        timeoutSeconds,
        env: {
          ...(topology.manifest?.scenarioEnv || {}),
          ...(topology.manifest?.env?.scenario || {}),
          ATPROTO_CLIENT_FLOW: args.clientFlow,
          ATPROTO_ALLOW_HYBRID_NETWORK: args.allowHybridNetwork ? "1" : "0",
          ...(args.webClient ? { ATPROTO_WEB_CLIENT: args.webClient } : {}),
          ...(args.topology ? { ATPROTO_TOPOLOGY: args.topology } : {}),
        },
      });
      const result = new ScenarioResult(scenario.name);
      result.start();
      if (exitCode === 0) {
        result.stepPassed(`Scenario ${scenario.id} (docker)`, `exit=${exitCode}`);
      } else {
        result.stepFailed(`Scenario ${scenario.id} (docker)`, `exit=${exitCode}`);
      }
      result.finish();
      return result;
    } catch (exc) {
      const result = new ScenarioResult(scenario.name);
      result.start();
      result.stepFailed(
        `Scenario ${scenario.id} docker runner`,
        exc instanceof Error ? exc.message : String(exc),
      );
      result.finish();
      return result;
    }
  }

  // Host runner mode (default)
  try {
    Deno.env.set("ATPROTO_CLIENT_FLOW", args.clientFlow);
    Deno.env.set("ATPROTO_ALLOW_HYBRID_NETWORK", args.allowHybridNetwork ? "1" : "0");
    Deno.env.set(
      "ATPROTO_BLOCKED_PUBLIC_HOSTS",
      args.allowHybridNetwork ? "" : "bsky.app,api.bsky.app,bsky.network,plc.directory",
    );
    if (args.webClient) Deno.env.set("ATPROTO_WEB_CLIENT", args.webClient);
    if (args.topology) Deno.env.set("ATPROTO_TOPOLOGY", args.topology);
    if (topology.manifest) {
      const runnerEnv = topology.manifest.env?.hostRunner || topology.manifest.scenarioEnv;
      const scenarioEnv = topology.manifest.env?.scenario || {};
      for (const [key, value] of Object.entries({ ...runnerEnv, ...scenarioEnv })) {
        Deno.env.set(key, String(value));
      }
    }
    const { resetCharacters } = await import("./config.ts");
    resetCharacters();
    const module = await import(`file://${scenario.path}?run=${Date.now()}`);
    if (typeof module.run !== "function") {
      const result = new ScenarioResult(scenario.name);
      result.start();
      result.stepFailed(`Scenario ${scenario.id} entry point`, "No run() export defined");
      result.finish();
      return result;
    }
    const result = await withTimeout<ScenarioResult>(
      module.run(),
      timeoutSeconds,
      `Scenario ${scenario.id}`,
    );
    if (!result.startedAt) result.startedAt = Date.now();
    if (!result.finishedAt) result.finishedAt = Date.now();
    return result;
  } catch (exc) {
    const result = new ScenarioResult(scenario.name);
    result.start();
    result.stepFailed(
      `Scenario ${scenario.id} execution`,
      exc instanceof Error ? exc.message : String(exc),
    );
    result.finish();
    return result;
  }
}

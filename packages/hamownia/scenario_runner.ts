/** Scenario execution — host runner and Docker runner modes with timeout support. @module scenario_runner */
import { dirname, fromFileUrl, join, toFileUrl } from "@std/path";
import type { ScenarioInfo } from "./scenario_metadata.ts";
import type { RunnerArgs } from "./run_scenarios_types.ts";
import type { Topology, TopologyManifestV2 } from "@garazyk/schemat";
import { roleEnvKey } from "@garazyk/schemat";
import { type ScenarioReport, ScenarioResult } from "./runner.ts";
import {
  type DockerRunnerOptions,
  runScenarioInDocker,
} from "./docker_runner.ts";

const HOST_CHILD_GRACE_MS = 2_000;

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
      const exitCode = await runScenarioInDocker(
        buildDockerScenarioRunnerOptions(
          scenario,
          timeoutSeconds,
          args,
          topology,
          repoRoot,
          composeProject,
        ),
      );
      const result = new ScenarioResult(scenario.name);
      result.start();
      if (exitCode === 0) {
        result.stepPassed(
          `Scenario ${scenario.id} (docker)`,
          `exit=${exitCode}`,
        );
      } else {
        result.stepFailed(
          `Scenario ${scenario.id} (docker)`,
          `exit=${exitCode}`,
        );
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

  return await runHostScenarioInChild(scenario, timeoutSeconds, args, topology);
}

/** Build Docker-runner options for a scenario without launching Docker. */
export function buildDockerScenarioRunnerOptions(
  scenario: ScenarioInfo,
  timeoutSeconds: number,
  args: RunnerArgs,
  topology: Topology,
  repoRoot: string,
  composeProject: string,
): DockerRunnerOptions {
  const topologyName = args.topology ?? topology.preset?.name;
  return {
    repoRoot,
    composeProject,
    networkName: topology.manifest
      ? `${composeProject}_${topology.manifest.networkName}`
      : `${composeProject}_local_net`,
    internalUrls: topology.internalUrls,
    dockerRunnerEnv: (topology.manifest as TopologyManifestV2 | undefined)?.env
      ?.dockerRunner,
    capabilities: topology.capabilities,
    scenarioPath: scenario.path,
    timeoutSeconds,
    roleEnvMapper: roleEnvKey,
    env: {
      ...(topology.manifest?.scenarioEnv || {}),
      ...((topology.manifest as TopologyManifestV2 | undefined)?.env
        ?.scenario || {}),
      ATPROTO_CLIENT_FLOW: args.clientFlow,
      ATPROTO_ALLOW_HYBRID_NETWORK: args.allowHybridNetwork ? "1" : "0",
      ...(args.webClient ? { ATPROTO_WEB_CLIENT: args.webClient } : {}),
      ...(topologyName ? { ATPROTO_TOPOLOGY: topologyName } : {}),
    },
  };
}

function buildHostScenarioEnv(
  args: RunnerArgs,
  topology: Topology,
): Record<string, string> {
  const env: Record<string, string> = {
    ATPROTO_CLIENT_FLOW: args.clientFlow,
    ATPROTO_ALLOW_HYBRID_NETWORK: args.allowHybridNetwork ? "1" : "0",
    ATPROTO_BLOCKED_PUBLIC_HOSTS: args.allowHybridNetwork
      ? ""
      : "bsky.app,api.bsky.app,bsky.network,plc.directory",
  };
  if (args.webClient) env.ATPROTO_WEB_CLIENT = args.webClient;
  const topologyName = args.topology ?? topology.preset?.name;
  if (topologyName) env.ATPROTO_TOPOLOGY = topologyName;
  if (topology.manifest) {
    const manifestV2 = topology.manifest as TopologyManifestV2;
    const runnerEnv = manifestV2.env?.hostRunner ||
      topology.manifest.scenarioEnv;
    const scenarioEnv = manifestV2.env?.scenario || {};
    for (
      const [key, value] of Object.entries({ ...runnerEnv, ...scenarioEnv })
    ) {
      env[key] = String(value);
    }
  }
  return env;
}

async function runHostScenarioInChild(
  scenario: ScenarioInfo,
  timeoutSeconds: number,
  args: RunnerArgs,
  topology: Topology,
): Promise<ScenarioResult> {
  const tempDir = await Deno.makeTempDir({ prefix: "garazyk-host-scenario-" });
  const outputPath = `${tempDir}/report.json`;
  const childRunnerPath = fromFileUrl(
    new URL("./host_child_runner.ts", import.meta.url),
  );

  // Write a temporary bootstrap script that statically imports the host runner and
  // scenario. This eliminates dynamic runtime import warnings during package publication.
  const bootstrapPath = join(tempDir, "bootstrap.ts");
  const bootstrapContent =
    `// Generated bootstrap for isolated scenario execution
import { runChildWithModule } from "${toFileUrl(childRunnerPath).href}";
import * as scenarioModule from "${toFileUrl(scenario.path).href}";
const exitCode = await runChildWithModule(scenarioModule);
Deno.exit(exitCode);
`;
  await Deno.writeTextFile(bootstrapPath, bootstrapContent);

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutSeconds * 1000);

  const command = new Deno.Command(Deno.execPath(), {
    args: [
      "run",
      "-A",
      "--config",
      join(dirname(childRunnerPath), "deno.json"),
      bootstrapPath,
      "--scenario",
      scenario.path,
      "--output",
      outputPath,
      "--scenario-id",
      scenario.id,
      "--scenario-name",
      scenario.name,
    ],
    env: buildHostScenarioEnv(args, topology),
    stdout: "inherit",
    stderr: "inherit",
  });

  const child = command.spawn();
  const abortHandler = () => {
    try {
      child.kill("SIGTERM");
    } catch {
      // already dead
    }
  };
  controller.signal.addEventListener("abort", abortHandler);

  try {
    const status = await child.status;
    clearTimeout(timeoutId);
    if (!status.success && controller.signal.aborted) {
      const result = new ScenarioResult(scenario.name);
      result.start();
      result.stepFailed(
        `Scenario ${scenario.id} timeout`,
        `Timed out after ${timeoutSeconds}s; host child process was terminated`,
      );
      result.finish();
      return result;
    }

    try {
      const report = JSON.parse(
        await Deno.readTextFile(outputPath),
      ) as ScenarioReport;
      return ScenarioResult.fromReport(report);
    } catch (exc) {
      const result = new ScenarioResult(scenario.name);
      result.start();
      result.stepFailed(
        `Scenario ${scenario.id} report`,
        `Host child exited but did not emit a parseable report: ${
          exc instanceof Error ? exc.message : String(exc)
        }`,
      );
      result.finish();
      return result;
    }
  } finally {
    controller.signal.removeEventListener("abort", abortHandler);
    await Deno.remove(tempDir, { recursive: true }).catch(() => undefined);
  }
}

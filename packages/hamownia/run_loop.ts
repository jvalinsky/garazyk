/**
 * Scenario execution loop with crash detection, progress tracking,
 * and OTel stats sampling.
 *
 * @module run_loop
 */

import { bold, red, yellow } from "@std/fmt/colors";
import { isOtelEnabled, withSpan } from "./otel.ts";
import {
  ContainerEventWatcher,
  type WatcherEvent,
} from "@garazyk/laweta";
import { ContainerStatsSampler } from "@garazyk/laweta";
import { createDockerClient } from "@garazyk/laweta";
import { formatBytes } from "./format.ts";
import { DurationCache, ProgressBar } from "./progress.ts";
import { runScenario } from "./scenario_runner.ts";
import { waitForHttp } from "@garazyk/laweta";
import type { ScenarioInfo } from "./scenario_metadata.ts";
import { ScenarioResult } from "./runner.ts";
import type { RunnerArgs } from "./run_scenarios_types.ts";
import type { Topology } from "@garazyk/schemat";

/** Result returned by the scenario execution loop. */
export interface ScenarioExecutionResult {
  /** Scenario results in execution order. */
  results: Array<{ scenario: ScenarioInfo; result: ScenarioResult }>;
  /** Paths to JSON reports written for completed scenarios. */
  reportPaths: string[];
  /** Whether a container crash was detected before completion. */
  crashedContainer: boolean;
}

async function checkEssentialServicesHealth(
  topology: Topology,
): Promise<{ ok: boolean; message?: string }> {
  const essentials = ["plc", "pds", "appview"];
  const adminSecret = Deno.env.get("APPVIEW_ADMIN_SECRET") || "localdevadmin";

  for (const name of essentials) {
    const url = topology.serviceUrls[name];
    if (!url) continue;

    let healthUrl = url;
    const headers: Record<string, string> = {};

    if (name === "plc") healthUrl = `${url}/_health`;
    if (name === "pds") {
      healthUrl = `${url}/xrpc/com.atproto.server.describeServer`;
    }
    if (name === "appview") {
      healthUrl = `${url}/admin/backfill/status`;
      headers["Authorization"] = `Bearer ${adminSecret}`;
    }

    const ok = await waitForHttp(healthUrl, name.toUpperCase(), 5, headers);
    if (!ok) {
      return {
        ok: false,
        message: `Essential service "${name.toUpperCase()}" is unreachable or unhealthy at ${healthUrl}`,
      };
    }
  }
  return { ok: true };
}

/**
 * Run a sequence of scenarios with progress tracking, crash detection,
 * and OTel stats sampling.
 */
export async function runScenarioLoop(
  selected: ScenarioInfo[],
  args: RunnerArgs,
  topology: Topology,
  repoRoot: string,
  composeProject: string,
  reportsDir: string,
  runContext: { runId: string; runDir: string; diagnosticsDir: string },
): Promise<ScenarioExecutionResult> {
  const results: Array<{ scenario: ScenarioInfo; result: ScenarioResult }> = [];
  const reportPaths: string[] = [];

  console.log(bold(`\nRunning ${selected.length} scenario(s)...\n`));
  const durationCache = new DurationCache(repoRoot);
  const expectedDurations = selected.map((s) => durationCache.get(s.id));
  const progress = new ProgressBar(selected.length, expectedDurations);
  const progressPath = `${runContext.runDir}/progress.json`;
  const writeProgress = async (
    completed: number,
    currentScenario: ScenarioInfo | null,
    running = true,
  ) => {
    await Deno.mkdir(runContext.runDir, { recursive: true });
    const now = Date.now();
    await Deno.writeTextFile(
      progressPath,
      JSON.stringify(
        {
          runId: runContext.runId,
          total: selected.length,
          completed,
          currentScenario: currentScenario?.name ?? null,
          currentScenarioId: currentScenario?.id ?? null,
          updatedAt: now,
          running,
        },
        null,
        2,
      ) + "\n",
    );
  };

  const crashWatcher = await ContainerEventWatcher.create({ composeProject });
  const monitoredServices = new Set(Object.values(topology.serviceNames));
  let crashedContainer: {
    serviceName: string;
    exitCode: number;
    oomKilled: boolean;
  } | null = null;
  if (crashWatcher) {
    crashWatcher.subscribe((event: WatcherEvent) => {
      if (event.kind === "died" || event.kind === "oom") {
        if (!monitoredServices.has(event.serviceName)) return;
        crashedContainer = {
          serviceName: event.serviceName,
          exitCode: event.kind === "died" ? event.exitCode : 137,
          oomKilled: event.kind === "oom" || event.oomKilled,
        };
      }
    });
  }

  let statsSampler: ContainerStatsSampler | null = null;
  if (isOtelEnabled()) {
    const dockerClient = await createDockerClient();
    if (dockerClient) {
      statsSampler = new ContainerStatsSampler({
        client: dockerClient,
        composeProject,
        intervalMs: 5000,
        onMemoryPressure: (alert) => {
          console.warn(yellow(
            `  Memory pressure: ${alert.serviceName} failcnt=${alert.failcnt} ` +
              `(${formatBytes(alert.memoryUsageBytes)} / ${
                formatBytes(alert.memoryLimitBytes)
              })`,
          ));
        },
      });
      statsSampler.start();
    }
  }

  try {
    let abortedForCrash = false;
    for (let i = 0; i < selected.length; i++) {
      const scenario = selected[i];
      progress.start(`${scenario.id} - ${scenario.name}`);
      await writeProgress(i, scenario, true);

      const health = await checkEssentialServicesHealth(topology);
      if (!health.ok || crashedContainer !== null) {
        const crash: {
          serviceName: string;
          exitCode: number;
          oomKilled: boolean;
        } | null = crashedContainer;

        const crashInfo = health.message || (crash?.oomKilled
          ? `Container "${crash?.serviceName}" was OOM-killed (exit code ${crash?.exitCode})`
          : `Container "${crash?.serviceName}" exited unexpectedly (exit code ${crash?.exitCode})`);

        console.error(red(`\n  Service failure detected: ${crashInfo}`));
        console.error(yellow(`  Skipping remaining scenarios.`));

        const crashResult = new ScenarioResult(scenario.name);
        crashResult.start();
        crashResult.stepFailed("Pre-scenario container check", crashInfo);
        crashResult.finish();
        results.push({ scenario, result: crashResult });
        if (!args.noJson) {
          const reportPath = await crashResult.writeReport(
            reportsDir,
            `${scenario.id}_${scenario.name}`,
          );
          reportPaths.push(reportPath);
          console.log(`  Report: ${reportPath}`);
        }
        progress.update(results.length);
        await writeProgress(results.length, null, false);
        abortedForCrash = true;
        break;
      }

      const result = await withSpan(
        `scenario.${scenario.id}`,
        async () =>
          await runScenario(
            scenario,
            scenario.timeout || args.timeout,
            args,
            topology,
            repoRoot,
            composeProject,
          ),
        {
          "scenario.id": scenario.id,
          "scenario.name": scenario.name,
          "scenario.timeout": scenario.timeout || args.timeout,
          "scenario.runner": args.runner,
        },
      );
      result.metadata = {
        ...result.metadata,
        run_id: runContext.runId,
        run_dir: runContext.runDir,
        diagnostics_dir: runContext.diagnosticsDir,
        service_urls: topology.serviceUrls,
        web_client: topology.webClient || null,
        client_flow: args.clientFlow,
        allow_hybrid_network: args.allowHybridNetwork,
        scenario_id: scenario.id,
        binary_mode: args.binary,
        pds2: topology.manifest?.env?.scenario?.ATPROTO_TOPOLOGY_CAPABILITIES
          ?.includes("pds2") ||
          false,
        topology: topology.manifest?.name || null,
        runner: args.runner,
      };

      Deno.stdout.writeSync(
        new TextEncoder().encode("\r" + " ".repeat(120) + "\r"),
      );
      result.printSummary();
      results.push({ scenario, result });

      if (result.startedAt && result.finishedAt) {
        durationCache.set(scenario.id, result.finishedAt - result.startedAt);
      }

      if (!args.noJson) {
        const reportPath = await result.writeReport(
          reportsDir,
          `${scenario.id}_${scenario.name}`,
        );
        reportPaths.push(reportPath);
        console.log(`  Report: ${reportPath}`);
      }

      progress.update(i + 1);
      await writeProgress(
        i + 1,
        i + 1 < selected.length ? selected[i + 1] : null,
        i + 1 < selected.length,
      );
    }
    if (abortedForCrash) {
      console.log("");
    } else {
      progress.finish();
      await writeProgress(results.length, null, false);
    }
  } finally {
    await crashWatcher?.close();
    await statsSampler?.stop();
  }

  return { results, reportPaths, crashedContainer: crashedContainer !== null };
}

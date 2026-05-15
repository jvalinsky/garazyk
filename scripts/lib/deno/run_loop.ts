/**
 * Scenario execution loop with crash detection, progress tracking,
 * and OTel stats sampling.
 *
 * @module run_loop
 */

import { bold, green, red, yellow } from "@std/fmt/colors";
import { withSpan, isOtelEnabled } from "./otel.ts";
import { ContainerEventWatcher, type WatcherEvent } from "./docker_events.ts";
import { ContainerStatsSampler } from "./container_stats.ts";
import { createDockerClient } from "./docker_api.ts";
import { formatBytes } from "./format.ts";
import { DurationCache, ProgressBar } from "./progress.ts";
import { runScenario } from "./scenario_runner.ts";
import type { ScenarioInfo } from "./scenario_metadata.ts";
import { ScenarioResult } from "./runner.ts";
import type { RunContext } from "./docker_types.ts";
import type { RunnerArgs } from "./run_scenarios_types.ts";
import type { Topology } from "./topology_types.ts";

export interface ScenarioExecutionResult {
  results: Array<{ scenario: ScenarioInfo; result: ScenarioResult }>;
  reportPaths: string[];
  crashedContainer: boolean;
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

  const crashWatcher = await ContainerEventWatcher.create();
  let crashedContainer: { serviceName: string; exitCode: number; oomKilled: boolean } | null = null;
  if (crashWatcher) {
    crashWatcher.subscribe((event: WatcherEvent) => {
      if (event.kind === "died" || event.kind === "oom") {
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
            `(${formatBytes(alert.memoryUsageBytes)} / ${formatBytes(alert.memoryLimitBytes)})`,
          ));
        },
      });
      statsSampler.start();
    }
  }

  try {
    for (let i = 0; i < selected.length; i++) {
      const scenario = selected[i];
      progress.start(`${scenario.id} - ${scenario.name}`);

      if (crashedContainer !== null) {
        const crash: { serviceName: string; exitCode: number; oomKilled: boolean } = crashedContainer;
        const crashInfo = crash.oomKilled
          ? `Container "${crash.serviceName}" was OOM-killed (exit code ${crash.exitCode})`
          : `Container "${crash.serviceName}" exited unexpectedly (exit code ${crash.exitCode})`;
        console.error(red(`\n  Container crash detected: ${crashInfo}`));
        console.error(yellow(`  Skipping remaining scenarios.`));

        const crashResult = new ScenarioResult(scenario.name);
        crashResult.start();
        crashResult.stepFailed("Pre-scenario container check", crashInfo);
        crashResult.finish();
        results.push({ scenario, result: crashResult });
        break;
      }

      const result = await withSpan(
        `scenario.${scenario.id}`,
        async () => await runScenario(
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
        pds2: topology.manifest?.env?.scenario?.ATPROTO_TOPOLOGY_CAPABILITIES?.includes("pds2") || false,
        topology: topology.manifest?.name || null,
        runner: args.runner,
      };

      Deno.stdout.writeSync(new TextEncoder().encode("\r" + " ".repeat(120) + "\r"));
      result.printSummary();
      results.push({ scenario, result });

      if (result.startedAt && result.finishedAt) {
        durationCache.set(scenario.id, result.finishedAt - result.startedAt);
      }

      if (!args.noJson) {
        const reportPath = await result.writeReport(reportsDir, `${scenario.id}_${scenario.name}`);
        reportPaths.push(reportPath);
        console.log(`  Report: ${reportPath}`);
      }

      progress.update(i + 1);
    }
    progress.finish();
  } finally {
    await crashWatcher?.close();
    await statsSampler?.stop();
  }

  return { results, reportPaths, crashedContainer: crashedContainer !== null };
}

/**
 * Scenario execution loop with crash detection, progress tracking,
 * and OTel stats sampling.
 *
 * @module run_loop
 */

import { yellow } from "@std/fmt/colors";
import { isOtelEnabled, withSpan } from "./otel.ts";
import { ContainerEventWatcher, type WatcherEvent } from "@garazyk/laweta";
import { ContainerStatsSampler } from "@garazyk/laweta";
import { createDockerClient } from "@garazyk/laweta";
import { formatBytes } from "./format.ts";
import { DurationCache } from "./progress.ts";
import { runScenario } from "./scenario_runner.ts";
import { waitForHttp } from "@garazyk/laweta";
import type { ScenarioInfo } from "./scenario_metadata.ts";
import { ScenarioResult } from "./runner.ts";
import type { RunnerArgs } from "./run_scenarios_types.ts";
import type { Topology, TopologyManifestV2 } from "@garazyk/schemat";
import { HumanReadableSink, type ScenarioRunEventSink } from "./events.ts";

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
        message:
          `Essential service "${name.toUpperCase()}" is unreachable or unhealthy at ${healthUrl}`,
      };
    }
  }
  return { ok: true };
}

/**
 * Run a sequence of scenarios with progress tracking, crash detection,
 * and OTel stats sampling.
 *
 * Events are emitted to the provided sinks.  When no sinks are given,
 * a default {@link HumanReadableSink} is used, preserving the existing
 * terminal output behavior.
 */
export async function runScenarioLoop(
  selected: ScenarioInfo[],
  args: RunnerArgs,
  topology: Topology,
  repoRoot: string,
  composeProject: string,
  reportsDir: string,
  runContext: { runId: string; runDir: string; diagnosticsDir: string },
  sinks?: ScenarioRunEventSink[],
): Promise<ScenarioExecutionResult> {
  const results: Array<{ scenario: ScenarioInfo; result: ScenarioResult }> = [];
  const reportPaths: string[] = [];

  const durationCache = new DurationCache(repoRoot);
  const effectiveSinks: ScenarioRunEventSink[] = sinks && sinks.length > 0
    ? sinks
    : [new HumanReadableSink({ durationCache })];

  const emit = (event: Parameters<ScenarioRunEventSink["emit"]>[0]) => {
    for (const s of effectiveSinks) s.emit(event);
  };

  const runStartTime = Date.now();
  emit({
    type: "run_start",
    runId: runContext.runId,
    scenarioIds: selected.map((s) => s.id),
    total: selected.length,
    timestamp: runStartTime,
  });

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

  let dockerClient = null;
  let statsSampler: ContainerStatsSampler | null = null;
  if (isOtelEnabled()) {
    dockerClient = await createDockerClient();
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
      emit({
        type: "scenario_start",
        scenarioId: scenario.id,
        name: scenario.name,
        index: i,
        total: selected.length,
        timestamp: Date.now(),
      });
      await writeProgress(i, scenario, true);

      const health = await checkEssentialServicesHealth(topology);
      // crashedContainer is reassigned asynchronously by the crash watcher callback,
      // so TypeScript's flow analysis can't see the non-null path. Read it at the
      // checkpoint and assert the union type explicitly.
      const crashSnapshot = crashedContainer as {
        serviceName: string;
        exitCode: number;
        oomKilled: boolean;
      } | null;
      if (!health.ok || crashSnapshot !== null) {
        const crashInfo = health.message ||
          (crashSnapshot
            ? crashSnapshot.oomKilled
              ? `Container "${crashSnapshot.serviceName}" was OOM-killed (exit code ${crashSnapshot.exitCode})`
              : `Container "${crashSnapshot.serviceName}" exited unexpectedly (exit code ${crashSnapshot.exitCode})`
            : "Unknown service failure");

        emit({
          type: "service_failure",
          message: crashInfo,
          source: crashSnapshot !== null ? "container_crash" : "health_check",
          timestamp: Date.now(),
        });

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
        }

        const crashNow = Date.now();
        emit({
          type: "scenario_complete",
          scenarioId: scenario.id,
          name: scenario.name,
          ok: false,
          passed: crashResult.passed,
          failed: crashResult.failed,
          skipped: crashResult.skipped,
          durationS: (crashResult.startedAt && crashResult.finishedAt)
            ? (crashResult.finishedAt - crashResult.startedAt) / 1000
            : 0,
          summaryText: crashResult.summary(),
          reportPath: reportPaths[reportPaths.length - 1] || undefined,
          timestamp: crashNow,
        });
        emit({
          type: "run_progress",
          completed: results.length,
          total: selected.length,
          currentScenarioId: null,
          currentScenarioName: null,
          running: false,
          timestamp: crashNow,
        });
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
        pds2:
          (topology.manifest as TopologyManifestV2 | undefined)?.env?.scenario
            ?.ATPROTO_TOPOLOGY_CAPABILITIES
            ?.includes("pds2") ||
          false,
        topology: topology.manifest?.name || null,
        runner: args.runner,
      };

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
      }

      const scenarioCompleteTime = Date.now();
      const durationS = result.startedAt && result.finishedAt
        ? (result.finishedAt - result.startedAt) / 1000
        : 0;
      emit({
        type: "scenario_complete",
        scenarioId: scenario.id,
        name: scenario.name,
        ok: result.ok,
        passed: result.passed,
        failed: result.failed,
        skipped: result.skipped,
        durationS,
        summaryText: result.summary(),
        reportPath: reportPaths[reportPaths.length - 1] || undefined,
        timestamp: scenarioCompleteTime,
      });

      emit({
        type: "run_progress",
        completed: i + 1,
        total: selected.length,
        currentScenarioId: null,
        currentScenarioName: null,
        running: i + 1 < selected.length,
        timestamp: scenarioCompleteTime,
      });
      await writeProgress(
        i + 1,
        null,
        i + 1 < selected.length,
      );
    }
    if (!abortedForCrash) {
      await writeProgress(results.length, null, false);
    }

    const totalPassed = results.reduce((sum, r) => sum + r.result.passed, 0);
    const totalFailed = results.reduce((sum, r) => sum + r.result.failed, 0);
    const totalSkipped = results.reduce((sum, r) => sum + r.result.skipped, 0);
    emit({
      type: "run_finished",
      runId: runContext.runId,
      ok: !abortedForCrash && totalFailed === 0,
      totalPassed,
      totalFailed,
      totalSkipped,
      reportsDir,
      crashedContainer: crashedContainer !== null,
      timestamp: Date.now(),
    });
  } finally {
    // Close sinks after emitting the final event.
    for (const s of effectiveSinks) {
      await s.close?.();
    }
    await crashWatcher?.close();
    await statsSampler?.stop();
    dockerClient?.close();
  }

  return { results, reportPaths, crashedContainer: crashedContainer !== null };
}

/** Scenario run report aggregation and summary writing. @module report_writer */
import { bold, green, red, yellow } from "@std/fmt/colors";
import { join } from "@std/path";
import type { ScenarioInfo } from "./scenario_metadata.ts";
import type { RunnerArgs } from "./run_scenarios_types.ts";
import type { ScenarioResult } from "./runner.ts";
import type { Topology } from "./topology.ts";

/** A single scenario result paired with its metadata. */
export interface OverallResultItem {
  scenario: ScenarioInfo;
  result: ScenarioResult;
}

export interface OverallSummaryContext {
  runId: string;
  runDir: string;
  diagnosticsDir: string;
}

export interface WriteOverallSummaryOptions {
  context: OverallSummaryContext;
  topology?: Topology;
  selected: ScenarioInfo[];
  results: OverallResultItem[];
  args: RunnerArgs;
  reportPaths: string[];
  reportsDir: string;
  fatalError: unknown;
  withPds2: boolean;
}

export interface OverallSummaryTotals {
  totalPassed: number;
  totalFailed: number;
  totalSkipped: number;
}

export async function writeOverallSummary(options: WriteOverallSummaryOptions): Promise<OverallSummaryTotals> {
  const totalPassed = options.results.reduce((sum, item) => sum + item.result.passed, 0);
  const totalFailed = options.results.reduce((sum, item) => sum + item.result.failed, 0);
  const totalSkipped = options.results.reduce((sum, item) => sum + item.result.skipped, 0);

  if (options.results.length > 0) {
    console.log(bold("\nOverall Results"));
    for (const { scenario, result } of options.results) {
      const marker = result.ok ? green("PASS") : red("FAIL");
      console.log(
        `  ${marker} ${scenario.id} ${result.scenarioName} (${result.passed}/${result.total} passed, ${result.skipped} skipped)`,
      );
    }
    console.log(
      `  Total: ${green(`${totalPassed} passed`)}, ${
        totalFailed > 0 ? red(`${totalFailed} failed`) : "0 failed"
      }, ${yellow(`${totalSkipped} skipped`)}`,
    );
  }

  if (!options.args.noJson) {
    try {
      await Deno.mkdir(options.reportsDir, { recursive: true });
      await Deno.writeTextFile(
        join(options.reportsDir, "overall-summary.json"),
        JSON.stringify(
          {
            run_id: options.context.runId,
            run_dir: options.context.runDir,
            diagnostics_dir: options.context.diagnosticsDir,
            reports_dir: options.reportsDir,
            scenario_ids: options.selected.map((scenario) => scenario.id),
            binary_mode: options.args.binary,
            pds2: options.withPds2,
            web_client: options.topology?.webClient || null,
            client_flow: options.args.clientFlow,
            service_urls: options.topology?.serviceUrls,
            report_paths: options.reportPaths,
            summary: {
              passed: totalPassed,
              failed: options.fatalError ? totalFailed + 1 : totalFailed,
              skipped: totalSkipped,
            },
            ok: !options.fatalError && totalFailed === 0,
            error: options.fatalError instanceof Error ? options.fatalError.message : undefined,
          },
          null,
          2,
        ) + "\n",
      );
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(red(`Failed to write overall summary: ${message}`));
    }
  }

  return { totalPassed, totalFailed, totalSkipped };
}

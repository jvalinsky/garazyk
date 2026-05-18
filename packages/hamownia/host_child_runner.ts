/** Host subprocess entry point for isolated scenario execution. @module host_child_runner */
import { dirname, toFileUrl } from "@std/path";
import { createScenarioContext } from "./scenario_context.ts";
import type { ScenarioContext } from "./scenario_context.ts";
import { ScenarioResult } from "./runner.ts";

interface HostChildArgs {
  scenarioPath: string;
  outputPath: string;
  scenarioId: string;
  scenarioName: string;
}

interface ScenarioModule {
  run?: (ctx: ScenarioContext) => Promise<ScenarioResult> | ScenarioResult;
}

function parseArgs(argv: string[]): HostChildArgs {
  const parsed: Partial<HostChildArgs> = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const value = argv[++i];
    if (!value) throw new Error(`${arg} requires a value`);
    if (arg === "--scenario") parsed.scenarioPath = value;
    else if (arg === "--output") parsed.outputPath = value;
    else if (arg === "--scenario-id") parsed.scenarioId = value;
    else if (arg === "--scenario-name") parsed.scenarioName = value;
    else throw new Error(`Unknown option: ${arg}`);
  }
  if (
    !parsed.scenarioPath || !parsed.outputPath || !parsed.scenarioId ||
    !parsed.scenarioName
  ) {
    throw new Error("Missing required host child runner arguments");
  }
  return parsed as HostChildArgs;
}

async function writeResult(
  outputPath: string,
  result: ScenarioResult,
): Promise<void> {
  await Deno.mkdir(dirname(outputPath), { recursive: true });
  await Deno.writeTextFile(
    outputPath,
    JSON.stringify(result.toReport(), null, 2) + "\n",
  );
}

async function runChild(): Promise<number> {
  const args = parseArgs(Deno.args);
  const result = new ScenarioResult(args.scenarioName);
  try {
    // deno-lint-ignore unanalyzable-dynamic-import
    const module = await import(
      `${toFileUrl(args.scenarioPath).href}?run=${Date.now()}`
    ) as ScenarioModule;
    if (typeof module.run !== "function") {
      result.start();
      result.stepFailed(
        `Scenario ${args.scenarioId} entry point`,
        "No run() export defined",
      );
      result.finish();
      await writeResult(args.outputPath, result);
      return 1;
    }

    const ctx = createScenarioContext();
    const scenarioResult = await module.run(ctx);

    if (!(scenarioResult instanceof ScenarioResult)) {
      result.start();
      result.stepFailed(
        `Scenario ${args.scenarioId} entry point`,
        "run() did not return a ScenarioResult",
      );
      result.finish();
      await writeResult(args.outputPath, result);
      return 1;
    }
    if (!scenarioResult.startedAt) scenarioResult.startedAt = Date.now();
    if (!scenarioResult.finishedAt) scenarioResult.finishedAt = Date.now();
    await writeResult(args.outputPath, scenarioResult);
    return scenarioResult.ok ? 0 : 1;
  } catch (exc) {
    result.start();
    result.stepFailed(
      `Scenario ${args.scenarioId} execution`,
      exc instanceof Error ? exc.message : String(exc),
    );
    result.finish();
    await writeResult(args.outputPath, result);
    return 1;
  }
}

if (import.meta.main) {
  Deno.exit(await runChild());
}

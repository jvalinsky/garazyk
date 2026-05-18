#!/usr/bin/env -S deno run -A

/**
 * @module run_scenarios
 *
 * Scenario Runner: Thin CLI wrapper for E2E ATProto service testing.
 *
 * All orchestration logic lives in `@garazyk/hamownia/run-command`.
 * This script resolves repo paths and delegates.
 */

import { fromFileUrl, join } from "@std/path";
import { runScenarioCommand } from "@garazyk/hamownia/run-command";

const scriptDir = fromFileUrl(new URL(".", import.meta.url));

await runScenarioCommand(Deno.args, {
  repoRoot: join(scriptDir, ".."),
  scenarioDir: join(scriptDir, "scenarios", "scenarios"),
  scriptPath: fromFileUrl(import.meta.url),
});

#!/usr/bin/env -S deno run -A

/**
 * Scenario runner CLI entrypoint.
 *
 * The orchestration implementation lives in @garazyk/hamownia so it can be
 * tested as package code while this script remains a stable user-facing path.
 */

import { fromFileUrl, join } from "@std/path";
import { runScenarioCommand } from "../packages/hamownia/run_command.ts";

const scriptDir = fromFileUrl(new URL(".", import.meta.url));

await runScenarioCommand(Deno.args, {
  repoRoot: join(scriptDir, ".."),
  scenarioDir: join(scriptDir, "scenarios", "scenarios"),
  scriptPath: fromFileUrl(import.meta.url),
});

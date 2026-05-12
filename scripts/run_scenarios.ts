#!/usr/bin/env -S deno run -A
import { parseArgs } from "@std/cli/parse-args";
import { join, fromFileUrl } from "@std/path";
import { startLocalNetwork, stopLocalNetwork } from "./lib/deno/docker.ts";
import { ScenarioResult } from "./lib/deno/runner.ts";
import { brightBlue, bold, green, red, yellow } from "@std/fmt/colors";

async function main() {
  const args = parseArgs(Deno.args, {
    boolean: ["setup-only", "teardown", "pds2", "list", "no-setup"],
    string: ["run-id"],
    alias: { "no-setup": "keep-running" } // Simplified for now
  });

  const scriptDir = fromFileUrl(new URL(".", import.meta.url));
  const scenarioDir = join(scriptDir, "scenarios", "scenarios");
  const scenarios: { id: string; name: string; path: string }[] = [];

  for await (const entry of Deno.readDir(scenarioDir)) {
    if (entry.isFile && entry.name.endsWith(".ts")) {
      const match = entry.name.match(/^(\d+)_(.+)\.ts$/);
      if (match) {
        scenarios.push({
          id: match[1],
          name: match[2].replace(/_/g, " "),
          path: join(scenarioDir, entry.name),
        });
      }
    }
  }

  scenarios.sort((a, b) => a.id.localeCompare(b.id));

  if (args.list) {
    console.log(bold("\nAvailable Scenarios:"));
    for (const s of scenarios) {
      console.log(`  ${brightBlue(s.id)} - ${s.name}`);
    }
    console.log("");
    Deno.exit(0);
  }

  if (args.teardown) {
    console.log("Tearing down local network...");
    await stopLocalNetwork();
    Deno.exit(0);
  }

  const requestedIds = args._.map(String);
  const scenariosToRun = requestedIds.length > 0
    ? scenarios.filter(s => requestedIds.includes(s.id))
    : scenarios;

  if (scenariosToRun.length === 0 && requestedIds.length > 0) {
    console.error(red(`No scenarios found matching: ${requestedIds.join(", ")}`));
    Deno.exit(1);
  }

  if (!args["no-setup"]) {
    console.log("Starting local network...");
    await startLocalNetwork(args.pds2 || scenariosToRun.some(s => s.id === "05"));
  }

  if (args["setup-only"]) {
    console.log("Network started. Exiting.");
    Deno.exit(0);
  }

  console.log(bold(`\nRunning ${scenariosToRun.length} scenario(s)...\n`));

  const results: ScenarioResult[] = [];
  let allPassed = true;

  for (const s of scenariosToRun) {
    console.log(`${bold("Executing:")} ${brightBlue(s.id)} - ${s.name}`);
    try {
      const module = await import(`file://${s.path}`);
      if (typeof module.run === "function") {
        const result: ScenarioResult = await module.run();
        console.log(result.summary());
        results.push(result);
        if (!result.ok) allPassed = false;
      } else {
        console.error(red(`  ✗ Error: Scenario ${s.id} does not export a run() function.`));
        allPassed = false;
      }
    } catch (e) {
      console.error(red(`  ✗ Fatal Error running scenario ${s.id}:`), e);
      allPassed = false;
    }
  }

  console.log(bold("Final Summary:"));
  const passedCount = results.filter(r => r.ok).length;
  const failedCount = results.filter(r => !r.ok).length;

  console.log(`  ${green(`${passedCount} Passed`)}`);
  if (failedCount > 0) {
    console.log(`  ${red(`${failedCount} Failed`)}`);
  }

  if (!allPassed) {
    Deno.exit(1);
  }
}

if (import.meta.main) {
  main();
}

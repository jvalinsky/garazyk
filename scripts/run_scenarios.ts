#!/usr/bin/env -S deno run -A
import { parseArgs } from "@std/cli/parse-args";
import { join, fromFileUrl } from "@std/path";
import { startLocalNetwork, stopLocalNetwork } from "./lib/deno/docker.ts";
import { ScenarioResult } from "./lib/deno/runner.ts";
import { ProgressBar, DurationCache } from "./lib/deno/progress.ts";
import { brightBlue, bold, green, red, yellow, cyan } from "@std/fmt/colors";

async function main() {
  const args = parseArgs(Deno.args, {
    boolean: ["setup-only", "teardown", "pds2", "list", "no-setup"],
    string: ["run-id"],
    alias: { "no-setup": "keep-running" } // Simplified for now
  });

  const scriptDir = fromFileUrl(new URL(".", import.meta.url));
  const repoRoot = join(scriptDir, "..");
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
    ? scenarios.filter(s => requestedIds.map(id => id.padStart(2, "0")).includes(s.id))
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

  const durationCache = new DurationCache(repoRoot);
  const expectedDurations = scenariosToRun.map(s => durationCache.get(s.id));
  const pb = new ProgressBar(scenariosToRun.length, expectedDurations);

  for (let i = 0; i < scenariosToRun.length; i++) {
    const s = scenariosToRun[i];
    
    // Clear the progress bar line before printing current task info
    // but we'll let the progress bar handle its own rendering.
    pb.start(`${s.id} - ${s.name}`);

    try {
      const module = await import(`file://${s.path}`);
      if (typeof module.run === "function") {
        const result: ScenarioResult = await module.run();
        
        // Before printing summary, clear progress bar if needed
        // but here we just print over it or let it be.
        // To be clean, we can move to next line.
        Deno.stdout.writeSync(new TextEncoder().encode("\r" + " ".repeat(100) + "\r")); 
        
        console.log(result.summary());
        results.push(result);
        if (!result.ok) allPassed = false;

        if (result.startedAt && result.finishedAt) {
          durationCache.set(s.id, result.finishedAt - result.startedAt);
        }

        if (args["run-id"]) {
          try {
            const reportFile = {
              scenario: s.name,
              started_at: result.startedAt ? Math.floor(result.startedAt / 1000) : 0,
              finished_at: result.finishedAt ? Math.floor(result.finishedAt / 1000) : 0,
              duration_s: (result.finishedAt && result.startedAt) ? (result.finishedAt - result.startedAt) / 1000 : 0,
              steps: result.steps.map(step => ({
                name: step.name,
                status: step.status,
                detail: step.detail,
                duration_ms: step.durationMs,
              })),
              summary: {
                passed: result.passed,
                failed: result.failed,
                skipped: result.skipped,
                total: result.steps.length,
              },
              ok: result.ok,
            };
            
            const reportsDir = join(scriptDir, "scenarios", "reports");
            await Deno.mkdir(reportsDir, { recursive: true });
            const safeName = s.name.replace(/[^a-zA-Z0-9_]/g, "_");
            const filename = `${args["run-id"]}-${s.id}_${safeName}.json`;
            await Deno.writeTextFile(join(reportsDir, filename), JSON.stringify(reportFile, null, 2));
            console.log(`Saved report to ${filename}`);
          } catch (e) {
            console.error("Failed to save JSON report", e);
          }
        }
      } else {
        Deno.stdout.writeSync(new TextEncoder().encode("\r" + " ".repeat(100) + "\r"));
        console.error(red(`  ✗ Error: Scenario ${s.id} does not export a run() function.`));
        allPassed = false;
      }
    } catch (e) {
      Deno.stdout.writeSync(new TextEncoder().encode("\r" + " ".repeat(100) + "\r"));
      console.error(red(`  ✗ Fatal Error running scenario ${s.id}:`), e);
      allPassed = false;
    }
    
    // Write live progress file after each scenario regardless of success/failure
    if (args["run-id"]) {
      try {
        const reportsDir = join(scriptDir, "scenarios", "reports");
        await Deno.mkdir(reportsDir, { recursive: true });
        const progress = {
          runId: args["run-id"],
          total: scenariosToRun.length,
          completed: i + 1,
          currentScenario: s.name,
          currentScenarioId: s.id,
          elapsedMs: pb.getElapsedMs(),
          updatedAt: Date.now(),
          running: true,
        };
        const progressPath = join(reportsDir, `${args["run-id"]}-progress.json`);
        await Deno.writeTextFile(progressPath, JSON.stringify(progress));
      } catch (e) {
        console.error("Failed to write progress file", e);
      }
    }
    
    pb.update(i + 1);
  }

  pb.finish();

  console.log(bold("\nFinal Summary:"));
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


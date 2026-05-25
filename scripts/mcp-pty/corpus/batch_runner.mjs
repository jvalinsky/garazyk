#!/usr/bin/env node
/**
 * Batch E2E Scenario Runner — runs YAML scenarios against installed TUI apps
 * and produces a pass/fail report.
 *
 * Usage:
 *   node corpus/batch_runner.mjs                    # run all installed
 *   node corpus/batch_runner.mjs --limit 10          # run first 10
 *   node corpus/batch_runner.mjs --apps lazygit,vim   # run specific apps
 *   node corpus/batch_runner.mjs --include-candidates # include generated candidate scenarios
 *   node corpus/batch_runner.mjs --dry-run            # validate scenarios without executing
 *   node corpus/batch_runner.mjs --report batch.json  # save report to file
 *   node corpus/batch_runner.mjs --timeout 15000      # timeout per scenario (ms)
 *
 * The runner:
 * 1. Loads the manifest
 * 2. Finds which apps are installed
 * 3. For each installed app, finds the YAML scenario in tests/
 * 4. Executes each scenario with a timeout
 * 5. Produces a batch JSON report
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { binaryExists, resolveBinary } from "./path_utils.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MANIFEST_PATH = path.join(__dirname, "manifest.json");
const TESTS_DIR = path.join(__dirname, "..", "tests");
const RUNNER_PATH = path.join(__dirname, "runner.mjs");
const FALLBACK_CURATED_IDS = new Set([
  "gitui",
  "yazi",
  "csvlens",
  "btop",
  "bottom",
  "ncdu",
  "tty-solitaire",
  "nudoku",
  "mc",
  "glow",
  "vim",
  "broot",
  "cbonsai",
  "greed",
]);

/**
 * Load the manifest.
 */
function loadManifest() {
  return JSON.parse(fs.readFileSync(MANIFEST_PATH, "utf-8"));
}

function curatedIds(manifest) {
  return new Set(manifest.tiers?.curated || [...FALLBACK_CURATED_IDS]);
}

function appTier(app, manifest) {
  return app.tier ||
    (curatedIds(manifest).has(app.id) ? "curated" : "candidate");
}

/**
 * Check if a binary exists on the system.
 */
function appIsInstalled(app) {
  if (!app.binary) return false;
  return binaryExists(app.binary);
}

/**
 * Find the YAML scenario path for an app.
 */
function findScenario(app) {
  const candidates = [
    path.join(TESTS_DIR, app.scenario || `${app.id}.yaml`),
    path.join(TESTS_DIR, `${app.id}.yaml`),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return null;
}

/**
 * Run a single scenario as a subprocess with a timeout.
 * Returns { appId, name, scenarioPath, passed, stepsTotal, stepsPassed, stepsFailed, elapsedMs, error }
 */
function runOne(appId, timeoutMs = 15000) {
  return new Promise((resolve) => {
    const manifest = loadManifest();
    const app = manifest.apps.find((a) => a.id === appId);
    if (!app) {
      resolve({ appId, error: "Not in manifest" });
      return;
    }

    const scenarioPath = findScenario(app);
    if (!scenarioPath) {
      resolve({ appId, name: app.name, error: "No scenario found" });
      return;
    }

    // Determine command (with cwd for local apps)
    let env = { ...process.env };
    if (app.cwd) {
      env.PWD = path.resolve(__dirname, "..", "..", app.cwd);
    }

    const child = spawn("node", [
      RUNNER_PATH,
      scenarioPath,
      "--continue-on-failure",
    ], {
      cwd: process.cwd(),
      env,
      stdio: "pipe",
      timeout: timeoutMs,
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (d) => {
      stdout += d.toString();
    });
    child.stderr.on("data", (d) => {
      stderr += d.toString();
    });

    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      setTimeout(() => child.kill("SIGKILL"), 2000);
    }, timeoutMs);

    child.on("close", (code) => {
      clearTimeout(timer);
      // Try to parse pass/fail from output
      const passMatch = stdout.match(/Result:\s*(\w+)/);
      const overall = passMatch ? passMatch[1] : (code === 0 ? "PASS" : "FAIL");

      resolve({
        appId,
        name: app.name,
        framework: app.framework,
        category: app.category,
        tier: appTier(app, manifest),
        scenarioPath,
        passed: overall === "PASS",
        exitCode: code,
        timeout: false,
        elapsedMs: 0,
        stdout: stdout.slice(-500),
        stderr: stderr.slice(-500),
      });
    });

    child.on("error", (err) => {
      clearTimeout(timer);
      resolve({
        appId,
        name: app.name,
        error: `Spawn error: ${err.message}`,
        passed: false,
      });
    });
  });
}

/**
 * Dry-run: validate that the scenario YAML can be parsed and the command exists.
 */
function dryRunOne(appId) {
  const manifest = loadManifest();
  const app = manifest.apps.find((a) => a.id === appId);
  if (!app) return { appId, error: "Not in manifest" };

  const scenarioPath = findScenario(app);
  if (!scenarioPath) return { appId, name: app.name, error: "No scenario" };

  try {
    const yaml = fs.readFileSync(scenarioPath, "utf-8");
    const hasCommand = yaml.includes("command:");
    const hasSteps = yaml.includes("steps:");
    const hasType = yaml.includes("type:");
    const stepCount = (yaml.match(/- type:/g) || []).length;

    return {
      appId,
      name: app.name,
      framework: app.framework,
      category: app.category,
      tier: appTier(app, manifest),
      scenarioPath,
      command: app.binary,
      installed: appIsInstalled(app),
      valid: hasCommand && hasSteps && hasType,
      stepCount,
    };
  } catch (err) {
    return { appId, name: app.name, error: err.message };
  }
}

/**
 * Run a batch of scenarios sequentially with optional concurrency.
 */
async function runBatch(options = {}) {
  const {
    limit = Infinity,
    appIds = null,
    timeoutMs = 15000,
    dryRun = false,
    reportPath = null,
    concurrency = 1,
    includeCandidates = false,
  } = options;

  const manifest = loadManifest();

  // Find installed apps
  let installed = manifest.apps.filter((a) => appIsInstalled(a));
  if (!includeCandidates) {
    installed = installed.filter((a) => appTier(a, manifest) === "curated");
  }

  // Filter to specific apps if requested
  if (appIds) {
    const idSet = new Set(appIds.split(",").map((s) => s.trim()));
    installed = installed.filter((a) => idSet.has(a.id));
  }

  // Limit
  if (limit < installed.length) {
    installed = installed.slice(0, limit);
  }

  console.log(`\n╔════════════════════════════════════════════╗`);
  console.log(`║  Batch Scenario Runner                    ║`);
  console.log(
    `║  Apps: ${String(installed.length).padStart(3)} installed / ${
      String(manifest.apps.length).padStart(3)
    } in manifest`.padEnd(43) + "║",
  );
  console.log(
    `║  Tier: ${includeCandidates ? "curated+candidate" : "curated only"}${
      " ".repeat(includeCandidates ? 7 : 13)
    }║`,
  );
  console.log(
    `║  Mode: ${dryRun ? "dry-run validation" : "live execution"}         ║`,
  );
  if (!dryRun) {
    console.log(`║  Timeout: ${String(timeoutMs)}ms per scenario            ║`);
  }
  console.log(`╚════════════════════════════════════════════╝\n`);

  const results = [];
  const startTime = Date.now();

  if (dryRun) {
    // Dry-run: just validate YAML structure and binary existence
    for (const app of installed) {
      const result = dryRunOne(app.id);
      const status = result.valid ? "✓" : "✗";
      console.log(
        `  ${status} ${app.id.padEnd(20)} ${result.command || "—".padEnd(30)} ${
          result.stepCount || 0
        } steps`,
      );
      results.push(result);
    }
  } else {
    // Live execution: run each scenario as subprocess
    for (let i = 0; i < installed.length; i += concurrency) {
      const batch = installed.slice(i, i + concurrency);
      const batchResults = await Promise.all(
        batch.map((app) => runOne(app.id, timeoutMs)),
      );

      for (const r of batchResults) {
        const status = r.passed ? "✓" : (r.timeout ? "⏱" : "✗");
        const detail = r.error || (r.passed ? "PASS" : "FAIL");
        console.log(
          `  ${status} ${r.appId.padEnd(20)} ${
            r.framework?.padEnd(12) || ""
          } ${detail}`,
        );
        results.push(r);
      }
    }
  }

  const elapsed = Date.now() - startTime;
  const passed = results.filter((r) => r.passed || r.valid).length;
  const failed = results.filter((r) => !r.passed && !r.valid).length;
  const errored = results.filter((r) => r.error && !r.passed).length;

  // Build report
  const report = {
    timestamp: new Date().toISOString(),
    mode: dryRun ? "dry-run" : "live",
    totalApps: installed.length,
    passed,
    failed,
    errored,
    elapsedMs: elapsed,
    timeoutMs,
    results,
  };

  // Summary
  console.log(`\n╔════════════════════════════════════════════╗`);
  console.log(`║  Batch Complete                           ║`);
  console.log(`║  Total: ${String(installed.length).padEnd(34)}║`);
  console.log(
    `║  Passed: ${String(passed).padStart(2)} / ${
      String(installed.length).padStart(2)
    }`.padEnd(43) + "║",
  );
  console.log(
    `║  Failed: ${String(failed).padStart(2)} / ${
      String(installed.length).padStart(2)
    }`.padEnd(43) + "║",
  );
  console.log(`║  Time:   ${(elapsed / 1000).toFixed(1)}s`.padEnd(43) + "║");
  console.log(`╚════════════════════════════════════════════╝`);

  // Write report
  if (reportPath) {
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2) + "\n");
    console.log(`\nReport written to: ${reportPath}`);
  }

  return report;
}

// ── CLI Entry ────────────────────────────────────────────────────────────

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const options = {
    dryRun: args.includes("--dry-run"),
    includeCandidates: args.includes("--include-candidates"),
    limit: args.includes("--limit")
      ? parseInt(args[args.indexOf("--limit") + 1], 10)
      : Infinity,
    appIds: args.includes("--apps") ? args[args.indexOf("--apps") + 1] : null,
    timeoutMs: args.includes("--timeout")
      ? parseInt(args[args.indexOf("--timeout") + 1], 10)
      : 15000,
    reportPath: args.includes("--report")
      ? args[args.indexOf("--report") + 1]
      : null,
    concurrency: 1,
  };

  runBatch(options).then((report) => {
    process.exit(report.failed > 0 ? 1 : 0);
  }).catch((err) => {
    console.error("Fatal:", err.message);
    process.exit(1);
  });
}

export {
  appIsInstalled,
  appTier,
  dryRunOne,
  findScenario,
  loadManifest,
  runBatch,
  runOne,
};

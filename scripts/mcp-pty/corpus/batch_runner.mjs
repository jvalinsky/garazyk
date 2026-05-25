#!/usr/bin/env node
/**
 * Batch Corpus Runner — runs manifest-backed YAML scenarios against installed
 * TUI apps and produces a pass/fail report.
 *
 * Usage:
 *   node corpus/batch_runner.mjs                      # curated installed apps
 *   node corpus/batch_runner.mjs --include-candidates # all installed candidates
 *   node corpus/batch_runner.mjs --dry-run            # validate without launching
 *   node corpus/batch_runner.mjs --sidecar            # run through garazyk-ptyd
 *   node corpus/batch_runner.mjs --apps gitui,yazi    # specific app IDs
 *   node corpus/batch_runner.mjs --limit 10
 *   node corpus/batch_runner.mjs --report batch.json
 *   node corpus/batch_runner.mjs --sidecar --record    # record asciicasts
 */

import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

import { parseYaml } from "./runner.mjs";
import { binaryExists, resolveBinary, resolveSidecarBinary } from "./path_utils.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MANIFEST_PATH = path.join(__dirname, "manifest.json");
const TESTS_DIR = path.join(__dirname, "..", "tests");
const RUNNER_PATH = path.join(__dirname, "runner.mjs");

const SIDECAR_BINARY = resolveSidecarBinary(import.meta.url);
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
  "ranger",
  "htop",
  "lazygit",
  "nano",
  "nsnake",
  "tig",
  "dua-cli",
]);

function loadManifest() {
  return JSON.parse(fs.readFileSync(MANIFEST_PATH, "utf8"));
}

function curatedIds(manifest) {
  return new Set(manifest.tiers?.curated || [...FALLBACK_CURATED_IDS]);
}

function appTier(app, manifest) {
  return app.tier ||
    (curatedIds(manifest).has(app.id) ? "curated" : "candidate");
}

function appIsInstalled(app) {
  if (!app.binary) return false;
  return binaryExists(app.binary);
}

function findScenario(app) {
  const candidates = [
    path.join(TESTS_DIR, app.scenario || `${app.id}.yaml`),
    path.join(TESTS_DIR, `${app.id}.yaml`),
  ];
  return candidates.find((candidate) => fs.existsSync(candidate)) || null;
}

function scenarioCommandAvailable(scenarioPath) {
  try {
    const yamlText = fs.readFileSync(scenarioPath, "utf8");
    const scenario = parseYaml(yamlText);
    return resolveBinary(scenario.command) !== null;
  } catch {
    return false;
  }
}

function dryRunOne(app, manifest) {
  const scenarioPath = findScenario(app);
  if (!scenarioPath) {
    return {
      appId: app.id,
      name: app.name,
      tier: appTier(app, manifest),
      valid: false,
      error: "No scenario found",
    };
  }

  try {
    const scenario = parseYaml(fs.readFileSync(scenarioPath, "utf8"));
    return {
      appId: app.id,
      name: app.name,
      framework: app.framework,
      category: app.category,
      tier: appTier(app, manifest),
      scenarioPath,
      command: scenario.command,
      installed: appIsInstalled(app),
      commandAvailable: scenarioCommandAvailable(scenarioPath),
      valid: !!scenario.command && Array.isArray(scenario.steps) &&
        scenario.steps.length > 0,
      stepCount: scenario.steps?.length || 0,
    };
  } catch (err) {
    return {
      appId: app.id,
      name: app.name,
      tier: appTier(app, manifest),
      valid: false,
      error: err.message,
    };
  }
}

function runOne(app, manifest, options = {}) {
  return new Promise((resolve) => {
    const scenarioPath = findScenario(app);
    if (!scenarioPath) {
      resolve({
        appId: app.id,
        name: app.name,
        tier: appTier(app, manifest),
        passed: false,
        error: "No scenario found",
      });
      return;
    }

    const timeoutMs = options.timeoutMs || 15_000;
    const args = [RUNNER_PATH, scenarioPath, "--continue-on-failure"];
    if (options.sidecar) args.push("--sidecar");
    if (options.record) args.push("--record");

    const childEnv = { ...process.env };
    // Propagate sidecar binary path so runner.mjs can find garazyk-ptyd.
    if (options.sidecar) {
      childEnv.GARAZYK_PTY_SIDECAR_BINARY = SIDECAR_BINARY;
    }

    const child = spawn("node", args, {
      cwd: process.cwd(),
      env: childEnv,
      stdio: "pipe",
    });

    let stdout = "";
    let stderr = "";
    const started = Date.now();
    let timedOut = false;

    child.stdout.on("data", (data) => {
      stdout += data.toString();
    });
    child.stderr.on("data", (data) => {
      stderr += data.toString();
    });

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGTERM");
      setTimeout(() => child.kill("SIGKILL"), 2_000).unref?.();
    }, timeoutMs);

    child.on("close", (code) => {
      clearTimeout(timer);
      const passMatch = stdout.match(/Result:\s*(\w+)/);
      const overall = passMatch ? passMatch[1] : (code === 0 ? "PASS" : "FAIL");
      // Detect timing violations from runner's ⚡ marker
      const timingViolations = (stdout.match(/⚡/g) || []).length;
      resolve({
        appId: app.id,
        name: app.name,
        framework: app.framework,
        category: app.category,
        tier: appTier(app, manifest),
        scenarioPath,
        passed: overall === "PASS",
        exitCode: code,
        timeout: timedOut,
        elapsedMs: Date.now() - started,
        timingViolations,
        flaky: timingViolations > 0,
        stdout: stdout.slice(-800),
        stderr: stderr.slice(-800),
      });
    });

    child.on("error", (err) => {
      clearTimeout(timer);
      resolve({
        appId: app.id,
        name: app.name,
        tier: appTier(app, manifest),
        passed: false,
        error: `Spawn error: ${err.message}`,
      });
    });
  });
}

function selectApps(manifest, options = {}) {
  let apps = manifest.apps.filter((app) => appIsInstalled(app));

  if (!options.includeCandidates) {
    apps = apps.filter((app) => appTier(app, manifest) === "curated");
  }

  if (options.appIds) {
    const selected = new Set(
      String(options.appIds).split(",").map((id) => id.trim()).filter(Boolean),
    );
    apps = apps.filter((app) => selected.has(app.id));
  }

  if (Number.isFinite(options.limit)) {
    apps = apps.slice(0, options.limit);
  }

  return apps;
}

async function runBatch(options = {}) {
  const manifest = loadManifest();
  const apps = selectApps(manifest, options);
  const dryRun = options.dryRun === true;
  const timeoutMs = options.timeoutMs || 15_000;

  console.log("\n╔════════════════════════════════════════════╗");
  console.log("║  Batch Corpus Runner                      ║");
  console.log(
    `║  Apps: ${String(apps.length).padStart(3)} selected / ${
      String(manifest.apps.length).padStart(3)
    } in manifest`.padEnd(43) + "║",
  );
  console.log(
    `║  Tier: ${options.includeCandidates ? "curated+candidate" : "curated only"}`.padEnd(43) +
      "║",
  );
  console.log(`║  Mode: ${dryRun ? "dry-run validation" : "live execution"}`.padEnd(43) + "║");
  console.log(`║  PTY:  ${options.sidecar ? "sidecar" : "node-pty"}`.padEnd(43) + "║");
  if (!dryRun) {
    console.log(`║  Timeout: ${String(timeoutMs)}ms per scenario`.padEnd(43) + "║");
  }
  console.log("╚════════════════════════════════════════════╝\n");

  const results = [];
  const started = Date.now();

  if (dryRun) {
    for (const app of apps) {
      const result = dryRunOne(app, manifest);
      const status = result.valid ? "✓" : "✗";
      const command = result.command || app.binary || "—";
      console.log(
        `  ${status} ${app.id.padEnd(20)} ${command.padEnd(30)} ${
          result.stepCount || 0
        } steps`,
      );
      results.push(result);
    }
  } else {
    for (const app of apps) {
      const result = await runOne(app, manifest, {
        timeoutMs,
        sidecar: options.sidecar,
        record: options.record,
      });
      const status = result.passed ? "✓" : (result.timeout ? "⏱" : "✗");
      const detail = result.error || (result.passed ? "PASS" : "FAIL");
      console.log(
        `  ${status} ${app.id.padEnd(20)} ${
          app.framework?.padEnd(12) || ""
        } ${detail}`,
      );
      results.push(result);
    }
  }

  const elapsedMs = Date.now() - started;
  const passed = results.filter((result) => result.passed || result.valid).length;
  const failed = results.length - passed;
  const errored = results.filter((result) => result.error).length;
  const flaky = results.filter((result) => result.flaky).length;
  const report = {
    timestamp: new Date().toISOString(),
    mode: dryRun ? "dry-run" : "live",
    sidecar: options.sidecar === true,
    totalApps: apps.length,
    passed,
    failed,
    errored,
    flaky,
    elapsedMs,
    timeoutMs,
    results,
  };

  console.log("\n╔════════════════════════════════════════════╗");
  console.log("║  Batch Complete                           ║");
  console.log(`║  Total: ${String(apps.length).padEnd(34)}║`);
  console.log(`║  Passed: ${String(passed).padEnd(33)}║`);
  console.log(`║  Failed: ${String(failed).padEnd(33)}║`);
  if (flaky > 0) {
    console.log(`║  Flaky:  ${String(flaky).padEnd(33)}║`);
  }
  console.log(`║  Time:   ${(elapsedMs / 1000).toFixed(1)}s`.padEnd(43) + "║");
  console.log("╚════════════════════════════════════════════╝");

  if (options.reportPath) {
    fs.writeFileSync(options.reportPath, JSON.stringify(report, null, 2) + "\n");
    console.log(`\nReport written to: ${options.reportPath}`);
  }

  return report;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const options = {
    dryRun: args.includes("--dry-run"),
    includeCandidates: args.includes("--include-candidates"),
    appIds: args.includes("--apps") ? args[args.indexOf("--apps") + 1] : null,
    limit: args.includes("--limit")
      ? parseInt(args[args.indexOf("--limit") + 1], 10)
      : Infinity,
    timeoutMs: args.includes("--timeout")
      ? parseInt(args[args.indexOf("--timeout") + 1], 10)
      : 15_000,
    reportPath: args.includes("--report")
      ? args[args.indexOf("--report") + 1]
      : null,
    sidecar: args.includes("--sidecar"),
    record: args.includes("--record"),
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
  scenarioCommandAvailable,
  selectApps,
};

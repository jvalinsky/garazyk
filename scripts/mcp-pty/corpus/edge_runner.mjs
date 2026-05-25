#!/usr/bin/env node
/**
 * Edge-Case Scenario Runner — executes edge-case YAML scenarios that test
 * boundary conditions in terminal rendering and semantic recognition.
 *
 * Usage:
 *   node corpus/edge_runner.mjs                     # run all edge cases
 *   node corpus/edge_runner.mjs --list               # list available edge cases
 *   node corpus/edge_runner.mjs --case cjk_fullwidth # run a specific case
 *   node corpus/edge_runner.mjs --dry-run            # validate without executing
 *   node corpus/edge_runner.mjs --report edge.json   # save report to file
 *
 * The runner:
 * 1. Scans the edge_cases/ directory for YAML files
 * 2. For each, checks if the required app is installed
 * 3. Executes the scenario using the main runner.mjs
 * 4. Produces a report
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { resolveBinary, binaryExists } from "./path_utils.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const EDGE_DIR = path.join(__dirname, "edge_cases");
const RUNNER_PATH = path.join(__dirname, "runner.mjs");



/**
 * Parse the command from a YAML file (minimal parser for our format).
 */
function parseCommand(yaml) {
  const match = yaml.match(/^command:\s*(.+)$/m);
  return match ? match[1].trim() : null;
}

/**
 * Parse name/description from a YAML file.
 */
function parseMeta(yaml) {
  const name = (yaml.match(/^name:\s*(.+)$/m) || [])[1] || "unknown";
  const desc = (yaml.match(/^description:\s*(.+)$/m) || [])[1] || "";
  return { name: name.trim(), description: desc.trim().replace(/^"|"$/g, "") };
}

/**
 * List all edge case YAML files.
 */
function listEdgeCases() {
  return fs.readdirSync(EDGE_DIR)
    .filter(f => f.endsWith(".yaml"))
    .sort();
}

/**
 * Run a single edge case scenario.
 */
function runEdgeCase(filename, options = {}) {
  return new Promise((resolve) => {
    const filepath = path.join(EDGE_DIR, filename);
    let yaml;
    try {
      yaml = fs.readFileSync(filepath, "utf-8");
    } catch (err) {
      resolve({ filename, error: `Cannot read: ${err.message}` });
      return;
    }

    const meta = parseMeta(yaml);
    const command = parseCommand(yaml);

    // Check if app is installed
    const resolved = command ? resolveBinary(command) : null;
    const installed = resolved !== null;

    if (options.dryRun) {
      resolve({
        filename: filename.replace(".yaml", ""),
        name: meta.name,
        description: meta.description,
        command,
        resolved,
        installed,
        valid: yaml.includes("name:") && yaml.includes("steps:") && yaml.includes("type:"),
        stepCount: (yaml.match(/^\s*- type:/gm) || []).length,
      });
      return;
    }

    if (!installed) {
      resolve({
        filename: filename.replace(".yaml", ""),
        name: meta.name,
        command,
        passed: false,
        skipped: true,
        reason: `Binary not found: ${command}`,
      });
      return;
    }

    const timeoutMs = options.timeoutMs || 15000;
    const child = spawn("node", [RUNNER_PATH, filepath, "--continue-on-failure"], {
      cwd: process.cwd(),
      env: { ...process.env },
      stdio: "pipe",
      timeout: timeoutMs,
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (d) => { stdout += d.toString(); });
    child.stderr.on("data", (d) => { stderr += d.toString(); });

    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      setTimeout(() => child.kill("SIGKILL"), 2000);
    }, timeoutMs);

    child.on("close", (code) => {
      clearTimeout(timer);
      const passMatch = stdout.match(/Result:\s*(\w+)/);
      const overall = passMatch ? passMatch[1] : (code === 0 ? "PASS" : "FAIL");

      resolve({
        filename: filename.replace(".yaml", ""),
        name: meta.name,
        command: resolved,
        passed: overall === "PASS",
        skipped: false,
        exitCode: code,
        stdout: stdout.slice(-300),
        stderr: stderr.slice(-300),
      });
    });

    child.on("error", (err) => {
      clearTimeout(timer);
      resolve({
        filename: filename.replace(".yaml", ""),
        name: meta.name,
        passed: false,
        error: `Spawn error: ${err.message}`,
      });
    });
  });
}

/**
 * Run all edge cases.
 */
async function runAll(options = {}) {
  const files = listEdgeCases();
  if (files.length === 0) {
    console.log("No edge case scenarios found in", EDGE_DIR);
    return;
  }

  const mode = options.dryRun ? "dry-run validation" : "live execution";
  console.log(`\n╔════════════════════════════════════════════╗`);
  console.log(`║  Edge-Case Scenario Runner                ║`);
  console.log(`║  Scenarios: ${String(files.length).padEnd(34)}║`);
  console.log(`║  Mode: ${mode.padEnd(34)}║`);
  console.log(`╚════════════════════════════════════════════╝\n`);

  const results = [];
  const startTime = Date.now();

  for (const f of files) {
    const r = await runEdgeCase(f, options);
    if (options.dryRun) {
      const status = r.valid ? "✓" : "✗";
      const inst = r.installed ? "installed" : "missing";
      console.log(`  ${status} ${r.filename.padEnd(28)} ${r.command?.padEnd(25) || ""} ${inst}`);
    } else {
      const status = r.passed ? "✓" : (r.skipped ? "⊙" : "✗");
      const detail = r.skipped ? r.reason : (r.passed ? "PASS" : "FAIL");
      console.log(`  ${status} ${r.filename.padEnd(28)} ${detail}`);
    }
    results.push(r);
  }

  const elapsed = Date.now() - startTime;
  const passed = results.filter(r => r.passed).length;
  const failed = results.filter(r => !r.passed && !r.skipped).length;
  const skipped = results.filter(r => r.skipped).length;
  const valid = results.filter(r => r.valid !== undefined ? r.valid : r.passed).length;

  console.log(`\n╔════════════════════════════════════════════╗`);
  console.log(`║  Edge Cases Complete                      ║`);
  console.log(`║  Total: ${String(results.length).padEnd(34)}║`);
  if (options.dryRun) {
    console.log(`║  Validated: ${String(valid).padEnd(34)}║`);
    console.log(`║  Missing:  ${String(results.length - valid).padEnd(34)}║`);
  } else {
    console.log(`║  Passed: ${String(passed).padEnd(34)}║`);
    console.log(`║  Failed: ${String(failed).padEnd(34)}║`);
    console.log(`║  Skipped: ${String(skipped).padEnd(34)}║`);
  }
  console.log(`║  Time:   ${(elapsed / 1000).toFixed(1)}s`.padEnd(43) + "║");
  console.log(`╚════════════════════════════════════════════╝`);

  if (options.reportPath) {
    const report = {
      timestamp: new Date().toISOString(),
      mode: options.dryRun ? "dry-run" : "live",
      total: results.length,
      passed,
      failed,
      skipped,
      elapsedMs: elapsed,
      results,
    };
    fs.writeFileSync(options.reportPath, JSON.stringify(report, null, 2) + "\n");
    console.log(`\nReport written to: ${options.reportPath}`);
  }
}

// ── CLI Entry ────────────────────────────────────────────────────────────

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const options = {
    dryRun: args.includes("--dry-run"),
    timeoutMs: args.includes("--timeout") ? parseInt(args[args.indexOf("--timeout") + 1], 10) : 15000,
    reportPath: args.includes("--report") ? args[args.indexOf("--report") + 1] : null,
  };

  if (args.includes("--list")) {
    const files = listEdgeCases();
    console.log(`Edge cases (${files.length}):\n`);
    for (const f of files) {
      const filepath = path.join(EDGE_DIR, f);
      const yaml = fs.readFileSync(filepath, "utf-8");
      const meta = parseMeta(yaml);
      const cmd = parseCommand(yaml);
      const inst = resolveBinary(cmd || "") ? "✓" : "✗";
      console.log(`  ${inst} ${f.replace(".yaml", "").padEnd(30)} ${meta.description}`);
    }
  } else if (args.includes("--case") && args[args.indexOf("--case") + 1]) {
    const caseName = args[args.indexOf("--case") + 1];
    const filename = caseName.endsWith(".yaml") ? caseName : `${caseName}.yaml`;
    const r = await runEdgeCase(filename, options);
    console.log(JSON.stringify(r, null, 2));
  } else {
    await runAll(options);
  }
}

export { runAll, runEdgeCase, listEdgeCases, resolveBinary };

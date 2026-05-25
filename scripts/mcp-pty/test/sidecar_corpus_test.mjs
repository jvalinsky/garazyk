/**
 * End-to-end test: YAML scenario runner through the Rust sidecar PTY pipeline.
 *
 * Verifies that the corpus runner's --sidecar flag correctly wires
 * createSidecarPtyFactory → TerminalSessionManager → scenario execution.
 *
 * The sidecar binary must be built beforehand:
 *   cargo build --manifest-path scripts/mcp-pty-rs/Cargo.toml
 */

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const sidecarBinary = path.resolve(
  __dirname, "..", "..", "mcp-pty-rs", "target", "debug", "garazyk-ptyd",
);
const binaryExists = fs.existsSync(sidecarBinary);

/** @type {import("../sidecar.mjs").SidecarManager} */
let sidecarManager;

test.before(async () => {
  if (!binaryExists) return;
  const { getSidecarManager } = await import("../sidecar.mjs");
  sidecarManager = getSidecarManager(sidecarBinary);
  sidecarManager._ensureStarted();
});

test.after(async () => {
  if (sidecarManager) {
    await sidecarManager.shutdown();
  }
});

test("sidecar binary is present", () => {
  assert.ok(
    binaryExists,
    `sidecar binary not found at ${sidecarBinary} — run cargo build first`,
  );
});

test(
  "corpus runner executes /bin/cat scenario through sidecar → snapshot → semantic snapshot",
  { skip: !binaryExists },
  async () => {
    // Write a minimal scenario to a temp file
    const tmpDir = fs.mkdtempSync(
      path.join(os.tmpdir(), "garazyk-pty-sidecar-corpus-"),
    );
    const scenarioPath = path.join(tmpDir, "cat_sidecar.yaml");
    fs.writeFileSync(
      scenarioPath,
      [
        "name: cat-sidecar-smoke",
        "description: Smoke test /bin/cat through sidecar-backed PTY",
        "command: /bin/cat",
        "cols: 40",
        "rows: 5",
        "settleMs: 100",
        "steps:",
        "  - type: wait",
        "    timeoutMs: 200",
        "    label: Wait for cat ready",
        "  - type: observe",
        "    label: Take initial snapshot",
        "  - type: type",
        "    value: 'hello-sidecar\\r'",
        "    label: Type text",
        "  - type: wait",
        "    timeoutMs: 300",
        "    label: Wait for echo",
        "  - type: assert_content_changed",
        "    label: Verify echo appeared",
      ].join("\n") + "\n",
    );

    try {
      const { runScenario } = await import("../corpus/runner.mjs");

      // Run through sidecar. The runner sets GARAZYK_PTY_MCP_ALLOW
      // to the resolved command path, so /bin/cat is allowed.
      const report = await runScenario(scenarioPath, {
        sidecar: true,
        stopOnFailure: true,
      });

      assert.equal(report.overall, "PASS", `Expected PASS, got: ${JSON.stringify(report.results)}`);
      assert.ok(report.stepsTotal >= 2, "should have executed multiple steps");
      assert.equal(report.stepsFailed, 0, "no steps should fail");

      // Verify the observe step captured a snapshot
      const observeStep = report.results.find((r) => r.label === "Take initial snapshot");
      assert.ok(observeStep, "should have observe step");
      assert.ok(observeStep.passed, "observe step should pass");

      // Verify echo appeared (content changed after typing)
      const changedStep = report.results.find((r) => r.label === "Verify echo appeared");
      assert.ok(changedStep, "should have assert_content_changed step");
      assert.ok(changedStep.passed, "content should have changed after typing text into cat");
    } finally {
      try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch {}
    }
  },
);

test(
  "corpus runner with sidecar produces a semantic snapshot with TuiWorld",
  { skip: !binaryExists },
  async () => {
    const tmpDir = fs.mkdtempSync(
      path.join(os.tmpdir(), "garazyk-pty-sidecar-world-"),
    );
    const scenarioPath = path.join(tmpDir, "cat_world.yaml");
    fs.writeFileSync(
      scenarioPath,
      [
        "name: cat-world-test",
        "description: Verify TuiWorld graph is produced through sidecar",
        "command: /bin/cat",
        "cols: 40",
        "rows: 5",
        "settleMs: 100",
        "steps:",
        "  - type: wait",
        "    timeoutMs: 200",
        "    label: Wait for ready",
        "  - type: type",
        "    value: 'hello-world\r'",
        "    label: Type text",
        "  - type: wait",
        "    timeoutMs: 300",
        "    label: Wait for echo",
        "  - type: observe",
        "    label: Get world",
      ].join("\n") + "\n",
    );

    try {
      const { runScenario } = await import("../corpus/runner.mjs");
      const report = await runScenario(scenarioPath, {
        sidecar: true,
        stopOnFailure: true,
      });

      assert.equal(
        report.overall,
        "PASS",
        `Expected PASS, got failures: ${
          JSON.stringify(report.results.filter((r) => !r.passed))
        }`,
      );

      // The observe step captures a semantic snapshot including TuiWorld
      const observeStep = report.results.find((r) => r.label === "Get world");
      assert.ok(observeStep, "should have observe step");
      assert.ok(observeStep.passed, "observe step should pass");
      assert.ok(observeStep.detail, "observe step should have detail");
    } finally {
      try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch {}
    }
  },
);

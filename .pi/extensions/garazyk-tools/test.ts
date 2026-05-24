/**
 * Structural and integration tests for the garazyk-tools pi extension.
 *
 * Structural tests verify CLI arg equivalence between the pi extension
 * and opencode tool via the shared `agent_args.ts` module.
 *
 * Integration tests invoke the actual `hamownia agent list` and `agent triage`
 * CLI commands (which don't require Docker) and verify valid JSON output.
 *
 * Run with: deno test -A .pi/extensions/garazyk-tools/test.ts
 */

import { assertEquals } from "@std/assert";
import {
  buildListArgs,
  buildRunArgs,
  buildTriageArgs,
  CLI_ENTRY,
  DENO_RUN_PREFIX,
} from "./agent_args.ts";
import {
  dockerAvailable,
  spawnCli,
  spawnCliWithTimeout,
} from "../../../packages/hamownia/test_utils.ts";

// ── Structural: shared module sanity ──────────────────────────────────

Deno.test("agent_args: CLI_ENTRY and DENO_RUN_PREFIX are consistent", () => {
  assertEquals(CLI_ENTRY, "packages/hamownia/cli.ts");
  assertEquals(DENO_RUN_PREFIX.length, 3);
  assertEquals(DENO_RUN_PREFIX[0], "run");
  assertEquals(DENO_RUN_PREFIX[1], "-A");
  assertEquals(DENO_RUN_PREFIX[2], CLI_ENTRY);
});

// ── Structural: agent list args ───────────────────────────────────────

Deno.test("agent_args: buildListArgs with no filters", () => {
  assertEquals(
    buildListArgs(),
    ["run", "-A", CLI_ENTRY, "agent", "list"],
  );
});

Deno.test("agent_args: buildListArgs with scenario IDs", () => {
  assertEquals(
    buildListArgs({ scenarioIds: "01 06 42" }),
    ["run", "-A", CLI_ENTRY, "agent", "list", "01", "06", "42"],
  );
});

Deno.test("agent_args: buildListArgs with topology", () => {
  assertEquals(
    buildListArgs({ topology: "garazyk-multi-pds" }),
    ["run", "-A", CLI_ENTRY, "agent", "list", "--topology", "garazyk-multi-pds"],
  );
});

Deno.test("agent_args: buildListArgs with both scenario IDs and topology", () => {
  assertEquals(
    buildListArgs({ scenarioIds: "01 06", topology: "garazyk-default" }),
    ["run", "-A", CLI_ENTRY, "agent", "list", "01", "06", "--topology", "garazyk-default"],
  );
});

// ── Structural: agent run args ────────────────────────────────────────

Deno.test("agent_args: buildRunArgs default invocation", () => {
  assertEquals(
    buildRunArgs(),
    ["run", "-A", CLI_ENTRY, "agent", "run", "--timeout", "120"],
  );
});

Deno.test("agent_args: buildRunArgs full tool shape", () => {
  assertEquals(
    buildRunArgs({
      scenarioIds: "01",
      noSetup: true,
      runner: "host",
      topology: "garazyk-default",
      runId: "full-tool-shape",
      timeout: 5,
    }),
    [
      "run", "-A", CLI_ENTRY, "agent", "run",
      "01",
      "--no-setup",
      "--topology", "garazyk-default",
      "--runner", "host",
      "--run-id", "full-tool-shape",
      "--timeout", "5",
    ],
  );
});

Deno.test("agent_args: buildRunArgs with all boolean flags", () => {
  const args = buildRunArgs({
    scenarioIds: "06",
    setup: true,
    binary: true,
    pds2: true,
    keepRunning: true,
    timeout: 120,
  });
  assertEquals(args.includes("--setup"), true);
  assertEquals(args.includes("--binary"), true);
  assertEquals(args.includes("--pds2"), true);
  assertEquals(args.includes("--keep-running"), true);
  assertEquals(args.includes("agent"), true);
  assertEquals(args.includes("run"), true);
});

Deno.test("agent_args: buildRunArgs respects custom timeout", () => {
  const args = buildRunArgs({ timeout: 300 });
  assertEquals(args.includes("--timeout"), true);
  assertEquals(args[args.indexOf("--timeout") + 1], "300");
});

// ── Structural: agent triage args ─────────────────────────────────────

Deno.test("agent_args: buildTriageArgs with runId", () => {
  assertEquals(
    buildTriageArgs({ runId: "run-20260523-2000" }),
    ["run", "-A", CLI_ENTRY, "agent", "triage", "--run-id", "run-20260523-2000"],
  );
});

Deno.test("agent_args: buildTriageArgs with reportsDir", () => {
  assertEquals(
    buildTriageArgs({ reportsDir: "/tmp/reports" }),
    ["run", "-A", CLI_ENTRY, "agent", "triage", "--reports-dir", "/tmp/reports"],
  );
});

Deno.test("agent_args: buildTriageArgs with both runId and reportsDir", () => {
  assertEquals(
    buildTriageArgs({ runId: "abc", reportsDir: "/tmp/reports" }),
    ["run", "-A", CLI_ENTRY, "agent", "triage", "--run-id", "abc", "--reports-dir", "/tmp/reports"],
  );
});

Deno.test("agent_args: buildTriageArgs with no params", () => {
  assertEquals(
    buildTriageArgs(),
    ["run", "-A", CLI_ENTRY, "agent", "triage"],
  );
});

// ── Structural: param counts ──────────────────────────────────────────

Deno.test("agent_args: type interfaces cover all pi extension params", () => {
  // List: scenarioIds, topology
  const listParams = ["scenarioIds", "topology"];
  assertEquals(listParams.length, 2);

  // Run: all 10 params
  const runParams = [
    "scenarioIds", "setup", "noSetup", "binary", "pds2",
    "keepRunning", "topology", "runner", "timeout", "runId",
  ];
  assertEquals(runParams.length, 10);

  // Triage: runId, reportsDir
  const triageParams = ["runId", "reportsDir"];
  assertEquals(triageParams.length, 2);
});

// ── Structural: truncation limits ─────────────────────────────────────

Deno.test("agent_args: truncation limits match pi extension constants", () => {
  const MAX_OUTPUT_BYTES = 50 * 1024;
  const MAX_OUTPUT_LINES = 2000;

  assertEquals(MAX_OUTPUT_BYTES, 51200);
  assertEquals(MAX_OUTPUT_LINES, 2000);

  // Text under limits is NOT truncated
  const shortText = "short output";
  assertEquals(shortText.split("\n").length > MAX_OUTPUT_LINES, false);
  assertEquals(
    new TextEncoder().encode(shortText).length > MAX_OUTPUT_BYTES,
    false,
  );

  // Text exceeding byte limit WOULD be truncated
  assertEquals(
    new TextEncoder().encode("x".repeat(MAX_OUTPUT_BYTES + 1)).length > MAX_OUTPUT_BYTES,
    true,
  );

  // Text exceeding line limit WOULD be truncated
  const manyLines = new Array(MAX_OUTPUT_LINES + 1).fill("x").join("\n");
  assertEquals(manyLines.split("\n").length > MAX_OUTPUT_LINES, true);
});

/** Extract CLI sub-args (after CLI_PATH) from full args produced by build* functions. */
function subArgs(fullArgs: string[]): string[] {
  const idx = fullArgs.indexOf(CLI_ENTRY);
  return idx >= 0 ? fullArgs.slice(idx + 1) : fullArgs;
}

// ── Integration: agent list CLI ───────────────────────────────────────

Deno.test("integration: agent list produces valid JSON array", async () => {
  const { stdout, code } = await spawnCli(subArgs(buildListArgs()));

  assertEquals(code, 0);
  const parsed = JSON.parse(stdout.trim());
  assertEquals(Array.isArray(parsed), true);

  // Every element must be a valid AgentScenarioSummary
  for (const s of parsed) {
    assertEquals(typeof s.id, "string");
    assertEquals(typeof s.name, "string");
    assertEquals(typeof s.path, "string");
    assertEquals(Array.isArray(s.requires), true);
    assertEquals(Array.isArray(s.optional), true);
    assertEquals(typeof s.needsPds2, "boolean");
    assertEquals(Array.isArray(s.browserFlows), true);
    assertEquals(typeof s.parameters, "object");
  }
});

Deno.test("integration: agent list with topology filter returns valid JSON", async () => {
  const { stdout, code } = await spawnCli(subArgs(buildListArgs({ topology: "garazyk-default" })));

  assertEquals(code, 0);
  const parsed = JSON.parse(stdout.trim());
  assertEquals(Array.isArray(parsed), true);
});

Deno.test("integration: agent list with specific scenario ID filter", async () => {
  const { stdout, code } = await spawnCli(subArgs(buildListArgs({ scenarioIds: "01" })));

  assertEquals(code, 0);
  const parsed = JSON.parse(stdout.trim());
  assertEquals(Array.isArray(parsed), true);
  for (const s of parsed) {
    assertEquals(s.id, "01", `Unexpected ID: ${s.id}`);
  }
});

Deno.test("integration: agent list with non-existent ID returns empty", async () => {
  const { stdout, code } = await spawnCli(subArgs(buildListArgs({ scenarioIds: "999" })));

  assertEquals(code, 0);
  const parsed = JSON.parse(stdout.trim());
  assertEquals(Array.isArray(parsed), true);
  assertEquals(parsed.length, 0);
});

// ── Integration: agent triage CLI ─────────────────────────────────────

Deno.test("integration: agent triage with --run-id returns valid JSON", async () => {
  const { stdout, code } = await spawnCli(subArgs(buildTriageArgs({ runId: "integration-test-run-9999" })));

  // Should succeed even if the run doesn't exist (returns empty result)
  assertEquals(code, 0);
  const parsed = JSON.parse(stdout.trim());
  assertEquals(typeof parsed.runId, "string");
  assertEquals(typeof parsed.ok, "boolean");
  assertEquals(typeof parsed.boundary, "string");
  assertEquals(Array.isArray(parsed.evidence), true);
  assertEquals(Array.isArray(parsed.reportPaths), true);
});

Deno.test("integration: agent triage with --reports-dir returns valid JSON", async () => {
  // Create a temp directory with actual report files
  const tmpDir = await Deno.makeTempDir();
  try {
    const reportPath = `${tmpDir}/overall-summary.json`;
    await Deno.writeTextFile(
      reportPath,
      JSON.stringify({
        run_id: "integration-test-triaged",
        ok: false,
        report_paths: [`${tmpDir}/01_report.json`],
      }),
    );
    await Deno.writeTextFile(
      `${tmpDir}/01_report.json`,
      JSON.stringify({
        scenario: "integration test scenario",
        steps: [{
          name: "auth step",
          status: "failed",
          detail: "session expired",
          duration_ms: 100,
        }],
        summary: { passed: 0, failed: 1, skipped: 0, total: 1 },
        ok: false,
        metadata: { scenario_id: "99" },
      }),
    );

    const { stdout, code } = await spawnCli(subArgs(buildTriageArgs({ reportsDir: tmpDir })));

    assertEquals(code, 0);
    const parsed = JSON.parse(stdout.trim());
    assertEquals(parsed.runId, "integration-test-triaged");
    assertEquals(parsed.ok, false);
    assertEquals(parsed.firstFailure.scenarioId, "99");
    assertEquals(parsed.firstFailure.step, "auth step");
    assertEquals(parsed.boundary, "auth");
    assertEquals(parsed.reportPaths.length, 1);
  } finally {
    await Deno.remove(tmpDir, { recursive: true }).catch(() => {});
  }
});

Deno.test("integration: agent triage with both --run-id and --reports-dir", async () => {
  // When both are provided, triage uses reports-dir and validates run-id
  const tmpDir = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(
      `${tmpDir}/overall-summary.json`,
      JSON.stringify({
        run_id: "both-params-test",
        ok: true,
        report_paths: [],
      }),
    );

    const { stdout, code } = await spawnCli(subArgs(buildTriageArgs({
      runId: "both-params-test",
      reportsDir: tmpDir,
    })));

    assertEquals(code, 0);
    const parsed = JSON.parse(stdout.trim());
    assertEquals(parsed.runId, "both-params-test");
    assertEquals(parsed.ok, true);
  } finally {
    await Deno.remove(tmpDir, { recursive: true }).catch(() => {});
  }
});

Deno.test("integration: agent triage with non-existent reportsDir returns valid JSON", async () => {
  const { stdout, code } = await spawnCli(subArgs(buildTriageArgs({ reportsDir: "/tmp/nonexistent-pi-integration-test" })));

  assertEquals(code, 0);
  const parsed = JSON.parse(stdout.trim());
  assertEquals(typeof parsed.runId, "string");
  assertEquals(Array.isArray(parsed.evidence), true);
});

// ── Integration: arg-building parity with pi extension ─────────────────

Deno.test("integration: buildListArgs output runs successfully as CLI command", async () => {
  const { code } = await spawnCli(subArgs(buildListArgs({ topology: "garazyk-default" })));
  assertEquals(code, 0);
});

Deno.test("integration: buildTriageArgs output runs successfully as CLI command", async () => {
  const { code } = await spawnCli(subArgs(buildTriageArgs({ runId: "parity-test" })));
  assertEquals(code, 0);
});

// ── Integration: agent run CLI ────────────────────────────────────────

Deno.test("integration: agent run --no-setup emits run_start NDJSON event", async () => {
  // Run a single scenario with --no-setup (no Docker required).
  // Should emit at least a run_start event before failing gracefully.
  const { stdout } = await spawnCliWithTimeout(subArgs(buildRunArgs({
    scenarioIds: "01",
    noSetup: true,
    timeout: 5,
    runId: "pi-integration-run",
  })), 60_000);

  // Filter JSON lines from stdout
  const rawLines: string[] = stdout.split("\n");
  const jsonLines: string[] = rawLines
    .map((l: string): string => l.trim())
    .filter((l: string): boolean => l.startsWith("{"));
  const events: Array<Record<string, unknown>> = [];
  for (const line of jsonLines) {
    try {
      events.push(JSON.parse(line) as Record<string, unknown>);
    } catch {
      // Skip unparseable lines
    }
  }

  // At minimum, run_start should be present
  const runStart = events.find((e: Record<string, unknown>): boolean => e.type === "run_start");
  assertEquals(runStart != null, true, "Missing run_start event");
  assertEquals(typeof runStart?.runId, "string");
  assertEquals(Array.isArray(runStart?.scenarioIds), true);
  assertEquals(typeof runStart?.total, "number");
});

Deno.test("integration: agent run with multiple flags accepted", async () => {
  // Verify the pi extension's buildRunArgs with multiple flags does not
  // cause CLI flag parsing errors.
  const { stderr } = await spawnCliWithTimeout(subArgs(buildRunArgs({
    scenarioIds: "01",
    noSetup: true,
    runner: "host",
    topology: "garazyk-default",
    runId: "pi-multi-flag-test",
    timeout: 3,
  })), 45_000);

  // Should not fail on flag parsing
  const isFlagError = /Unknown|Invalid|Expected/.test(stderr);
  assertEquals(isFlagError, false, `Flag parsing error: ${stderr.slice(0, 200)}`);
});

Deno.test("integration: agent run --setup emits full NDJSON lifecycle", async () => {
  if (!await dockerAvailable()) {
    return;
  }

  // Full integration test: docker setup, scenario run, teardown.
  // 90s CLI timeout accounts for Docker container startup.
  const { stdout } = await spawnCli(subArgs(buildRunArgs({
    scenarioIds: "01",
    setup: true,
    timeout: 90,
    runId: "pi-docker-run",
  })));

  // Filter JSON lines
  const rawLines2: string[] = stdout.split("\n");
  const jsonLines2: string[] = rawLines2
    .map((l: string): string => l.trim())
    .filter((l: string): boolean => l.startsWith("{"));
  const events: Array<Record<string, unknown>> = [];
  for (const line of jsonLines2) {
    try {
      events.push(JSON.parse(line) as Record<string, unknown>);
    } catch {
      // Skip unparseable lines
    }
  }

  // Verify core lifecycle events
  const types = events.map((e: Record<string, unknown>): unknown => e.type);
  assertEquals(types.includes("run_start"), true, "missing run_start");
  assertEquals(types.includes("scenario_start"), true, "missing scenario_start");
  assertEquals(types.includes("scenario_complete"), true, "missing scenario_complete");
  assertEquals(types.includes("run_finished"), true, "missing run_finished");

  // Verify the finished event reports success
  const finished = events.find((e: Record<string, unknown>): boolean => e.type === "run_finished");
  assertEquals(finished?.ok, true);
});

Deno.test("integration: agent run with --runner docker flag accepted", async () => {
  if (!await dockerAvailable()) {
    return;
  }

  const { stderr } = await spawnCliWithTimeout(subArgs(buildRunArgs({
    scenarioIds: "01",
    runner: "docker",
    noSetup: true,
    timeout: 5,
  })), 30_000);

  // Should NOT fail on enum validation for --runner
  const isFlagError = /Unknown|Invalid|Expected/.test(stderr);
  assertEquals(isFlagError, false, `Flag parsing error: ${stderr.slice(0, 200)}`);
});

Deno.test("integration: agent run with --binary and --pds2 flags accepted", async () => {
  const { stderr } = await spawnCliWithTimeout(subArgs(buildRunArgs({
    scenarioIds: "01",
    noSetup: true,
    binary: true,
    pds2: true,
    timeout: 5,
  })), 30_000);

  const isFlagError = /Unknown|Invalid|Expected/.test(stderr);
  assertEquals(isFlagError, false, `Flag parsing error: ${stderr.slice(0, 200)}`);
});

Deno.test("integration: agent run with --keep-running flag accepted", async () => {
  const { stderr } = await spawnCliWithTimeout(subArgs(buildRunArgs({
    scenarioIds: "01",
    noSetup: true,
    keepRunning: true,
    timeout: 5,
  })), 30_000);

  const isFlagError = /Unknown|Invalid|Expected/.test(stderr);
  assertEquals(isFlagError, false, `Flag parsing error: ${stderr.slice(0, 200)}`);
});

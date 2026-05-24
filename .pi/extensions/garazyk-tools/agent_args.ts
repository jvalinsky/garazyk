/**
 * Shared CLI arg-building functions for hamownia agent subcommands.
 *
 * Used by both the pi extension (index.ts) and its structural/integration
 * tests (test.ts) to ensure CLI arg construction stays in sync.
 *
 * These are pure functions — no Node.js or Deno-specific dependencies.
 */

/** CLI entry point for all hamownia agent subcommands. */
export const CLI_ENTRY = "packages/hamownia/cli.ts";

/** Base args prefix for all deno invocations. */
export const DENO_RUN_PREFIX = ["run", "-A", CLI_ENTRY] as const;

// ── agent list ────────────────────────────────────────────────────────

export interface ListArgs {
  /** Space-separated scenario IDs, e.g. "01 06 42". */
  scenarioIds?: string;
  /** Topology preset name. */
  topology?: string;
}

/** Build CLI args for `hamownia agent list`. */
export function buildListArgs(params: ListArgs = {}): string[] {
  const args: string[] = [...DENO_RUN_PREFIX, "agent", "list"];
  if (params.scenarioIds) {
    args.push(...params.scenarioIds.trim().split(/\s+/));
  }
  if (params.topology) {
    args.push("--topology", params.topology);
  }
  return args;
}

// ── agent run ─────────────────────────────────────────────────────────

export interface RunArgs {
  /** Space-separated scenario IDs, e.g. "01 06". */
  scenarioIds?: string;
  /** Start the local network before running. */
  setup?: boolean;
  /** Run against an already-running network (mutually exclusive with setup). */
  noSetup?: boolean;
  /** Start services from build/bin instead of Docker. */
  binary?: boolean;
  /** Include the second PDS instance. */
  pds2?: boolean;
  /** Leave services running after execution. */
  keepRunning?: boolean;
  /** Topology preset name. */
  topology?: string;
  /** Scenario runner mode: "host" or "docker". */
  runner?: string;
  /** Per-scenario timeout in seconds. */
  timeout?: number;
  /** Reuse or name the e2e run directory. */
  runId?: string;
}

/** Build CLI args for `hamownia agent run`. */
export function buildRunArgs(params: RunArgs = {}): string[] {
  const args: string[] = [...DENO_RUN_PREFIX, "agent", "run"];
  if (params.scenarioIds) {
    args.push(...params.scenarioIds.trim().split(/\s+/));
  }
  if (params.setup) args.push("--setup");
  if (params.noSetup) args.push("--no-setup");
  if (params.binary) args.push("--binary");
  if (params.pds2) args.push("--pds2");
  if (params.keepRunning) args.push("--keep-running");
  if (params.topology) args.push("--topology", params.topology);
  if (params.runner) args.push("--runner", params.runner);
  if (params.runId) args.push("--run-id", params.runId);
  args.push("--timeout", String(params.timeout ?? 120));
  return args;
}

// ── agent triage ──────────────────────────────────────────────────────

export interface TriageArgs {
  /** Run identifier to triage. */
  runId?: string;
  /** Path to directory containing report JSON files. */
  reportsDir?: string;
}

/** Build CLI args for `hamownia agent triage`. */
export function buildTriageArgs(params: TriageArgs = {}): string[] {
  const args: string[] = [...DENO_RUN_PREFIX, "agent", "triage"];
  if (params.runId) args.push("--run-id", params.runId);
  if (params.reportsDir) args.push("--reports-dir", params.reportsDir);
  return args;
}

/** OpenCode tool: programmatic scenario discovery, execution, and triage via hamownia agent. */
import { tool } from "@opencode-ai/plugin"

const HAMOWNIA_CLI = "packages/hamownia/cli.ts"

/** Run the hamownia agent command and return its stdout (JSON/NDJSON). */
async function runAgent(
  cwd: string,
  subcommand: string,
  args: string[],
  timeoutMs = 600_000,
): Promise<string> {
  const proc = Bun.spawn(
    ["deno", "run", "-A", HAMOWNIA_CLI, "agent", subcommand, ...args],
    {
      cwd,
      stdout: "pipe",
      stderr: "pipe",
    },
  )

  const timer = setTimeout(() => {
    proc.kill(9)
  }, timeoutMs)

  const stdout = await new Response(proc.stdout).text()
  const stderr = await new Response(proc.stderr).text()
  const exitCode = await proc.exited
  clearTimeout(timer)

  if (exitCode !== 0) {
    return `Error (exit ${exitCode}):\n${stderr}\n${stdout}`
  }

  return stdout.trim() || stderr.trim() || "(no output)"
}

export default tool({
  description:
    "Discover, run, and triage Garazyk ATProto e2e scenarios via the machine-readable hamownia agent CLI. " +
    "All output on stdout is guaranteed valid JSON or NDJSON. " +
    "Subcommands: list (discover scenarios), run (execute with NDJSON events), triage (parse failure reports).",
  args: {
    command: tool.schema
      .enum(["list", "run", "triage"])
      .describe(
        "Subcommand: list (discover scenarios as JSON array), run (execute with NDJSON events on stdout), triage (parse existing reports without starting services)",
      ),
    scenarioIds: tool.schema
      .string()
      .optional()
      .describe(
        'Space-separated scenario IDs to filter, e.g. "01 06 42". Omit to run all compatible scenarios.',
      ),
    topology: tool.schema
      .string()
      .optional()
      .describe(
        "Topology preset name for filtering (list/run). Available: garazyk-default, garazyk-multi-pds, etc.",
      ),
    setup: tool.schema
      .boolean()
      .default(false)
      .describe("Explicitly start the local network before running (run only)."),
    noSetup: tool.schema
      .boolean()
      .default(false)
      .describe(
        "Run against an already-running network without setup (run only).",
      ),
    binary: tool.schema
      .boolean()
      .default(false)
      .describe("Start services from build/bin instead of Docker (run only)."),
    pds2: tool.schema
      .boolean()
      .default(false)
      .describe("Include the second PDS instance (run only)."),
    keepRunning: tool.schema
      .boolean()
      .default(false)
      .describe(
        "Leave services running after execution completes (run only).",
      ),
    verbose: tool.schema
      .boolean()
      .default(false)
      .describe("Also write human-readable progress to stderr (run only)."),
    runner: tool.schema
      .enum(["host", "docker"])
      .default("host")
      .describe("Scenario runner mode: host or docker (run only)."),
    timeout: tool.schema
      .number()
      .default(120)
      .describe("Per-scenario timeout in seconds (run only)."),
    runId: tool.schema
      .string()
      .optional()
      .describe(
        "Run identifier to reuse or name the e2e run directory (run/triage).",
      ),
    reportsDir: tool.schema
      .string()
      .optional()
      .describe(
        "Path to directory containing report JSON files (triage only).",
      ),
  },
  async execute(args, context) {
    const cwd = context.worktree || context.directory
    const cmdArgs: string[] = []

    switch (args.command) {
      case "list": {
        // scenarioIds is optional filter for list
        if (args.scenarioIds) {
          const ids = args.scenarioIds.trim().split(/\s+/)
          cmdArgs.push(...ids)
        }
        if (args.topology) cmdArgs.push("--topology", args.topology)
        return await runAgent(cwd, "list", cmdArgs)
      }

      case "run": {
        if (args.scenarioIds) {
          const ids = args.scenarioIds.trim().split(/\s+/)
          cmdArgs.push(...ids)
        }
        if (args.setup) cmdArgs.push("--setup")
        if (args.noSetup) cmdArgs.push("--no-setup")
        if (args.binary) cmdArgs.push("--binary")
        if (args.pds2) cmdArgs.push("--pds2")
        if (args.keepRunning) cmdArgs.push("--keep-running")
        if (args.verbose) cmdArgs.push("--verbose")
        if (args.runner) cmdArgs.push("--runner", args.runner)
        if (args.topology) cmdArgs.push("--topology", args.topology)
        if (args.runId) cmdArgs.push("--run-id", args.runId)
        cmdArgs.push("--timeout", String(args.timeout ?? 120))
        // Use the default 10m timeout as baseline; let larger per-scenario timeouts raise it.
        const procTimeout = Math.max(
          600_000,
          ((args.timeout ?? 120) + 60) * 1000,
        )
        return await runAgent(cwd, "run", cmdArgs, procTimeout)
      }

      case "triage": {
        if (args.runId) cmdArgs.push("--run-id", args.runId)
        if (args.reportsDir) cmdArgs.push("--reports-dir", args.reportsDir)
        return await runAgent(cwd, "triage", cmdArgs)
      }

      default:
        return `Unknown command: ${args.command}. Use list, run, or triage.`
    }
  },
})

/** OpenCode tool: start/stop the full local ATProto service stack with optional seeding. */
import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "Start full local ATProto stack (PLC, PDS, Relay, AppView, Chat, Video, UI) with optional seeding. Wraps scripts/full_suite_demo.sh.",
  args: {
    action: tool.schema.enum(["start", "stop"]).default("start").describe("Start the full suite or stop a running instance"),
    skipSeed: tool.schema.boolean().default(false).describe("Skip the XRPC seeding phase"),
    keepRunning: tool.schema.boolean().default(false).describe("Keep services running after seeding"),
    runId: tool.schema.string().optional().describe("Explicit run ID (for resuming/stopping a specific instance)"),
    collectDiagnostics: tool.schema.boolean().default(false).describe("Collect health diagnostics from all services"),
  },
  async execute(args, context) {
    const worktree = context.worktree
    const script = `${worktree}/scripts/full_suite_demo.sh`

    const cmd = [script]

    if (args.action === "stop") {
      cmd.push("--stop")
      if (args.runId) cmd.push("--run-id", args.runId)
    } else {
      if (args.skipSeed) cmd.push("--skip-seed")
      if (args.keepRunning) cmd.push("--keep-running")
      if (args.runId) cmd.push("--run-id", args.runId)
      if (args.collectDiagnostics) cmd.push("--collect-diagnostics")
    }

    try {
      const result = await Bun.$`${cmd}`.cwd(worktree).text()
      return result.trim()
    } catch (e) {
      const stderr = e.stderr?.toString().trim() || ""
      const stdout = e.stdout?.toString().trim() || ""
      return `COMMAND FAILED:\n${stdout}\n${stderr}`
    }
  },
})

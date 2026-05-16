/** OpenCode tool: control local ATProto services (start, stop, restart, status, logs, etc.). */
import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "Control local ATProto services: start, stop, restart, check status, follow logs. Wraps scripts/services-control.sh and scripts/start-all-services.sh.",
  args: {
    command: tool.schema.enum(["start", "stop", "restart", "status", "logs", "follow", "test", "clean"]).describe("Operation to perform"),
    target: tool.schema.enum(["all", "plc", "pds", "relay", "appview", "chat", "video", "ui"]).default("all").describe("Which service to target"),
    lines: tool.schema.number().default(50).describe("Number of log lines (logs command only)"),
    skipHealthChecks: tool.schema.boolean().default(false).describe("Skip health check validation on start"),
  },
  async execute(args, context) {
    const worktree = context.worktree

    if (args.command === "start") {
      const script = `${worktree}/scripts/start-all-services.sh`
      const cmd = [script]
      if (args.skipHealthChecks) cmd.push("--skip-health-checks")
      if (args.target !== "all") cmd.push(`--skip-${args.target}`)
      try {
        const result = await Bun.$`${cmd}`.cwd(worktree).text()
        return result.trim()
      } catch (e) {
        return `FAILED:\n${e.stderr?.toString().trim() || e.stdout?.toString().trim() || e}`
      }
    }

    const script = `${worktree}/scripts/services-control.sh`
    const cmd = [script, args.command, args.target]
    if (args.command === "logs") cmd.push(String(args.lines))

    try {
      const result = await Bun.$`${cmd}`.cwd(worktree).text()
      return result.trim()
    } catch (e) {
      return `FAILED:\n${e.stderr?.toString().trim() || e.stdout?.toString().trim() || e}`
    }
  },
})

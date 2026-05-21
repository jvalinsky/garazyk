/** OpenCode tool: control local ATProto services (start, stop, restart, status, logs, follow). */
import { tool } from "@opencode-ai/plugin"

const MANAGER = "scripts/manage_local_network.ts"

function deno(args: string[], cwd: string): Promise<string> {
  const cmd = new Deno.Command("deno", {
    args: ["run", "-A", MANAGER, ...args],
    cwd,
    stdout: "piped",
    stderr: "piped",
  })
  return cmd.output().then((r) => {
    const out = new TextDecoder().decode(r.stdout).trim()
    const err = new TextDecoder().decode(r.stderr).trim()
    if (!r.success) throw new Error(err || out)
    return out
  })
}

export default tool({
  description: "Control local ATProto services: start, stop, restart, check status, follow logs. Delegates to scripts/manage_local_network.ts.",
  args: {
    command: tool.schema.enum(["start", "stop", "restart", "status", "logs", "follow", "test", "clean"]).describe("Operation to perform"),
    target: tool.schema.enum(["all", "plc", "pds", "relay", "appview", "chat", "video", "ui"]).default("all").describe("Which service to target"),
    lines: tool.schema.number().default(50).describe("Number of log lines (logs command only)"),
    skipHealthChecks: tool.schema.boolean().default(false).describe("Skip health check validation on start"),
  },
  async execute(args, context) {
    const worktree = context.worktree

    switch (args.command) {
      case "start": {
        const flags = []
        if (args.target !== "all") flags.push(`--${args.target}-only`)
        if (args.skipHealthChecks) flags.push("--skip-health-checks")
        return deno([...flags], worktree)
      }
      case "stop":
        return deno(["--teardown"], worktree)
      case "status": {
        const cmd = new Deno.Command("docker", {
          args: ["ps", "--format", "table {{.Names}}\t{{.Status}}\t{{.Ports}}", "--filter", `name=garazyk-e2e`],
          stdout: "piped",
          stderr: "piped",
        })
        const r = await cmd.output()
        const out = new TextDecoder().decode(r.stdout).trim()
        const err = new TextDecoder().decode(r.stderr).trim()
        if (!r.success) return `FAILED:\n${err}`
        return out || "No services running."
      }
      case "logs": {
        const cmd = new Deno.Command("docker", {
          args: ["ps", "--format", "{{.Names}}", "--filter", `name=garazyk-e2e`],
          stdout: "piped",
        })
        const r = await cmd.output()
        const containers = new TextDecoder().decode(r.stdout).trim().split("\n")
        const logLines: string[] = []
        for (const c of containers) {
          const logCmd = new Deno.Command("docker", {
            args: ["logs", "--tail", String(args.lines), c],
            stdout: "piped",
            stderr: "piped",
          })
          const lr = await logCmd.output()
          const log = new TextDecoder().decode(lr.stdout).trim()
          if (log) logLines.push(`=== ${c} ===\n${log}`)
        }
        return logLines.join("\n\n") || "No logs found."
      }
      case "follow": {
        const target = args.target || "all"
        const filter = target === "all" ? "name=garazyk-e2e" : `name=${target}`
        const cmd = new Deno.Command("docker", {
          args: ["ps", "--format", "{{.Names}}", "--filter", filter],
          stdout: "piped",
        })
        const r = await cmd.output()
        const containers = new TextDecoder().decode(r.stdout).trim().split("\n")
        if (containers.length === 0) return "No matching containers."
        const processes = containers.map((c) =>
          new Deno.Command("docker", {
            args: ["logs", "-f", c],
            stdout: "inherit",
            stderr: "inherit",
          }).spawn()
        )
        await Promise.all(processes.map((p) => p.status))
        return "Done."
      }
      case "restart":
        await deno(["--teardown"], worktree)
        return deno([], worktree)
      case "test":
        return `Use "deno run -A scripts/run_scenarios.ts" directly.`
      case "clean": {
        const teardown = deno(["--teardown"], worktree)
        return teardown
      }
      default:
        return `Unknown command: ${args.command}`
    }
  },
})

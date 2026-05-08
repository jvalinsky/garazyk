import type { Plugin } from "@opencode-ai/plugin"

export const PushGuardPlugin: Plugin = async ({ project, client, $, worktree }) => {
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool === "bash" && /^git\s+push\b/.test(output.args.command)) {
        const testBinary = `${worktree}/build/tests/AllTests`
        let testStatus = "not built"
        try {
          const stat = await Bun.$`test -f ${testBinary} && stat -f '%Sm' ${testBinary}`.text()
          testStatus = `built, last modified: ${stat.trim()}`
        } catch {
          testStatus = "not built"
        }
        output.args.command = `echo "--- PushGuard: Test binary ${testStatus}. Consider running build-test first. ---" && ${output.args.command}`
      }
    },
  }
}

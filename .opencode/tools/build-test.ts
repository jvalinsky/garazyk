/** OpenCode tool: build and run XCTest tests (xcodegen -> xcodebuild -> test runner). */
import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "Build and run tests in one command. Runs xcodegen generate, xcodebuild, and scripts/test/run-tests.sh.",
  args: {
    scheme: tool.schema.string().default("AllTests").describe("Xcode scheme to build (default: AllTests)"),
    filter: tool.schema.string().optional().describe("Optional test filter, e.g. 'PDSHealthCheckTests' or 'PDSHealthCheckTests/testHealthCheckHealthy'"),
    skipBuild: tool.schema.boolean().default(false).describe("Skip xcodebuild phase, only run tests"),
  },
  async execute(args, context) {
    const worktree = context.worktree
    const results = []

    if (!args.skipBuild) {
      results.push("=== xcodegen generate ===")
      try {
        const genOut = await Bun.$`xcodegen generate`.cwd(worktree).text()
        results.push(genOut.trim() || "(ok)")
      } catch (e) {
        results.push(`XCODEGEN FAILED:\n${e}`)
        return results.join("\n")
      }

      results.push("\n=== xcodebuild ===")
      try {
        const buildOut = await Bun.$`xcodebuild -scheme ${args.scheme} build`.cwd(worktree).text()
        const lastLine = buildOut.trim().split("\n").pop() || ""
        results.push(lastLine)
      } catch (e) {
        results.push(`BUILD FAILED:\n${e}`)
        return results.join("\n")
      }
    }

    results.push("\n=== run-tests.sh ===")
    try {
      const testOut = await Bun.$`scripts/test/run-tests.sh`.cwd(worktree).text()
      results.push(testOut.trim())
    } catch (e) {
      const stderr = e.stderr?.toString().trim() || ""
      const stdout = e.stdout?.toString().trim() || ""
      results.push(`TESTS FAILED:\n${stdout}\n${stderr}`)
    }

    return results.join("\n")
  },
})

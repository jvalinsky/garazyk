import type { Plugin } from "@opencode-ai/plugin"

export const CompactionPlugin: Plugin = async ({ project, client }) => {
  await client.app.log({
    body: { service: "compaction", level: "info", message: "Compaction plugin initialized" },
  })

  return {
    "experimental.session.compacting": async (input, output) => {
      output.context.push(`## Project Context for Garazyk

This is an AT Protocol PDS implementation in Objective-C. Build system: CMake + XcodeGen.
Tests: XCTest with custom test_main.m runner at build/tests/AllTests.

Key conventions:
- Use out-of-source builds, run xcodegen generate before building
- Log decisions/actions in the deciduous graph
- Skills are in .agents/skills/ (loaded via use_skill tool)
- Custom tools are in .opencode/tools/

Available custom tools: build-test, find-test-class, seed-data, service-control`)
    },
  }
}

import { tool } from "@opencode-ai/plugin"

const TEST_MAIN_PATH = "Garazyk/Tests/test_main.m"

async function parseRegisteredClasses(worktree: string): Promise<string[]> {
  const text = await Bun.$`rg -o '(?<=@")[A-Za-z]+Tests(?=")' ${TEST_MAIN_PATH}`.cwd(worktree).text()
  return text.split("\n").map(s => s.trim()).filter(Boolean)
}

async function findTestMethods(worktree: string, className: string): Promise<string[]> {
  const file = await Bun.$`rg -l "\\b@implementation\\s+${className}\\b" Garazyk/Tests/`.cwd(worktree).text()
  if (!file.trim()) return []
  const methods = await Bun.$`rg -o '(?<=^[-+]\\s*\\(void\\))test\\w+' ${file.trim()}`.cwd(worktree).text()
  return methods.split("\n").map(s => s.trim()).filter(Boolean)
}

export default tool({
  description: "Search for XCTest test classes by name pattern. Shows registration status in test_main.m and file location.",
  args: {
    pattern: tool.schema.string().describe("Search pattern (substring, e.g. 'Health', 'PDS', 'OAuth')"),
    showMethods: tool.schema.boolean().default(false).describe("List test methods within matching classes"),
    unregistered: tool.schema.boolean().default(false).describe("Only show test classes NOT registered in test_main.m"),
  },
  async execute(args, context) {
    const worktree = context.worktree
    const pattern = args.pattern
    const results: string[] = []

    // Find test files on disk
    const fileMatches = await Bun.$`find Garazyk/Tests -name '*${pattern}*Tests.m' -o -name '*${pattern}*Tests.h' 2>/dev/null | sort`
      .cwd(worktree).text()
    const fileLines = fileMatches.split("\n").map(s => s.trim()).filter(Boolean)

    // Parse registered classes from test_main.m
    const registered = await parseRegisteredClasses(worktree)
    const matchingRegistered = registered.filter(c => c.toLowerCase().includes(pattern.toLowerCase()))

    // Extract class names from file paths
    const fileClassNames = new Set<string>()
    for (const file of fileLines) {
      const base = file.split("/").pop() || ""
      const name = base.replace(/\.(m|h)$/, "")
      fileClassNames.add(name)
    }

    // On-disk files not in registration
    const diskOnly = [...fileClassNames].filter(c => !registered.includes(c)).sort()

    // Registered but no file found
    const registeredOnly = matchingRegistered.filter(c => !fileClassNames.has(c)).sort()

    // Found in both
    const both = matchingRegistered.filter(c => fileClassNames.has(c)).sort()

    if (args.unregistered) {
      if (diskOnly.length === 0) {
        results.push("All test files matching that pattern are registered.")
      } else {
        results.push(`=== Unregistered test classes (${diskOnly.length}) ===`)
        for (const c of diskOnly) {
          const file = fileLines.find(f => f.includes(c))
          results.push(`  ${c} → ${file || "(no file)"}`)
        }
      }
      return results.join("\n")
    }

    results.push(`=== Registered + file found (${both.length}) ===`)
    for (const c of both) {
      const file = fileLines.find(f => f.includes(c))
      results.push(`  ✓ ${c} → ${file || "?"}`)
      if (args.showMethods) {
        const methods = await findTestMethods(worktree, c)
        for (const m of methods) results.push(`      - ${m}`)
      }
    }

    if (diskOnly.length > 0) {
      results.push(`\n=== Unregistered (${diskOnly.length}) — not in test_main.m ===`)
      for (const c of diskOnly) {
        const file = fileLines.find(f => f.includes(c))
        results.push(`  ✗ ${c} → ${file}`)
      }
    }

    if (registeredOnly.length > 0) {
      results.push(`\n=== Registered but no file (${registeredOnly.length}) ===`)
      for (const c of registeredOnly) results.push(`  ? ${c} — no .m/.h found`)
    }

    results.push(`\n--- Summary: ${both.length} registered + filed, ${diskOnly.length} unregistered, ${registeredOnly.length} stale registrations ---`)
    return results.join("\n")
  },
})

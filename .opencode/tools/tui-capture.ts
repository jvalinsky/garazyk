import { tool } from "@opencode-ai/plugin";
import path from "node:path";
import fs from "node:fs";

export default tool({
  description:
    "Capture Garazyk dashboard TUI interactions as HTML playback. " +
    "Runs the dashboard headlessly via VirtualTuiHarness, simulates keystrokes, " +
    "records as asciicast v2, and exports a standalone HTML page with Asciinema Player. " +
    "Supports preset scripts (demo, e2e), indexed scenarios (0-based flat list), " +
    "and custom ReplayStep sequences.",
  args: {
    preset: tool.schema.enum(["demo", "e2e"]).optional()
      .describe("Preset interaction script: 'demo' (navigate all panels, show help overlay) or 'e2e' (tab to Scenarios, select first, run, complete)."),
    scenarioIndex: tool.schema.number().optional()
      .describe("0-based flat-list index of the scenario to run and complete. Flat list: 0=category header, 1=scenario 01, 2=scenario 02, etc."),
    scenarioName: tool.schema.string().optional()
      .describe("Scenario label for markers (default: 'Scenario N'). Only used with scenarioIndex."),
    steps: tool.schema.string().optional()
      .describe("JSON string of ReplayStep[] for custom interactions. Each step: { t: number, kind: 'key'|'resize'|'marker', ... }. Generate from user's natural-language description."),
    outputDir: tool.schema.string().optional()
      .describe("Output directory for cast/HTML (default: scripts/scenarios/reports/tui-capture/<mode>-<timestamp>)"),
    speed: tool.schema.number().optional()
      .describe("Playback speed multiplier. 1 = real-time, 2 = 2x, 5 = fast. Default 2."),
    title: tool.schema.string().optional()
      .describe("Recording title (default auto-generated)"),
  },
  async execute(args, context) {
    const { preset, scenarioIndex, scenarioName, steps, speed, title } = args;
    const ts = Date.now();
    const projectRoot = context.worktree;

    const modes = [preset, scenarioIndex !== undefined, steps !== undefined].filter(Boolean).length;
    if (modes === 0) return "Error: one of 'preset', 'scenarioIndex', or 'steps' is required.";
    if (modes > 1) return "Error: use only one of 'preset', 'scenarioIndex', or 'steps'.";

    const outputDir = args.outputDir ??
      `scripts/scenarios/reports/tui-capture/${preset ?? (scenarioIndex !== undefined ? `scenario-${scenarioIndex}` : "custom")}-${ts}`;
    const absOutputDir = path.resolve(projectRoot, outputDir);

    const scriptPath = path.join(projectRoot, "scripts/scenario-dashboard/tui_headless_capture.ts");

    if (preset) {
      let result;
      if (preset === "e2e" && speed) {
        result = await Bun.$`deno run -A ${scriptPath} ${absOutputDir} --e2e --speed=${speed}`.text();
      } else if (preset === "e2e") {
        result = await Bun.$`deno run -A ${scriptPath} ${absOutputDir} --e2e`.text();
      } else if (speed) {
        result = await Bun.$`deno run -A ${scriptPath} ${absOutputDir} --speed=${speed}`.text();
      } else {
        result = await Bun.$`deno run -A ${scriptPath} ${absOutputDir}`.text();
      }
      return formatResult(result);
    }

    if (scenarioIndex !== undefined) {
      const name = scenarioName ?? `Scenario ${scenarioIndex}`;
      const speedFlag = speed ? `--speed=${speed}` : "";
      const result =
        await Bun.$`deno run -A ${scriptPath} ${absOutputDir} --scenario=${scenarioIndex} --scenario-name=${name} ${speedFlag}`
          .text();
      return formatResult(result);
    }

    // ── Custom steps ──────────────────────────────────────────────────

    let stepsParsed: unknown[];
    try {
      stepsParsed = JSON.parse(steps!);
      if (!Array.isArray(stepsParsed) || stepsParsed.length === 0) {
        return "Error: 'steps' must be a non-empty JSON array.";
      }
    } catch (e) {
      return `Error: invalid JSON in 'steps': ${(e as Error).message}`;
    }

    const dashboardDir = path.join(projectRoot, "scripts/scenario-dashboard");
    const tempScript = path.join(dashboardDir, `.tmp-capture-${ts}.ts`);

    const scriptContent = [
      `import { captureHeadlessReplay } from "./tui_headless_capture.ts";`,
      `import { join } from "$std/path/mod.ts";`,
      ``,
      `const result = await captureHeadlessReplay({`,
      `  outputDir: ${JSON.stringify(absOutputDir)},`,
      `  steps: ${JSON.stringify(stepsParsed)},`,
      `  speed: ${speed ?? 2},`,
      `  title: ${JSON.stringify(title ?? "Garazyk Dashboard — Custom Capture")},`,
      `});`,
      ``,
      `console.log("[capture] Cast:", result.castPath);`,
      `console.log("[capture] HTML:", result.htmlPath);`,
    ].join("\n");

    fs.writeFileSync(tempScript, scriptContent, "utf8");

    try {
      const result = await Bun.$`deno run -A ${tempScript}`.text();
      return formatResult(result);
    } finally {
      try {
        fs.unlinkSync(tempScript);
      } catch {
        // ignore cleanup errors
      }
    }
  },
});

function formatResult(output: string): string {
  const trimmed = output.trim();
  if (!trimmed) return "TUI capture completed (no output from script).";

  const castMatch = trimmed.match(/Cast:\s*(.+)/);
  const htmlMatch = trimmed.match(/HTML:\s*(.+)/);

  if (!castMatch && !htmlMatch) return trimmed;

  const lines: string[] = ["### TUI Capture Complete\n"];
  if (castMatch) lines.push(`- **Cast file**: \`${castMatch[1].trim()}\``);
  if (htmlMatch) lines.push(`- **HTML export**: \`${htmlMatch[1].trim()}\``);
  lines.push("\nOpen the HTML file in a browser to view the playback.");

  return lines.join("\n");
}

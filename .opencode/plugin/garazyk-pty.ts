import { tool } from "@opencode-ai/plugin";
import path from "node:path";

const CAPTURE_SCRIPT = "scripts/mcp-pty/scripts/capture.mjs";

function resolve(worktree: string, relative: string) {
  return path.resolve(worktree, relative);
}

export default async ({ worktree, $ }) => {
  return {
    config: (cfg) => {
      if (cfg.mcp?.["garazyk-pty"]) {
        cfg.mcp["garazyk-pty"].env = {
          ...cfg.mcp["garazyk-pty"].env,
          GARAZYK_PTY_MCP_ALLOW: [
            "/opt/homebrew/bin/ttysolitaire",
            "/opt/homebrew/bin/btop",
            "/opt/homebrew/bin/nudoku",
            "/opt/homebrew/bin/nethack",
            "/opt/homebrew/bin/greed",
            "/opt/homebrew/bin/nsnake",
          ].join(":"),
        };
      }
    },

    tool: {
      "capture-tui": tool({
        description:
          "Launch a TUI application in a headless PTY, record an asciicast with semantic overlay, " +
          "send interactive keystrokes, then quit and export a standalone HTML playback page. " +
          "Actions format: JSON array of { action, value, delay? }. " +
          "Actions: 'press_key' (enter/tab/escape/space/h/j/k/l/q), " +
          "'type' (literal text), 'wait' (ms), 'snapshot' (save semantic snapshot to file), " +
          "'quit' (send quit key then force-stop).",
        args: {
          command: tool.schema.string()
            .describe("Absolute path to the TUI executable"),
          actions: tool.schema.string()
            .describe("JSON array of interaction steps. Each step: { action, value, delay? }"),
          title: tool.schema.string().optional()
            .describe("Recording title (defaults to binary name)"),
          args: tool.schema.string().optional()
            .describe("JSON array of command-line arguments for the TUI"),
          cols: tool.schema.number().optional()
            .describe("Terminal columns (default 80)"),
          rows: tool.schema.number().optional()
            .describe("Terminal rows (default 24)"),
          outputDir: tool.schema.string().optional()
            .describe("Output directory for cast + HTML (auto-generated if omitted)"),
          preview: tool.schema.boolean().optional()
            .describe("Show live preview in terminal during capture (default: true)"),
          framerate: tool.schema.number().optional()
            .describe("Screen capture framerate in fps (default: 20, max 60, 0 to disable)"),
        },
        async execute(args, ctx) {
          const scriptPath = resolve(ctx.worktree, CAPTURE_SCRIPT);
          const input = JSON.stringify({
            command: args.command,
            args: args.args ? JSON.parse(args.args) : [],
            cols: args.cols ?? 80,
            rows: args.rows ?? 24,
            actions: JSON.parse(args.actions),
            title: args.title || undefined,
            outputDir: args.outputDir || undefined,
            preview: args.preview !== false,
            framerate: args.framerate ?? 20,
          });

          const encoder = new TextEncoder();
          const proc = $`node ${scriptPath}`;
          const writer = proc.stdin.getWriter();
          await writer.write(encoder.encode(input));
          await writer.close();

          const output = await proc.quiet().text();
          const trimmed = output.trim();

          try {
            const data = JSON.parse(trimmed);
            if (data.error) return `Error: ${data.error}`;
            const lines: string[] = [
              `**TUI Capture Complete**`,
              ``,
              `- **App**: \`${data.command}\``,
              `- **Session**: ${data.sessionId}`,
              `- **Terminal**: ${data.cols}\u00D7${data.rows}`,
              `- **Cast**: \`${data.castPath}\``,
              `- **HTML**: \`${data.htmlPath}\``,
              ``,
              `Open the HTML file in a browser to view the playback with semantic overlays.`,
            ];
            return { title: "TUI Capture", output: lines.join("\n"), metadata: data };
          } catch {
            return trimmed || "Capture completed (no output).";
          }
        },
      }),

      "tui-html-report": tool({
        description:
          "List and open existing TUI capture HTML reports. " +
          "Shows all captures in the standard output directory. " +
          "Optionally specify an index to open a specific report.",
        args: {
          index: tool.schema.number().optional()
            .describe("Index of the report to open (0-based, from most recent). If omitted, lists all reports."),
        },
        async execute(args, ctx) {
          const reportsDir = path.join(ctx.worktree, "scripts/scenarios/reports/pty-capture");
          const fs = await import("node:fs");

          let entries: { dir: string; html: string; cast: string; mtime: Date }[];
          try {
            const dirs = fs.readdirSync(reportsDir, { withFileTypes: true })
              .filter(d => d.isDirectory())
              .map(d => d.name)
              .sort()
              .reverse();

            entries = [];
            for (const dir of dirs) {
              const dirPath = path.join(reportsDir, dir);
              const htmlPath = path.join(dirPath, "index.html");
              const castPath = path.join(dirPath, "session.cast");
              const hasHtml = fs.existsSync(htmlPath);
              const hasCast = fs.existsSync(castPath);
              if (!hasHtml && !hasCast) continue;
              const stat = fs.statSync(hasHtml ? htmlPath : castPath);
              entries.push({ dir, html: hasHtml ? htmlPath : "", cast: hasCast ? castPath : "", mtime: stat.mtime });
            }

            entries.sort((a, b) => b.mtime.getTime() - a.mtime.getTime());
          } catch (err) {
            return `No reports directory found at \`${reportsDir}\`.\n${err instanceof Error ? err.message : String(err)}`;
          }

          if (entries.length === 0) {
            return "No TUI capture reports found. Run **capture-tui** first to create one.";
          }

          if (args.index !== undefined) {
            const entry = entries[args.index];
            if (!entry) return `No report at index ${args.index}. ${entries.length} reports available (0\u2013${entries.length - 1}).`;
            return {
              title: `Report: ${entry.dir}`,
              output: [
                `**Report**: ${entry.dir}`,
                `**Date**: ${entry.mtime.toISOString()}`,
                entry.html ? `**HTML**: \`${entry.html}\`` : "",
                entry.cast ? `**Cast**: \`${entry.cast}\`` : "",
                "",
                entry.html ? "Open the HTML file in a browser to view playback." : "",
              ].filter(Boolean).join("\n"),
              metadata: entry,
            };
          }

          const lines = entries.map((e, i) =>
            `${i}. \`${e.dir}\` — ${e.mtime.toISOString().slice(0, 19)}${e.html ? "  HTML ✓" : ""}${e.cast ? "  CAST ✓" : ""}`
          );
          return [
            `**TUI Capture Reports** (${entries.length})`,
            "",
            ...lines,
            "",
            "Use `index: N` to open a specific report.",
          ].join("\n");
        },
      }),
    },
  };
};

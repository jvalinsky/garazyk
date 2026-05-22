import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import { spawn } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { join } from "node:path";

const TEST_MAIN_PATH = "Garazyk/Tests/test_main.m";
const MAX_OUTPUT_BYTES = 50 * 1024;
const MAX_OUTPUT_LINES = 2000;

type CommandResult = {
  stdout: string;
  stderr: string;
  code: number | null;
  signal: NodeJS.Signals | null;
};

function truncateTail(text: string): string {
  const lines = text.split("\n");
  let truncated = false;
  let kept = lines;
  if (lines.length > MAX_OUTPUT_LINES) {
    kept = lines.slice(lines.length - MAX_OUTPUT_LINES);
    truncated = true;
  }
  let out = kept.join("\n");
  if (Buffer.byteLength(out, "utf8") > MAX_OUTPUT_BYTES) {
    const buf = Buffer.from(out, "utf8");
    out = buf.subarray(buf.length - MAX_OUTPUT_BYTES).toString("utf8");
    truncated = true;
  }
  if (!truncated) return out;
  return `[Output truncated to last ${MAX_OUTPUT_LINES} lines / ${MAX_OUTPUT_BYTES} bytes]\n${out}`;
}

function runCommand(command: string, args: string[], cwd: string, signal?: AbortSignal, timeoutMs = 300_000): Promise<CommandResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";

    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      setTimeout(() => child.kill("SIGKILL"), 2_000).unref();
    }, timeoutMs);

    const abort = () => child.kill("SIGTERM");
    signal?.addEventListener("abort", abort, { once: true });

    child.stdout.on("data", (chunk) => { stdout += chunk.toString(); });
    child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
    child.on("error", (err) => {
      clearTimeout(timer);
      signal?.removeEventListener("abort", abort);
      reject(err);
    });
    child.on("close", (code, sig) => {
      clearTimeout(timer);
      signal?.removeEventListener("abort", abort);
      resolve({ stdout, stderr, code, signal: sig });
    });
  });
}

async function shell(command: string, cwd: string, signal?: AbortSignal, timeoutMs?: number): Promise<CommandResult> {
  return runCommand("bash", ["-lc", command], cwd, signal, timeoutMs);
}

function formatResult(title: string, result: CommandResult): string {
  const parts = [`=== ${title} ===`];
  if (result.stdout.trim()) parts.push(truncateTail(result.stdout.trim()));
  if (result.stderr.trim()) parts.push(`stderr:\n${truncateTail(result.stderr.trim())}`);
  parts.push(`exit: ${result.code}${result.signal ? ` (${result.signal})` : ""}`);
  return parts.join("\n");
}

async function parseRegisteredClasses(cwd: string, signal?: AbortSignal): Promise<string[]> {
  const result = await runCommand("rg", ["-o", "(?<=@\")[A-Za-z]+Tests(?=\")", TEST_MAIN_PATH], cwd, signal, 30_000);
  if (result.code !== 0 && !result.stdout.trim()) return [];
  return result.stdout.split("\n").map((s) => s.trim()).filter(Boolean);
}

async function findTestMethods(cwd: string, className: string, signal?: AbortSignal): Promise<string[]> {
  const fileResult = await runCommand("rg", ["-l", `\\b@implementation\\s+${className}\\b`, "Garazyk/Tests/"], cwd, signal, 30_000);
  const file = fileResult.stdout.split("\n").map((s) => s.trim()).find(Boolean);
  if (!file) return [];
  const methods = await runCommand("rg", ["-o", "(?<=^[-+]\\s*\\(void\\))test\\w+", file], cwd, signal, 30_000);
  return methods.stdout.split("\n").map((s) => s.trim()).filter(Boolean);
}

async function hasRecentDeciduousNode(cwd: string, signal?: AbortSignal): Promise<boolean> {
  if (!existsSync(join(cwd, ".deciduous"))) return true;
  const result = await shell("deciduous nodes 2>/dev/null | tail -5", cwd, signal, 10_000);
  if (result.code !== 0) return true;
  return result.stdout.split("\n").some((line) => /\b(goal|action)\b/i.test(line));
}

export default function garazykTools(pi: ExtensionAPI) {
  pi.registerTool({
    name: "garazyk_build_test",
    label: "Garazyk Build/Test",
    description: "Build Garazyk and run XCTest tests. Runs xcodegen generate, xcodebuild, and build/tests/AllTests. Output is truncated to 50KB/2000 lines.",
    promptSnippet: "Build Garazyk and run XCTest tests with optional filter.",
    promptGuidelines: ["Use garazyk_build_test for Garazyk build/test validation instead of ad-hoc xcodegen/xcodebuild commands."],
    parameters: Type.Object({
      scheme: Type.Optional(Type.String({ default: "AllTests", description: "Xcode scheme to build." })),
      filter: Type.Optional(Type.String({ description: "Optional AllTests filter, e.g. PDSHealthCheckTests or PDSHealthCheckTests/testName." })),
      skipBuild: Type.Optional(Type.Boolean({ default: false, description: "Skip xcodegen/xcodebuild and only run tests." })),
      json: Type.Optional(Type.Boolean({ default: false, description: "Ask AllTests for JSON output." })),
    }),
    async execute(_id, params, signal, _onUpdate, ctx) {
      const scheme = params.scheme || "AllTests";
      const chunks: string[] = [];

      if (!params.skipBuild) {
        const gen = await runCommand("xcodegen", ["generate"], ctx.cwd, signal, 120_000);
        chunks.push(formatResult("xcodegen generate", gen));
        if (gen.code !== 0) return { content: [{ type: "text", text: chunks.join("\n\n") }], details: { failedAt: "xcodegen" } };

        const build = await runCommand("xcodebuild", ["-scheme", scheme, "build"], ctx.cwd, signal, 600_000);
        chunks.push(formatResult("xcodebuild", build));
        if (build.code !== 0) return { content: [{ type: "text", text: chunks.join("\n\n") }], details: { failedAt: "xcodebuild" } };
      }

      const testArgs = ["build/tests/AllTests"];
      if (params.filter) testArgs.push("--filter", params.filter);
      if (params.json) testArgs.push("--json");
      const tests = await runCommand(testArgs[0], testArgs.slice(1), ctx.cwd, signal, 600_000);
      chunks.push(formatResult("AllTests", tests));
      return { content: [{ type: "text", text: chunks.join("\n\n") }], details: { exitCode: tests.code } };
    },
  });

  pi.registerTool({
    name: "garazyk_find_test_class",
    label: "Garazyk Find Test Class",
    description: "Search XCTest test classes by name pattern and show registration status in Garazyk/Tests/test_main.m.",
    promptSnippet: "Find XCTest classes, registration status, and methods.",
    parameters: Type.Object({
      pattern: Type.String({ description: "Substring pattern, e.g. Health, PDS, OAuth." }),
      showMethods: Type.Optional(Type.Boolean({ default: false })),
      unregistered: Type.Optional(Type.Boolean({ default: false })),
    }),
    async execute(_id, params, signal, _onUpdate, ctx) {
      const pattern = params.pattern;
      const find = await runCommand(
        "find",
        ["Garazyk/Tests", "(", "-name", `*${pattern}*Tests.m`, "-o", "-name", `*${pattern}*Tests.h`, ")"],
        ctx.cwd,
        signal,
        30_000,
      );
      const fileLines = find.stdout.split("\n").map((s) => s.trim()).filter(Boolean).sort();
      const registered = await parseRegisteredClasses(ctx.cwd, signal);
      const matchingRegistered = registered.filter((c) => c.toLowerCase().includes(pattern.toLowerCase()));
      const fileClassNames = new Set(fileLines.map((file) => (file.split("/").pop() || "").replace(/\.(m|h)$/, "")));
      const diskOnly = [...fileClassNames].filter((c) => !registered.includes(c)).sort();
      const registeredOnly = matchingRegistered.filter((c) => !fileClassNames.has(c)).sort();
      const both = matchingRegistered.filter((c) => fileClassNames.has(c)).sort();
      const out: string[] = [];

      if (params.unregistered) {
        out.push(diskOnly.length ? `=== Unregistered test classes (${diskOnly.length}) ===` : "All matching test files are registered.");
        for (const c of diskOnly) out.push(`  ✗ ${c} → ${fileLines.find((f) => f.includes(c)) || "?"}`);
        return { content: [{ type: "text", text: out.join("\n") }], details: { diskOnly } };
      }

      out.push(`=== Registered + file found (${both.length}) ===`);
      for (const c of both) {
        out.push(`  ✓ ${c} → ${fileLines.find((f) => f.includes(c)) || "?"}`);
        if (params.showMethods) for (const m of await findTestMethods(ctx.cwd, c, signal)) out.push(`      - ${m}`);
      }
      if (diskOnly.length) {
        out.push(`\n=== Unregistered (${diskOnly.length}) — not in test_main.m ===`);
        for (const c of diskOnly) out.push(`  ✗ ${c} → ${fileLines.find((f) => f.includes(c)) || "?"}`);
      }
      if (registeredOnly.length) {
        out.push(`\n=== Registered but no file (${registeredOnly.length}) ===`);
        for (const c of registeredOnly) out.push(`  ? ${c} — no .m/.h found`);
      }
      out.push(`\n--- Summary: ${both.length} registered + filed, ${diskOnly.length} unregistered, ${registeredOnly.length} stale registrations ---`);
      return { content: [{ type: "text", text: out.join("\n") }], details: { both, diskOnly, registeredOnly } };
    },
  });

  pi.registerTool({
    name: "garazyk_service_control",
    label: "Garazyk Service Control",
    description: "Control local ATProto services: start, stop, restart, status, logs, collect diagnostics. Delegates to scripts/manage_local_network.ts and docker.",
    promptSnippet: "Start, stop, inspect, or collect diagnostics for local Garazyk ATProto services.",
    parameters: Type.Object({
      command: StringEnum(["start", "stop", "restart", "status", "logs", "clean", "diagnostics"] as const),
      target: Type.Optional(StringEnum(["all", "plc", "pds", "relay", "appview", "chat", "video", "ui"] as const)),
      lines: Type.Optional(Type.Number({ default: 50 })),
      pds2: Type.Optional(Type.Boolean({ default: false })),
      binary: Type.Optional(Type.Boolean({ default: false })),
      runId: Type.Optional(Type.String()),
    }),
    async execute(_id, params, signal, _onUpdate, ctx) {
      const target = params.target || "all";
      let result: CommandResult;
      if (params.command === "status") {
        result = await runCommand("docker", ["ps", "--format", "table {{.Names}}\t{{.Status}}\t{{.Ports}}", "--filter", "name=garazyk-e2e"], ctx.cwd, signal, 30_000);
      } else if (params.command === "logs") {
        const ps = await runCommand("docker", ["ps", "--format", "{{.Names}}", "--filter", target === "all" ? "name=garazyk-e2e" : `name=${target}`], ctx.cwd, signal, 30_000);
        const containers = ps.stdout.split("\n").map((s) => s.trim()).filter(Boolean);
        const sections: string[] = [];
        for (const c of containers) {
          const logs = await runCommand("docker", ["logs", "--tail", String(params.lines || 50), c], ctx.cwd, signal, 30_000);
          sections.push(`=== ${c} ===\n${logs.stdout || logs.stderr}`);
        }
        return { content: [{ type: "text", text: truncateTail(sections.join("\n\n") || "No matching containers.") }], details: { containers } };
      } else {
        const args = ["run", "-A", "scripts/manage_local_network.ts"];
        if (params.command === "stop" || params.command === "clean") args.push("--teardown");
        if (params.command === "restart") args.push("--teardown");
        if (params.command === "diagnostics") args.push("--collect-diagnostics");
        if (params.pds2) args.push("--pds2");
        if (params.binary) args.push("--binary");
        if (params.runId) args.push("--run-id", params.runId);
        result = await runCommand("deno", args, ctx.cwd, signal, 600_000);
        if (params.command === "restart" && result.code === 0) {
          const startArgs = ["run", "-A", "scripts/manage_local_network.ts"];
          if (params.pds2) startArgs.push("--pds2");
          if (params.binary) startArgs.push("--binary");
          if (params.runId) startArgs.push("--run-id", params.runId);
          const start = await runCommand("deno", startArgs, ctx.cwd, signal, 600_000);
          return { content: [{ type: "text", text: `${formatResult("teardown", result)}\n\n${formatResult("start", start)}` }], details: { teardown: result.code, start: start.code } };
        }
      }
      return { content: [{ type: "text", text: formatResult(params.command, result) }], details: { exitCode: result.code } };
    },
  });

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName === "edit" || event.toolName === "write") {
      const ok = await hasRecentDeciduousNode(ctx.cwd, ctx.signal);
      if (!ok) {
        const message = "No recent deciduous goal/action node found. Run: deciduous add goal/action ...";
        ctx.ui.notify(message, "warn");
        if (process.env.GARAZYK_REQUIRE_DECIDUOUS === "1") return { block: true, reason: message };
      }
    }

    if (isToolCallEventType("bash", event)) {
      const command = event.input.command || "";
      if (/^\s*git\s+push\b/.test(command)) {
        const testBinary = join(ctx.cwd, "build/tests/AllTests");
        let testStatus = "not built";
        try {
          if (existsSync(testBinary)) {
            const stat = statSync(testBinary);
            testStatus = `built, last modified: ${stat.mtime.toISOString()}`;
          }
        } catch {
          testStatus = "not built";
        }
        event.input.command = `echo "--- PushGuard: Test binary ${testStatus}. Consider running garazyk_build_test first. ---" && ${command}`;
      }
    }
  });
}

#!/usr/bin/env node
import { TerminalSessionManager, snapshotToYaml } from "./terminal_session.mjs";
import { AsciicastRecorder, defaultRecordingDir } from "./recording.mjs";
import { worldQuery } from "./world.mjs";
import { createSidecarPtyFactory, SidecarManager } from "./sidecar.mjs";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";

const useSidecar = process.argv.includes("--sidecar");

const manager = new TerminalSessionManager({
  env: process.env,
  ptyFactory: useSidecar ? createSidecarPtyFactory() : null,
});

function toolResultFromSnapshot(snapshot) {
  return {
    content: [{ type: "text", text: snapshotToYaml(snapshot) }],
    isError: false,
    _meta: { structuredContent: snapshot }
  };
}

function startToolResult(snapshot) {
  return {
    content: [{ type: "text", text: snapshotToYaml(snapshot) }],
    isError: false,
    _meta: {
      structuredContent: {
        sessionId: snapshot.sessionId,
        pid: snapshot.pid,
        snapshot,
        ...snapshot,
      }
    }
  };
}

const server = new Server(
  { name: "garazyk-pty", version: "0.1.0" },
  { capabilities: { tools: {} } }
);

const tools = [
  {
    name: "pty_start",
    description: "Start a whitelisted command in a pseudo-terminal and return the initial screen snapshot.",
    inputSchema: {
      type: "object",
      properties: {
        command: { type: "string", description: "Absolute path to an allowlisted executable" },
        args: { type: "array", items: { type: "string" }, description: "Command arguments" },
        cwd: { type: "string", description: "Absolute working directory" },
        cols: { type: "integer", minimum: 1, maximum: 400, default: 80 },
        rows: { type: "integer", minimum: 1, maximum: 200, default: 24 },
        env: { type: "object", additionalProperties: { type: "string" } },
        title: { type: "string" },
      },
      required: ["command"],
    },
  },
  {
    name: "pty_snapshot",
    description: "Return the current terminal screen as YAML plus structured line/cursor/session data.",
    inputSchema: {
      type: "object",
      properties: {
        sessionId: { type: "string" },
      },
      required: ["sessionId"],
    },
  },
  {
    name: "pty_semantic_snapshot",
    description: "Return a deterministically parsed semantic snapshot of the terminal screen, optimized for LLM interpretation.",
    inputSchema: {
      type: "object",
      properties: {
        sessionId: { type: "string" },
        detail: { type: "string", enum: ["compact", "full"], default: "compact" },
        includePrompt: { type: "boolean", default: false },
      },
      required: ["sessionId"],
    },
  },
  {
    name: "pty_world_query",
    description: "Run a strict, deterministic query against the current normalized TuiWorld graph.",
    inputSchema: {
      type: "object",
      properties: {
        sessionId: { type: "string" },
        op: {
          type: "string",
          enum: [
            "getByRole",
            "getByRef",
            "find",
            "related",
            "nearest",
            "explain",
            "actionsFor",
            "primaryAction",
            "validate",
          ],
        },
        detail: { type: "string", enum: ["compact", "full"], default: "compact" },
        ref: { type: "string" },
        role: { type: "string" },
        name: { type: "string" },
        domain: { type: "string" },
        source: { type: "string" },
        kind: { type: "string" },
        direction: {
          type: "string",
          enum: ["in", "out", "both", "above", "below", "leftOf", "rightOf"],
        },
        strict: { type: "boolean", default: true },
        selected: { type: "boolean" },
        focused: { type: "boolean" },
        visible: { type: "boolean" },
        includeSource: { type: "boolean" },
        includeTarget: { type: "boolean" },
        intent: { type: "string" },
      },
      required: ["sessionId", "op"],
    },
  },
  {
    name: "pty_action",
    description: "Send a key, literal text, or raw escape string to a PTY session and return the updated snapshot.",
    inputSchema: {
      type: "object",
      properties: {
        sessionId: { type: "string" },
        action: { type: "string", enum: ["press_key", "type", "write"] },
        value: { type: "string" },
      },
      required: ["sessionId", "action", "value"],
    },
  },
  {
    name: "pty_resize",
    description: "Resize a PTY and its headless terminal model.",
    inputSchema: {
      type: "object",
      properties: {
        sessionId: { type: "string" },
        cols: { type: "integer", minimum: 1, maximum: 400 },
        rows: { type: "integer", minimum: 1, maximum: 200 },
      },
      required: ["sessionId", "cols", "rows"],
    },
  },
  {
    name: "pty_stop",
    description: "Stop a PTY session with SIGTERM, optionally escalating to SIGKILL after a timeout.",
    inputSchema: {
      type: "object",
      properties: {
        sessionId: { type: "string" },
        signal: { type: "string", default: "SIGTERM" },
        force: { type: "boolean", default: true },
        killAfterMs: { type: "integer", minimum: 0, default: 500 },
      },
      required: ["sessionId"],
    },
  },
  {
    name: "pty_list",
    description: "List live PTY sessions.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "pty_rec_start",
    description: "Start asciicast v2 output recording for a session. Input is not recorded unless recordInput is true.",
    inputSchema: {
      type: "object",
      properties: {
        sessionId: { type: "string" },
        title: { type: "string" },
        outputDir: { type: "string" },
        recordInput: { type: "boolean", default: false },
        semanticOverlay: { type: "boolean", default: false },
      },
      required: ["sessionId"],
    },
  },
  {
    name: "pty_rec_stop",
    description: "Stop asciicast recording and export a minimal standalone HTML page.",
    inputSchema: {
      type: "object",
      properties: {
        sessionId: { type: "string" },
      },
      required: ["sessionId"],
    },
  },
];

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return { tools };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args = {} } = request.params;
  try {
    switch (name) {
      case "pty_start": {
        const session = await manager.create(args);
        await session.settle(100);
        return startToolResult(session.snapshot());
      }
      case "pty_snapshot": {
        const session = manager.get(args.sessionId);
        await session.settle(20);
        return toolResultFromSnapshot(session.snapshot());
      }
      case "pty_semantic_snapshot": {
        const session = manager.get(args.sessionId);
        await session.settle(20);
        const detail = args.detail || "compact";
        const includePrompt = args.includePrompt || false;
        const semanticRes = session.semanticSnapshot(detail, includePrompt);
        return {
          content: [{ type: "text", text: JSON.stringify(semanticRes, null, 2) }],
          isError: false,
          _meta: { structuredContent: semanticRes }
        };
      }
      case "pty_world_query": {
        const session = manager.get(args.sessionId);
        await session.settle(20);
        const semanticRes = session.semanticSnapshot("compact", false);
        const result = worldQuery(semanticRes.snapshot.world, args);
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
          isError: false,
          _meta: { structuredContent: result }
        };
      }
      case "pty_action": {
        const session = manager.get(args.sessionId);
        if (args.action === "press_key") await session.pressKey(args.value);
        else if (args.action === "type") await session.type(args.value);
        else if (args.action === "write") await session.rawWrite(args.value);
        else throw new Error(`Unknown action: ${args.action}`);
        return toolResultFromSnapshot(session.snapshot());
      }
      case "pty_resize": {
        const session = manager.get(args.sessionId);
        session.resize(args.cols, args.rows);
        await session.settle(50);
        return toolResultFromSnapshot(session.snapshot());
      }
      case "pty_stop": {
        const session = await manager.stop(args.sessionId, {
          signal: typeof args.signal === "string" ? args.signal : "SIGTERM",
          force: args.force !== false,
          killAfterMs: Number.isInteger(args.killAfterMs) ? args.killAfterMs : 500,
        });
        return toolResultFromSnapshot(session.snapshot());
      }
      case "pty_list":
        return {
          content: [{ type: "text", text: JSON.stringify(manager.list(), null, 2) }],
          isError: false,
          _meta: { structuredContent: { sessions: manager.list() } }
        };
      case "pty_rec_start": {
        const session = manager.get(args.sessionId);
        if (session.recording) {
          throw new Error("recording already active");
        }
        const outputDir = typeof args.outputDir === "string"
          ? args.outputDir
          : defaultRecordingDir(process.cwd());
        const recorder = new AsciicastRecorder({
          outputDir,
          cols: session.cols,
          rows: session.rows,
          title: typeof args.title === "string" ? args.title : session.title,
          recordInput: args.recordInput === true,
          semanticOverlay: args.semanticOverlay === true,
          command: [session.command, ...session.args].join(" "),
        });
        session.attachRecording(recorder);
        return {
          content: [{ type: "text", text: `Recording started.\nCast: ${recorder.castPath}` }],
          isError: false,
          _meta: { structuredContent: { sessionId: session.sessionId, castPath: recorder.castPath } }
        };
      }
      case "pty_rec_stop": {
        const session = manager.get(args.sessionId);
        const recorder = session.detachRecording();
        if (!recorder) throw new Error("no active recording");
        await recorder.close();
        return {
          content: [{ type: "text", text: `Recording complete.\nCast: ${recorder.castPath}\nHTML: ${recorder.htmlPath}` }],
          isError: false,
          _meta: {
            structuredContent: {
              sessionId: session.sessionId,
              castPath: recorder.castPath,
              htmlPath: recorder.htmlPath,
            }
          }
        };
      }
      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (error) {
    const structuredError = {
      message: error.message,
      code: error.code || "error",
      candidates: error.candidates,
      locator: error.locator,
      role: error.role,
      name: error.name,
    };
    return {
      content: [{ type: "text", text: `Error: ${error.message}` }],
      isError: true,
      _meta: { structuredContent: { error: structuredError } },
    };
  }
});

let shuttingDown = false;

async function gracefulShutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  await manager.stopAll();
  await manager.dispose();
  await SidecarManager.dispose();
  await server.close();
  process.exit(0);
}

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);

  process.on("SIGINT", () => void gracefulShutdown());
  process.on("SIGTERM", () => void gracefulShutdown());

  // stdin-close: transport may close if the parent process exits
  process.stdin.on("close", () => void gracefulShutdown());

  process.on("uncaughtException", (error) => {
    console.error("uncaughtException:", error);
    void gracefulShutdown();
  });

  process.on("unhandledRejection", (reason) => {
    console.error("unhandledRejection:", reason);
    void gracefulShutdown();
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

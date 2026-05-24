#!/usr/bin/env node
import { createInterface } from "node:readline";
import { TerminalSessionManager, snapshotToYaml } from "./terminal_session.mjs";
import { AsciicastRecorder, defaultRecordingDir } from "./recording.mjs";

const manager = new TerminalSessionManager();

function jsonRpc(id, result) {
  return JSON.stringify({ jsonrpc: "2.0", id, result });
}

function jsonRpcError(id, code, message) {
  return JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } });
}

function toolResultFromSnapshot(snapshot) {
  return {
    content: [{ type: "text", text: snapshotToYaml(snapshot) }],
    structuredContent: snapshot,
    isError: false,
  };
}

function startToolResult(snapshot) {
  return {
    content: [{ type: "text", text: snapshotToYaml(snapshot) }],
    structuredContent: {
      sessionId: snapshot.sessionId,
      pid: snapshot.pid,
      snapshot,
      ...snapshot,
    },
    isError: false,
  };
}

function errorToolResult(message) {
  return {
    content: [{ type: "text", text: `Error: ${message}` }],
    isError: true,
  };
}

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

async function handleToolCall(name, args = {}) {
  try {
    switch (name) {
      case "pty_start": {
        const session = manager.create(args);
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
          structuredContent: semanticRes,
          isError: false,
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
          structuredContent: { sessions: manager.list() },
          isError: false,
        };
      case "pty_rec_start": {
        const session = manager.get(args.sessionId);
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
          structuredContent: { sessionId: session.sessionId, castPath: recorder.castPath },
          isError: false,
        };
      }
      case "pty_rec_stop": {
        const session = manager.get(args.sessionId);
        const recorder = session.detachRecording();
        if (!recorder) throw new Error("no active recording");
        await recorder.close();
        return {
          content: [{ type: "text", text: `Recording complete.\nCast: ${recorder.castPath}\nHTML: ${recorder.htmlPath}` }],
          structuredContent: {
            sessionId: session.sessionId,
            castPath: recorder.castPath,
            htmlPath: recorder.htmlPath,
          },
          isError: false,
        };
      }
      default:
        return errorToolResult(`Unknown tool: ${name}`);
    }
  } catch (error) {
    return errorToolResult(error.message);
  }
}

async function handleRequest(msg) {
  if (msg.jsonrpc !== "2.0") {
    return jsonRpcError(msg.id, -32600, "Invalid Request");
  }
  if (msg.id === undefined) {
    if (msg.method === "exit") {
      await manager.stopAll();
      manager.dispose();
      process.exit(0);
    }
    return null;
  }
  if (msg.method === "initialize") {
    return jsonRpc(msg.id, {
      protocolVersion: "2024-11-05",
      capabilities: { tools: {} },
      serverInfo: { name: "garazyk-pty", version: "0.1.0" },
    });
  }
  if (msg.method === "initialized") return null;
  if (msg.method === "shutdown") {
    await manager.stopAll();
    manager.dispose();
    return jsonRpc(msg.id, null);
  }
  if (msg.method === "tools/list") {
    return jsonRpc(msg.id, { tools });
  }
  if (msg.method === "tools/call") {
    const params = msg.params ?? {};
    if (!params.name) return jsonRpcError(msg.id, -32602, "Missing tool name");
    return jsonRpc(msg.id, await handleToolCall(params.name, params.arguments ?? {}));
  }
  return jsonRpcError(msg.id, -32601, `Unknown method: ${msg.method}`);
}

async function main() {
  const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });
  for await (const line of rl) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      const msg = JSON.parse(trimmed);
      const response = await handleRequest(msg);
      if (response) process.stdout.write(`${response}\n`);
    } catch (error) {
      process.stdout.write(`${jsonRpcError(null, -32700, error.message || "Parse error")}\n`);
    }
  }
  await manager.stopAll();
  manager.dispose();
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

export { handleRequest, handleToolCall, tools };

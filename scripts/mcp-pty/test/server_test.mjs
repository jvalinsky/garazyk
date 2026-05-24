import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { handleRequest, tools } from "../server.mjs";

test("initialize returns server info and tools capability", async () => {
  const response = JSON.parse(await handleRequest({
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: {},
  }));
  assert.equal(response.result.serverInfo.name, "garazyk-pty");
  assert.deepEqual(response.result.capabilities, { tools: {} });
});

test("tools/list includes pty tools with schemas", async () => {
  const response = JSON.parse(await handleRequest({
    jsonrpc: "2.0",
    id: 2,
    method: "tools/list",
  }));
  const names = response.result.tools.map((tool) => tool.name);
  assert.deepEqual(names, tools.map((tool) => tool.name));
  assert.ok(response.result.tools.every((tool) => tool.inputSchema?.type === "object"));
  assert.ok(names.includes("pty_start"));
  assert.ok(names.includes("pty_rec_stop"));
});

test("tool failures return MCP tool errors instead of JSON-RPC errors", async () => {
  const response = JSON.parse(await handleRequest({
    jsonrpc: "2.0",
    id: 3,
    method: "tools/call",
    params: {
      name: "pty_start",
      arguments: { command: "/bin/definitely-not-allowlisted" },
    },
  }));
  assert.equal(response.result.isError, true);
  assert.match(response.result.content[0].text, /allowlisted/);
  assert.equal(response.error, undefined);
});

test("stdio MCP flow starts cat, sends input, resizes, records, and stops", async () => {
  const child = spawn(process.execPath, ["server.mjs"], {
    cwd: new URL("..", import.meta.url),
    env: {
      ...process.env,
      GARAZYK_PTY_MCP_ALLOW: "/bin/cat",
      GARAZYK_PTY_MCP_MAX_SESSIONS: "2",
    },
    stdio: ["pipe", "pipe", "pipe"],
  });
  const pending = [];
  let stdout = "";
  child.stdout.setEncoding("utf8");
  child.stdout.on("data", (chunk) => {
    stdout += chunk;
    let index;
    while ((index = stdout.indexOf("\n")) >= 0) {
      const line = stdout.slice(0, index);
      stdout = stdout.slice(index + 1);
      if (!line.trim()) continue;
      pending.shift()?.(JSON.parse(line));
    }
  });

  let nextId = 1;
  const request = (method, params) => new Promise((resolve) => {
    const id = nextId++;
    pending.push(resolve);
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
  });

  try {
    const init = await request("initialize", {});
    assert.equal(init.result.serverInfo.name, "garazyk-pty");

    const list = await request("tools/list", {});
    assert.ok(list.result.tools.some((tool) => tool.name === "pty_start"));

    const start = await request("tools/call", {
      name: "pty_start",
      arguments: {
        command: "/bin/cat",
        cols: 20,
        rows: 5,
        cwd: process.cwd(),
        title: "cat",
      },
    });
    assert.equal(start.result.isError, false);
    const { sessionId } = start.result.structuredContent;

    const action = await request("tools/call", {
      name: "pty_action",
      arguments: { sessionId, action: "type", value: "hello\r" },
    });
    assert.ok(action.result.structuredContent.lines.some((line) => line.includes("hello")));

    const outputDir = fs.mkdtempSync(path.join(os.tmpdir(), "garazyk-pty-mcp-"));
    const recStart = await request("tools/call", {
      name: "pty_rec_start",
      arguments: { sessionId, outputDir, recordInput: true },
    });
    assert.equal(recStart.result.isError, false);

    const resize = await request("tools/call", {
      name: "pty_resize",
      arguments: { sessionId, cols: 30, rows: 6 },
    });
    assert.equal(resize.result.structuredContent.cols, 30);
    assert.equal(resize.result.structuredContent.rows, 6);

    const recStop = await request("tools/call", {
      name: "pty_rec_stop",
      arguments: { sessionId },
    });
    assert.equal(recStop.result.isError, false);
    const castLines = fs.readFileSync(recStop.result.structuredContent.castPath, "utf8");
    assert.match(castLines, /"r","30x6"/);

    const stop = await request("tools/call", {
      name: "pty_stop",
      arguments: { sessionId, killAfterMs: 50 },
    });
    assert.equal(stop.result.structuredContent.running, false);
  } finally {
    child.kill("SIGTERM");
  }
});

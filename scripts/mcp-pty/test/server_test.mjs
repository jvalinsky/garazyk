import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

test("stdio MCP flow starts cat, sends input, resizes, records, and stops", async () => {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: ["server.mjs"],
    env: {
      ...process.env,
      GARAZYK_PTY_MCP_ALLOW: "/bin/cat",
      GARAZYK_PTY_MCP_MAX_SESSIONS: "2",
    }
  });

  const client = new Client({
    name: "test-client",
    version: "1.0.0",
  }, {
    capabilities: {}
  });

  await client.connect(transport);

  try {
    const list = await client.listTools();
    assert.ok(list.tools.some((tool) => tool.name === "pty_start"));

    const start = await client.callTool({
      name: "pty_start",
      arguments: {
        command: "/bin/cat",
        cols: 20,
        rows: 5,
        cwd: process.cwd(),
        title: "cat",
      },
    });
    assert.equal(start.isError, false);
    const { sessionId } = start._meta.structuredContent;

    const action = await client.callTool({
      name: "pty_action",
      arguments: { sessionId, action: "type", value: "hello\r" },
    });
    assert.ok(action._meta.structuredContent.lines.some((line) => line.includes("hello")));

    const outputDir = fs.mkdtempSync(path.join(os.tmpdir(), "garazyk-pty-mcp-"));
    const recStart = await client.callTool({
      name: "pty_rec_start",
      arguments: { sessionId, outputDir, recordInput: true },
    });
    assert.equal(recStart.isError, false);

    const resize = await client.callTool({
      name: "pty_resize",
      arguments: { sessionId, cols: 30, rows: 6 },
    });
    assert.equal(resize._meta.structuredContent.cols, 30);
    assert.equal(resize._meta.structuredContent.rows, 6);

    const recStop = await client.callTool({
      name: "pty_rec_stop",
      arguments: { sessionId },
    });
    assert.equal(recStop.isError, false);
    const castLines = fs.readFileSync(recStop._meta.structuredContent.castPath, "utf8");
    assert.match(castLines, /"r","30x6"/);

    const stop = await client.callTool({
      name: "pty_stop",
      arguments: { sessionId, killAfterMs: 50 },
    });
    assert.equal(stop._meta.structuredContent.running, false);
  } finally {
    await transport.close();
  }
});

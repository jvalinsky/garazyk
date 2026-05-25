import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import xtermHeadless from "@xterm/headless";
import {
  TerminalSessionManager,
  encodeKey,
  validateCommand,
} from "../terminal_session.mjs";
import { AsciicastRecorder, buildStandaloneHtml } from "../recording.mjs";

const { Terminal } = xtermHeadless;

test("encodeKey maps common control keys", () => {
  assert.equal(encodeKey("enter"), "\r");
  assert.equal(encodeKey("tab"), "\t");
  assert.equal(encodeKey("escape"), "\x1b");
  assert.equal(encodeKey("backspace"), "\x7f");
  assert.equal(encodeKey("up"), "\x1b[A");
  assert.equal(encodeKey("down"), "\x1b[B");
  assert.equal(encodeKey("right"), "\x1b[C");
  assert.equal(encodeKey("left"), "\x1b[D");
  assert.equal(encodeKey("ctrl-c"), "\x03");
  assert.equal(encodeKey("ctrl-d"), "\x04");
  assert.equal(encodeKey("ctrl-z"), "\x1a");
  assert.equal(encodeKey("ctrl-l"), "\x0c");
});

test("validateCommand requires absolute allowlisted commands and blocks shells", () => {
  const env = { GARAZYK_PTY_MCP_ALLOW: "/bin/cat:/bin/bash" };
  assert.equal(validateCommand("/bin/cat", env), "/bin/cat");
  assert.throws(() => validateCommand("cat", env), /absolute/);
  assert.throws(() => validateCommand("/bin/echo", env), /allowlisted/);
  assert.throws(() => validateCommand("/bin/bash", env), /shell entrypoints/);
  assert.equal(validateCommand("/bin/bash", { ...env, GARAZYK_PTY_MCP_ALLOW_SHELL: "1" }), "/bin/bash");
});

test("validateCommand default allowlist excludes shell-capable editors and pagers", () => {
  const env = {};
  for (const command of ["/usr/bin/less", "/usr/bin/vim", "/usr/bin/vi", "/usr/bin/nano"]) {
    assert.throws(() => validateCommand(command, env), /allowlisted/);
  }
  assert.equal(
    validateCommand("/usr/bin/less", { GARAZYK_PTY_MCP_ALLOW: "/usr/bin/less" }),
    "/usr/bin/less",
  );
});

test("headless xterm exposes lines, cursor, and dimensions", async () => {
  const term = new Terminal({ cols: 20, rows: 4, allowProposedApi: true });
  await new Promise((resolve) => term.write("hello\r\nworld", resolve));
  const line1 = term.buffer.active.getLine(0).translateToString(true);
  const line2 = term.buffer.active.getLine(1).translateToString(true);
  assert.equal(term.cols, 20);
  assert.equal(term.rows, 4);
  assert.equal(line1, "hello");
  assert.equal(line2, "world");
  assert.equal(term.buffer.active.cursorY, 1);
});

test("AsciicastRecorder writes v2 header and output/input/resize events", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "garazyk-pty-rec-"));
  const recorder = new AsciicastRecorder({
    outputDir: dir,
    cols: 80,
    rows: 24,
    title: "test capture",
    recordInput: true,
    command: "/bin/cat",
  });
  recorder.recordOutput("out");
  recorder.recordInput("in");
  recorder.recordResize(100, 30);
  await recorder.close();

  const lines = fs.readFileSync(recorder.castPath, "utf8").trimEnd().split("\n");
  assert.equal(JSON.parse(lines[0]).version, 2);
  assert.deepEqual(JSON.parse(lines[1]).slice(1), ["r", "80x24"]);
  assert.equal(JSON.parse(lines[2])[1], "o");
  assert.equal(JSON.parse(lines[3])[1], "i");
  assert.deepEqual(JSON.parse(lines[4]).slice(1), ["r", "100x30"]);
  assert.ok(fs.existsSync(recorder.htmlPath));
});

test("buildStandaloneHtml can enable semantic overlay controls", () => {
  const castContent = [
    JSON.stringify({ version: 2, width: 10, height: 4, timestamp: 1 }),
    JSON.stringify([0, "o", "┌──┐\r\n│hi│\r\n└──┘"]),
  ].join("\n") + "\n";
  const html = buildStandaloneHtml({
    title: "overlay",
    castContent,
    semanticOverlay: true,
  });
  assert.match(html, /id="overlay"/);
  assert.match(html, /semantic-box/);
  assert.match(html, /let overlayEnabled = true/);
});

test("TerminalSessionManager starts cat, captures input, resizes, and stops", async () => {
  const manager = new TerminalSessionManager({
    env: {
      GARAZYK_PTY_MCP_ALLOW: "/bin/cat",
      GARAZYK_PTY_MCP_MAX_SESSIONS: "2",
    },
    idleMs: 60_000,
  });
  try {
    const session = manager.create({
      command: "/bin/cat",
      cols: 20,
      rows: 5,
      cwd: process.cwd(),
      title: "cat",
    });
    await session.type("abc\r");
    const snapshot = session.snapshot();
    assert.equal(snapshot.sessionId, "s1");
    assert.equal(snapshot.cols, 20);
    assert.ok(snapshot.lines.some((line) => line.includes("abc")));

    session.resize(30, 6);
    assert.equal(session.snapshot().cols, 30);
    assert.equal(session.snapshot().rows, 6);

    await manager.stop(session.sessionId, { force: true, killAfterMs: 50 });
    assert.equal(manager.list().length, 0);
  } finally {
    await manager.stopAll();
    manager.dispose();
  }
});

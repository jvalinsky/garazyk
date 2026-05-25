/**
 * End-to-end test for the Rust sidecar PTY pipeline.
 *
 * Tests the full MCP → sidecar adapter → JSONL protocol → @xterm/headless
 * flow: start, write, snapshot, resize, semantic snapshot, recording,
 * world query, stop, and duplicate detection.
 *
 * Shares a single sidecar process across all tests to avoid spawn/shutdown
 * overhead per-test. The sidecar is expected to be built beforehand:
 *   cargo build --manifest-path scripts/mcp-pty-rs/Cargo.toml
 */

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const sidecarBinary = path.resolve(
  __dirname,
  "..",
  "..",
  "mcp-pty-rs",
  "target",
  "debug",
  "garazyk-ptyd",
);

const binaryExists = fs.existsSync(sidecarBinary);

// ---------------------------------------------------------------------------
// Shared state
// ---------------------------------------------------------------------------

/** @type {import("../sidecar.mjs").SidecarManager} */
let sidecarManager;
/** @type {import("../terminal_session.mjs").TerminalSessionManager} */
let sessionManager;

// ---------------------------------------------------------------------------
// Lifecycle hooks — one sidecar process for the whole test file
// ---------------------------------------------------------------------------

test.before(async () => {
  if (!binaryExists) return;
  const { getSidecarManager } = await import("../sidecar.mjs");
  sidecarManager = getSidecarManager(sidecarBinary);
  // Force lazy start so we know the process is alive
  sidecarManager._ensureStarted();
});

test.after(async () => {
  if (sessionManager) {
    await sessionManager.stopAll();
    sessionManager.dispose();
  }
  if (sidecarManager) {
    await sidecarManager.shutdown();
  }
});

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test("sidecar binary is present", () => {
  assert.ok(binaryExists, `sidecar binary not found at ${sidecarBinary} — run cargo build first`);
});

test("SidecarManager starts, spawns a session, writes, reads output, and stops", { skip: !binaryExists }, async () => {
  const { SidecarPty } = await import("../sidecar.mjs");

  const pty = new SidecarPty(sidecarManager, "smoke-s1", {
    command: "/bin/cat",
    args: [],
    cols: 40,
    rows: 5,
  });
  await pty.spawn();
  assert.ok(pty.pid != null, "should have a pid after spawn");
  assert.equal(pty.cols, 40);
  assert.equal(pty.rows, 5);

  const outputChunks = [];
  let exited = false;
  let exitInfo = null;
  pty.onData((data) => outputChunks.push(data));
  pty.onExit((info) => {
    exited = true;
    exitInfo = info;
  });

  // Write and wait for echo
  await pty.write("hello\r\n");
  await new Promise((resolve) => setTimeout(resolve, 100));
  const output = outputChunks.join("");
  assert.ok(output.includes("hello"), `expected output to include "hello", got: ${JSON.stringify(output)}`);

  // Resize
  await pty.resize(60, 8);
  assert.equal(pty.cols, 60);
  assert.equal(pty.rows, 8);

  // Kill — note: killed processes typically have non-zero exit codes
  await pty.kill();
  await new Promise((resolve) => setTimeout(resolve, 500));
  assert.ok(exited, "should have received exit event");
  assert.ok(exitInfo != null, "should have exit info");
});

test("SidecarPty buffers data until onData is registered", { skip: !binaryExists }, async () => {
  const { SidecarPty } = await import("../sidecar.mjs");

  const pty = new SidecarPty(sidecarManager, "buffer-s2", {
    command: "/bin/cat",
    args: [],
    cols: 80,
    rows: 4,
  });
  await pty.spawn();

  // Write data BEFORE registering onData
  await pty.write("buffered\r\n");
  await new Promise((r) => setTimeout(r, 80));

  // Now register onData — should flush buffer
  const outputChunks = [];
  pty.onData((data) => outputChunks.push(data));

  const output = outputChunks.join("");
  assert.ok(output.includes("buffered"), `expected buffered output, got: ${JSON.stringify(output)}`);

  await pty.kill();
});

test("TerminalSession + TerminalSessionManager with sidecar starts, captures output, resizes, and stops", { skip: !binaryExists }, async () => {
  const { createSidecarPtyFactory } = await import("../sidecar.mjs");
  const { TerminalSessionManager } = await import("../terminal_session.mjs");

  const mgr = new TerminalSessionManager({
    env: {
      ...process.env,
      GARAZYK_PTY_MCP_ALLOW: "/bin/cat",
    },
    ptyFactory: createSidecarPtyFactory(sidecarBinary),
  });

  try {
    const session = await mgr.create({
      command: "/bin/cat",
      cols: 30,
      rows: 5,
      cwd: process.cwd(),
      title: "ts-cat",
    });

    assert.equal(session.sessionId, "s1");
    assert.ok(session.pid != null, "should have a pid");

    await session.type("hello-ts\r");
    const snapshot = session.snapshot();
    assert.ok(
      snapshot.lines.some((line) => line.includes("hello-ts")),
      `expected output to contain "hello-ts", got lines: ${JSON.stringify(snapshot.lines)}`,
    );

    session.resize(50, 8);
    assert.equal(session.cols, 50);
    assert.equal(session.rows, 8);

    const semRes = session.semanticSnapshot("compact", false);
    assert.ok(semRes.snapshot, "should have semantic snapshot");

    await mgr.stop("s1");
    assert.equal(mgr.list().length, 0);
  } finally {
    await mgr.stopAll();
    mgr.dispose();
  }
});

test("TerminalSession with sidecar supports recording", { skip: !binaryExists }, async () => {
  const { createSidecarPtyFactory } = await import("../sidecar.mjs");
  const { TerminalSessionManager } = await import("../terminal_session.mjs");
  const { AsciicastRecorder } = await import("../recording.mjs");

  const mgr = new TerminalSessionManager({
    env: {
      ...process.env,
      GARAZYK_PTY_MCP_ALLOW: "/bin/cat",
    },
    ptyFactory: createSidecarPtyFactory(sidecarBinary),
  });

  const outputDir = fs.mkdtempSync(path.join(os.tmpdir(), "garazyk-pty-sidecar-rec-"));

  try {
    const session = await mgr.create({
      command: "/bin/cat",
      cols: 30,
      rows: 4,
      title: "rec-test",
    });

    const recorder = new AsciicastRecorder({
      outputDir,
      cols: session.cols,
      rows: session.rows,
      title: "sidecar-rec-test",
      recordInput: true,
      command: "/bin/cat",
    });
    session.attachRecording(recorder);

    await session.type("recorded\r");

    const rec = session.detachRecording();
    assert.ok(rec, "should have a recorder");
    await rec.close();

    assert.ok(fs.existsSync(recorder.castPath), "cast file should exist");
    const castLines = fs.readFileSync(recorder.castPath, "utf8").trim().split("\n");
    assert.equal(JSON.parse(castLines[0]).version, 2);
    assert.ok(castLines.some((line) => JSON.parse(line)[1] === "o"), "should have output events");
    assert.ok(fs.existsSync(recorder.htmlPath), "html file should exist");

    await mgr.stop(session.sessionId);
  } finally {
    await mgr.stopAll();
    mgr.dispose();
    try { fs.rmSync(outputDir, { recursive: true, force: true }); } catch {}
  }
});

test("duplicate sessionId on sidecar returns error", { skip: !binaryExists }, async () => {
  const { SidecarPty } = await import("../sidecar.mjs");

  const pty1 = new SidecarPty(sidecarManager, "dup-s3", {
    command: "/bin/cat",
    cols: 20,
    rows: 3,
  });
  await pty1.spawn();

  // Second spawn with same sessionId should fail
  const pty2 = new SidecarPty(sidecarManager, "dup-s3", {
    command: "/bin/cat",
    cols: 20,
    rows: 3,
  });

  try {
    await assert.rejects(
      () => pty2.spawn(),
      /session already exists/,
      "duplicate session should be rejected",
    );
  } finally {
    await pty1.kill();
  }
});

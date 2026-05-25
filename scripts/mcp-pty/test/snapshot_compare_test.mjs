/**
 * Snapshot comparison tests — sidecar vs node-pty visual parity.
 *
 * Starts the same command with both PTY backends, sends identical input,
 * and asserts the terminal snapshots produce equivalent output.
 */

import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { TerminalSessionManager } from "../terminal_session.mjs";
import { createSidecarPtyFactory, SidecarManager } from "../sidecar.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const sidecarBinary = path.resolve(
  __dirname, "..", "..", "mcp-pty-rs", "target", "debug", "garazyk-ptyd",
);
const binaryExists = fs.existsSync(sidecarBinary);

const sharedBinCheck = { skip: !binaryExists };
let sidecarFactory = null;

// ---------------------------------------------------------------------------
// Test lifecycle
// ---------------------------------------------------------------------------

test.before(() => {
  if (!binaryExists) return;
  sidecarFactory = createSidecarPtyFactory(sidecarBinary);
});

test.after(async () => {
  // Shut down the sidecar singleton so the Node test runner can exit cleanly.
  await SidecarManager.dispose();
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Spawn /bin/cat, type text, capture a snapshot, then stop the session.
 * Creates and disposes its own TerminalSessionManager for isolation.
 */
async function captureCatOutput(ptyFactory) {
  const mgr = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: "/bin/cat" },
    ptyFactory,
  });

  try {
    const session = await mgr.create({ command: "/bin/cat", cols: 40, rows: 5 });
    await session.settle(200);

    const input = "abcdefghijklmnop";
    await session.type(input + "\r");
    await session.settle(200);
    const snap = session.snapshot();

    await session.type("\x04"); // ctrl+d (EOF)
    await session.settle(300);
    try { await mgr.stop(session.sessionId); } catch {}
    return snap;
  } finally {
    mgr.dispose();
  }
}

function normalizeLines(lines) {
  return lines
    .map((l) => l.replace(/\s+$/, ""))
    .filter((l, i, arr) => {
      if (l.length > 0) return true;
      const before = arr.slice(0, i).some((x) => x.trim().length > 0);
      const after = arr.slice(i + 1).some((x) => x.trim().length > 0);
      return before && after;
    });
}

function stripAnsi(s) {
  return s.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "").trim();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test("content parity: both backends echo back typed input", sharedBinCheck, async () => {
  const nodePtySnap = await captureCatOutput(null);
  const sidecarSnap = await captureCatOutput(sidecarFactory);

  const nodeLines = normalizeLines(nodePtySnap.lines);
  const sidecarLines = normalizeLines(sidecarSnap.lines);

  assert.ok(nodeLines.some((l) => l.includes("abcdefghijklmnop")),
    `node-pty output should contain typed text`);
  assert.ok(sidecarLines.some((l) => l.includes("abcdefghijklmnop")),
    `sidecar output should contain typed text`);

  const nodeEcho = nodeLines.filter((l) => l.length > 0).find((l) => l.includes("abcdefghijklmnop"));
  const sidecarEcho = sidecarLines.filter((l) => l.length > 0).find((l) => l.includes("abcdefghijklmnop"));

  assert.ok(nodeEcho && sidecarEcho, "both backends should echo back input");
  assert.equal(stripAnsi(nodeEcho), stripAnsi(sidecarEcho),
    `echoed text should match: node="${stripAnsi(nodeEcho)}" sidecar="${stripAnsi(sidecarEcho)}"`);
});

test("dimensions: both backends report correct cols/rows", sharedBinCheck, async () => {
  const nodePtySnap = await captureCatOutput(null);
  const sidecarSnap = await captureCatOutput(sidecarFactory);

  assert.equal(nodePtySnap.cols, 40, "node-pty cols");
  assert.equal(nodePtySnap.rows, 5, "node-pty rows");
  assert.equal(sidecarSnap.cols, 40, "sidecar cols");
  assert.equal(sidecarSnap.rows, 5, "sidecar rows");
});

test("running state: both backends report running after spawn", sharedBinCheck, async () => {
  const nodeMgr = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: "/bin/cat" },
  });
  const sidecarMgr = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: "/bin/cat" },
    ptyFactory: sidecarFactory,
  });

  try {
    const ns = await nodeMgr.create({ command: "/bin/cat", cols: 20, rows: 4 });
    const ss = await sidecarMgr.create({ command: "/bin/cat", cols: 20, rows: 4 });
    await ns.settle(200);
    await ss.settle(200);

    assert.equal(ns.snapshot().running, true, "node-pty should report running");
    assert.equal(ss.snapshot().running, true, "sidecar should report running");

    await nodeMgr.stop(ns.sessionId);
    await sidecarMgr.stop(ss.sessionId);
  } finally {
    nodeMgr.dispose();
    sidecarMgr.dispose();
  }
});

test("after kill: both backends report not running after stop", sharedBinCheck, async () => {
  const nodeMgr = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: "/bin/cat" },
  });
  const sidecarMgr = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: "/bin/cat" },
    ptyFactory: sidecarFactory,
  });

  try {
    const ns = await nodeMgr.create({ command: "/bin/cat", cols: 20, rows: 4 });
    const ss = await sidecarMgr.create({ command: "/bin/cat", cols: 20, rows: 4 });
    await ns.settle(200);
    await ss.settle(200);

    await nodeMgr.stop(ns.sessionId);
    await sidecarMgr.stop(ss.sessionId);

    // Poll until both report not-running (exit event may be asynchronous)
    const deadline = Date.now() + 2000;
    let nr = true, sr = true;
    while ((nr || sr) && Date.now() < deadline) {
      await new Promise((r) => setTimeout(r, 50));
      nr = ns.snapshot().running;
      sr = ss.snapshot().running;
    }

    assert.equal(ns.snapshot().running, false, "node-pty should report not running after stop");
    assert.equal(ss.snapshot().running, false, "sidecar should report not running after stop");
  } finally {
    nodeMgr.dispose();
    sidecarMgr.dispose();
  }
});

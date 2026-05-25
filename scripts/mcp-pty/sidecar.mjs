/**
 * Sidecar adapter for garazyk-ptyd — the Rust PTY sidecar.
 *
 * Spawns the binary once and exposes a `SidecarPty` class that mimics the
 * `node-pty` interface (`onData`, `onExit`, `write`, `resize`, `kill`, `pid`).
 * Output bytes arrive base64-encoded and are decoded to UTF-8 strings before
 * being passed to the registered `onData` callback.
 *
 * Keep allowlisting, session lifecycle, and recording in the MCP process.
 * The sidecar intentionally does **not** implement allowlisting.
 *
 * @module mcp-pty/sidecar
 */

import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

// ---------------------------------------------------------------------------
// SidecarManager — singleton that owns the child process
// ---------------------------------------------------------------------------

let nextRequestId = 1;
let managerInstance = null;

export function getSidecarManager(binaryPath) {
  if (!managerInstance) {
    managerInstance = new SidecarManager(binaryPath);
  }
  return managerInstance;
}

export class SidecarManager {
  /**
   * @param {string} [binaryPath]
   *   Path to the `garazyk-ptyd` binary. Defaults to
   *   `GARAZYK_PTY_SIDECAR_BINARY` env var or `garazyk-ptyd` from PATH.
   */
  constructor(binaryPath = process.env.GARAZYK_PTY_SIDECAR_BINARY || "garazyk-ptyd") {
    this.binaryPath = binaryPath;
    /** @type {import("node:child_process").ChildProcess|null} */
    this.proc = null;
    /** @type {Map<string, { resolve: Function, reject: Function }>} */
    this.pending = new Map();
    /** @type {Map<string, import("./sidecar.mjs").SidecarPty>} */
    this.sessions = new Map();
    this.dead = false;
  }

  /**
   * Lazily spawn the sidecar process if not already running.
   * @throws {Error} if the sidecar has exited and cannot be restarted.
   */
  _ensureStarted() {
    if (this.dead) throw new Error("sidecar has exited");
    if (this.proc) return;

    this.proc = spawn(this.binaryPath, [], {
      stdio: ["pipe", "pipe", "inherit"],
      // Inherit environment so TERM, PATH, etc. are available
      env: process.env,
    });

    this._rl = createInterface({ input: this.proc.stdout });

    this._rl.on("line", (line) => {
      if (!line.trim()) return;
      let msg;
      try {
        msg = JSON.parse(line);
      } catch {
        return;
      }

      if (msg.event) {
        // Route event to the owning session
        const session = this.sessions.get(msg.sessionId);
        if (session) {
          session._handleEvent(msg.event, msg);
        }
      } else if (msg.id !== undefined) {
        // Route response to the pending request
        const pending = this.pending.get(msg.id);
        if (pending) {
          this.pending.delete(msg.id);
          if (msg.ok) {
            pending.resolve(msg.result);
          } else {
            pending.reject(new Error(msg.error || "unknown sidecar error"));
          }
        }
      }
    });

    this.proc.on("exit", (code) => {
      this.dead = true;
      try { this._rl?.close(); } catch {}
      this.proc = null;

      // Reject all pending requests
      for (const [id, pending] of this.pending) {
        pending.reject(
          new Error(`sidecar exited with code ${code != null ? code : "null"}`),
        );
        this.pending.delete(id);
      }

      // Notify all sessions of exit
      for (const [sid, session] of this.sessions) {
        session._handleEvent("exit", { exitCode: 1, signal: null });
      }
    });

    this.proc.stdin.on("error", (err) => {
      if (!this.dead) {
        console.error(`sidecar stdin error: ${err.message}`);
      }
    });
  }

  /**
   * Send a JSONL command to the sidecar and wait for the response.
   * @param {object} command
   * @returns {Promise<any>}
   */
  async _send(command) {
    this._ensureStarted();
    const id = String(nextRequestId++);
    const line = JSON.stringify({ id, ...command });

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error(`sidecar request ${id} timed out after 10s`));
        }
      }, 10_000);

      // Register callbacks that clear the safety timer on resolution
      this.pending.set(id, {
        resolve: (val) => { clearTimeout(timer); resolve(val); },
        reject: (err) => { clearTimeout(timer); reject(err); },
      });

      this.proc.stdin.write(line + "\n", (err) => {
        if (err) {
          clearTimeout(timer);
          this.pending.delete(id);
          reject(err);
        }
      });
    });
  }

  /**
   * Gracefully shutdown all sessions and terminate the sidecar process.
   */
  async shutdown() {
    if (this.dead || !this.proc) return;
    // Send shutdown with a short timeout — sidecar may exit before responding
    try {
      await Promise.race([
        this._send({ op: "shutdown" }),
        new Promise((_, reject) => setTimeout(() => reject(new Error("shutdown timed out")), 3000)),
      ]);
    } catch {
      // Best effort
    }
    this.dead = true;
    // Close readline interface and pipes to release event loop references
    try { this._rl?.close(); } catch {}
    try { this.proc.stdin.end(); } catch {}
    try { this.proc.kill(); } catch {}
    this.proc = null;
  }

  /**
   * Dispose the global singleton. Returns a promise that resolves when
   * the sidecar process has exited (or after a best-effort timeout).
   */
  static async dispose() {
    if (managerInstance) {
      const instance = managerInstance;
      managerInstance = null;
      await instance.shutdown().catch(() => {});
    }
  }
}

// ---------------------------------------------------------------------------
// SidecarPty — node-pty-compatible interface backed by the sidecar
// ---------------------------------------------------------------------------

export class SidecarPty {
  /**
   * @param {SidecarManager} manager
   * @param {string} sessionId
   * @param {object} opts
   * @param {string} opts.command
   * @param {string[]} [opts.args]
   * @param {number} [opts.cols]
   * @param {number} [opts.rows]
   * @param {string} [opts.cwd]
   * @param {Record<string,string>} [opts.env]
   */
  constructor(manager, sessionId, opts) {
    this.manager = manager;
    this.sessionId = sessionId;
    this.command = opts.command;
    this.args = opts.args || [];
    this.cols = opts.cols || 80;
    this.rows = opts.rows || 24;
    this.cwd = opts.cwd;
    this.env = opts.env;
    /** @type {number|null} */
    this.pid = null;

    // Callbacks matching node-pty signature
    /** @type {(data: string) => void|null} */
    this._onData = null;
    /** @type {(info: { exitCode: number, signal: string|null }) => void|null} */
    this._onExit = null;

    // Buffer events that arrive before handlers are registered (brief gap
    // between spawn completing and TerminalSession wiring onData/onExit).
    // Capped at ~256 KiB to avoid unbounded growth if onData is never attached.
    this._dataBuffer = [];
    this._exitBuffer = null;

    this._spawned = false;
  }

  /**
   * Spawn the PTY session via the sidecar.
   * Returns `this` so callers can chain `.onData()` / `.onExit()`.
   * @returns {Promise<SidecarPty>}
   */
  async spawn() {
    if (this._spawned) return this;

    // Only pass env if non-empty (sidecar omits the field otherwise)
    const envObj = this.env && Object.keys(this.env).length > 0 ? { ...this.env } : undefined;
    const result = await this.manager._send({
      op: "start",
      sessionId: this.sessionId,
      command: this.command,
      args: this.args,
      cwd: this.cwd,
      env: envObj,
      cols: this.cols,
      rows: this.rows,
    });

    this.pid = result.pid;
    this.manager.sessions.set(this.sessionId, this);
    this._spawned = true;
    return this;
  }

  /** @param {(data: string) => void} cb */
  onData(cb) {
    this._onData = cb;
    // Flush any buffered data that arrived before the handler was registered
    for (const encoded of this._dataBuffer) {
      this._onData(Buffer.from(encoded, "base64").toString("utf8"));
    }
    this._dataBuffer = [];
  }

  /** @param {(info: { exitCode: number, signal: string|null }) => void} cb */
  onExit(cb) {
    this._onExit = cb;
    if (this._exitBuffer) {
      this._onExit(this._exitBuffer);
      this._exitBuffer = null;
    }
  }

  /**
   * Handle an incoming event from the sidecar.
   * @param {string} event
   * @param {object} msg
   * @internal
   */
  _handleEvent(event, msg) {
    switch (event) {
      case "output": {
        if (this._onData) {
          this._onData(Buffer.from(msg.data, "base64").toString("utf8"));
        } else if (this._dataBuffer.length < 512) {
          // Soft cap: ~256 KiB (512 × 512 B average chunk)
          this._dataBuffer.push(msg.data);
        }
        break;
      }
      case "exit": {
        this.manager.sessions.delete(this.sessionId);
        const exitInfo = { exitCode: msg.exitCode, signal: msg.signal || null };
        if (this._onExit) {
          this._onExit(exitInfo);
        } else {
          this._exitBuffer = exitInfo;
        }
        break;
      }
      case "error": {
        this.manager.sessions.delete(this.sessionId);
        const exitInfo = { exitCode: 1, signal: null };
        if (this._onExit) {
          this._onExit(exitInfo);
        } else {
          this._exitBuffer = exitInfo;
        }
        break;
      }
      default:
        // Unknown event — ignore
        break;
    }
  }

  /**
   * Write data to the PTY.
   * Accepts strings (like node-pty); base64-encodes for the JSONL protocol.
   * @param {string} data
   * @returns {Promise<void>}
   */
  write(data) {
    const b64 = Buffer.from(data, "utf8").toString("base64");
    return this.manager._send({
      op: "write",
      sessionId: this.sessionId,
      data: b64,
      base64: true,
    });
  }

  /**
   * Resize the PTY.
   * @param {number} cols
   * @param {number} rows
   * @returns {Promise<void>}
   */
  resize(cols, rows) {
    this.cols = cols;
    this.rows = rows;
    return this.manager._send({
      op: "resize",
      sessionId: this.sessionId,
      cols,
      rows,
    });
  }

  /**
   * Kill the PTY session.
   * Resolves only after the sidecar confirms exit (via exit event) or
   * after a bounded timeout. This ensures TerminalSession.stop() can
   * observe running→false before proceeding.
   * @param {string} [_signal] — ignored; sidecar always kills via ChildKiller
   * @returns {Promise<void>}
   */
  kill(_signal) {
    if (this.manager.dead) return Promise.resolve();
    return this.manager._send({
      op: "stop",
      sessionId: this.sessionId,
    }).then(() => {
      // Wait for the async exit event to arrive, or time out.
      return new Promise((resolve) => {
        const originalOnExit = this._onExit;
        let settled = false;
        const done = () => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          this._onExit = originalOnExit;
          resolve();
        };
        const timer = setTimeout(done, 3000);
        this._onExit = (info) => {
          done();
          if (originalOnExit) originalOnExit(info);
        };
        if (this._exitBuffer) {
          const buffered = this._exitBuffer;
          this._exitBuffer = null;
          done();
          if (originalOnExit) originalOnExit(buffered);
        }
      });
    }).catch(() => {
      // Best effort — child may have already exited
    });
  }
}

// ---------------------------------------------------------------------------
// Factory — creates a PTY instance for use by TerminalSessionManager
// ---------------------------------------------------------------------------

/**
 * Returns an async factory function suitable for `TerminalSessionManager`'s
 * `ptyFactory` option.
 *
 * @param {string} [binaryPath]
 * @returns {(options: object) => Promise<SidecarPty>}
 */
export function createSidecarPtyFactory(binaryPath) {
  const mgr = getSidecarManager(binaryPath);
  return async (options) => {
    const pty = new SidecarPty(mgr, options.sessionId, options);
    await pty.spawn();
    return pty;
  };
}

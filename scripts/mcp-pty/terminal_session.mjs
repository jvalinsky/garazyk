import os from "node:os";
import path from "node:path";
import pty from "node-pty";
import xtermHeadless from "@xterm/headless";

const { Terminal } = xtermHeadless;

const DEFAULT_COLS = 80;
const DEFAULT_ROWS = 24;
const DEFAULT_TERM = "xterm-256color";
const DEFAULT_IDLE_MS = 10 * 60 * 1000;
const DEFAULT_MAX_SESSIONS = 4;

const DEFAULT_ALLOWLIST = [
  "/usr/bin/top",
  "/usr/bin/less",
  "/usr/bin/vim",
  "/usr/bin/vi",
  "/usr/bin/nano",
  "/opt/homebrew/bin/htop",
  "/usr/bin/htop",
  "/etc/profiles/per-user/jack/bin/btop",
];

const SHELL_NAMES = new Set(["sh", "bash", "zsh"]);

const KEY_BYTES = new Map([
  ["enter", "\r"],
  ["return", "\r"],
  ["tab", "\t"],
  ["escape", "\x1b"],
  ["esc", "\x1b"],
  ["backspace", "\x7f"],
  ["up", "\x1b[A"],
  ["down", "\x1b[B"],
  ["right", "\x1b[C"],
  ["left", "\x1b[D"],
  ["ctrl-c", "\x03"],
  ["ctrl-d", "\x04"],
  ["ctrl-z", "\x1a"],
  ["ctrl-l", "\x0c"],
]);

function positiveInt(value, fallback, min = 1, max = 1000) {
  const n = Number(value);
  if (!Number.isInteger(n) || n < min || n > max) return fallback;
  return n;
}

export function encodeKey(name) {
  const key = String(name ?? "").toLowerCase();
  const bytes = KEY_BYTES.get(key);
  if (bytes === undefined) {
    throw new Error(`Unsupported key: ${name}`);
  }
  return bytes;
}

export function parseAllowlist(env = process.env) {
  const extra = String(env.GARAZYK_PTY_MCP_ALLOW ?? "")
    .split(":")
    .map((entry) => entry.trim())
    .filter(Boolean);
  return new Set([...DEFAULT_ALLOWLIST, ...extra]);
}

export function isShellEntrypoint(command) {
  return SHELL_NAMES.has(path.basename(command));
}

export function validateCommand(command, env = process.env) {
  if (typeof command !== "string" || command.length === 0) {
    throw new Error("command is required");
  }
  if (!path.isAbsolute(command)) {
    throw new Error("command must be an absolute path");
  }
  if (isShellEntrypoint(command) && env.GARAZYK_PTY_MCP_ALLOW_SHELL !== "1") {
    throw new Error("shell entrypoints are blocked unless GARAZYK_PTY_MCP_ALLOW_SHELL=1");
  }
  if (!parseAllowlist(env).has(command)) {
    throw new Error(`command is not allowlisted: ${command}`);
  }
  return command;
}

function coerceArgs(args) {
  if (args === undefined) return [];
  if (!Array.isArray(args)) throw new Error("args must be an array");
  return args.map((arg) => {
    if (typeof arg !== "string") throw new Error("args entries must be strings");
    return arg;
  });
}

function coerceEnv(env) {
  if (env === undefined) return {};
  if (env === null || typeof env !== "object" || Array.isArray(env)) {
    throw new Error("env must be an object");
  }
  const result = {};
  for (const [key, value] of Object.entries(env)) {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
      throw new Error(`invalid env key: ${key}`);
    }
    if (typeof value !== "string") {
      throw new Error(`env value for ${key} must be a string`);
    }
    result[key] = value;
  }
  return result;
}

function applyXtermWrite(term, data) {
  return new Promise((resolve) => {
    term.write(data, resolve);
  });
}

function escapeYamlDoubleQuoted(value) {
  return String(value)
    .replaceAll("\\", "\\\\")
    .replaceAll("\"", "\\\"")
    .replaceAll("\x1b", "\\x1b")
    .replaceAll("\r", "\\r")
    .replaceAll("\n", "\\n");
}

export function snapshotToYaml(snapshot) {
  const state = snapshot.running ? "running" : `stopped exitCode=${snapshot.exitCode ?? "unknown"}`;
  const title = escapeYamlDoubleQuoted(snapshot.title ?? path.basename(snapshot.command ?? "terminal"));
  const lines = [
    `- terminal "${title}" [session=${snapshot.sessionId}] [pid=${snapshot.pid ?? "none"}] [${state}] [box=0,0,${snapshot.cols},${snapshot.rows}]`,
  ];
  snapshot.lines.forEach((line, index) => {
    lines.push(`  - line ${index + 1} "${escapeYamlDoubleQuoted(line)}"`);
  });
  return `${lines.join("\n")}\n`;
}

export class TerminalSession {
  constructor(options) {
    this.sessionId = options.sessionId;
    this.command = options.command;
    this.args = options.args;
    this.cwd = options.cwd;
    this.title = options.title ?? path.basename(options.command);
    this.cols = options.cols;
    this.rows = options.rows;
    this.running = true;
    this.exitCode = undefined;
    this.signal = undefined;
    this.lastActivity = Date.now();
    this.recording = null;
    this.outputDisposables = [];
    this.writeQueue = Promise.resolve();

    this.term = new Terminal({
      cols: this.cols,
      rows: this.rows,
      allowProposedApi: true,
    });

    this.pty = pty.spawn(this.command, this.args, {
      name: options.termName,
      cols: this.cols,
      rows: this.rows,
      cwd: this.cwd,
      env: options.env,
    });
    this.pid = this.pty.pid;

    this.pty.onData((data) => {
      this.lastActivity = Date.now();
      this.writeQueue = this.writeQueue.then(() => applyXtermWrite(this.term, data));
      if (this.recording) this.recording.recordOutput(data);
    });

    this.pty.onExit(({ exitCode, signal }) => {
      this.running = false;
      this.exitCode = exitCode;
      this.signal = signal;
      if (this.recording) this.recording.close();
    });
  }

  async settle(ms = 50) {
    await this.writeQueue;
    await new Promise((resolve) => setTimeout(resolve, ms));
    await this.writeQueue;
  }

  async write(data, recordInput = true) {
    if (!this.running) throw new Error("session is not running");
    this.lastActivity = Date.now();
    this.pty.write(data);
    if (recordInput && this.recording) this.recording.recordInput(data);
    await this.settle();
  }

  async pressKey(keyName) {
    await this.write(encodeKey(keyName));
  }

  async type(text) {
    if (typeof text !== "string") throw new Error("value must be a string");
    await this.write(text);
  }

  async rawWrite(value) {
    if (typeof value !== "string") throw new Error("value must be a string");
    await this.write(value);
  }

  resize(cols, rows) {
    this.cols = positiveInt(cols, this.cols, 1, 400);
    this.rows = positiveInt(rows, this.rows, 1, 200);
    this.term.resize(this.cols, this.rows);
    if (this.running) this.pty.resize(this.cols, this.rows);
    if (this.recording) this.recording.recordResize(this.cols, this.rows);
    this.lastActivity = Date.now();
  }

  snapshot() {
    const buffer = this.term.buffer.active;
    const lines = [];
    for (let row = 0; row < this.rows; row += 1) {
      const line = buffer.getLine(buffer.viewportY + row);
      lines.push(line ? line.translateToString(true) : "");
    }
    return {
      sessionId: this.sessionId,
      pid: this.pid,
      command: this.command,
      args: this.args,
      title: this.title,
      cols: this.cols,
      rows: this.rows,
      cursor: {
        x: buffer.cursorX,
        y: buffer.cursorY,
      },
      lines,
      running: this.running,
      exitCode: this.exitCode,
      signal: this.signal,
    };
  }

  attachRecording(recorder) {
    if (this.recording) throw new Error("recording already active");
    this.recording = recorder;
  }

  detachRecording() {
    const recorder = this.recording;
    this.recording = null;
    return recorder;
  }

  stop({ signal = "SIGTERM", killAfterMs = 500, force = true } = {}) {
    if (!this.running) return Promise.resolve();
    this.pty.kill(signal);
    return new Promise((resolve) => {
      const started = Date.now();
      let escalated = false;
      const timer = setInterval(() => {
        if (!this.running) {
          clearInterval(timer);
          resolve();
          return;
        }
        if (force && !escalated && Date.now() - started >= killAfterMs) {
          escalated = true;
          this.pty.kill("SIGKILL");
        }
        if (escalated && Date.now() - started >= killAfterMs + 500) {
          clearInterval(timer);
          resolve();
        }
      }, 25);
    });
  }
}

export class TerminalSessionManager {
  constructor({ env = process.env, idleMs = DEFAULT_IDLE_MS } = {}) {
    this.env = env;
    this.sessions = new Map();
    this.nextId = 1;
    this.maxSessions = positiveInt(env.GARAZYK_PTY_MCP_MAX_SESSIONS, DEFAULT_MAX_SESSIONS, 1, 64);
    this.idleMs = idleMs;
    this.reaper = setInterval(() => {
      void this.stopIdleSessions();
    }, Math.min(this.idleMs, 60_000));
    this.reaper.unref?.();
  }

  create(params = {}) {
    if (this.sessions.size >= this.maxSessions) {
      throw new Error(`maximum live sessions reached (${this.maxSessions})`);
    }

    const command = validateCommand(params.command, this.env);
    const args = coerceArgs(params.args);
    const cols = positiveInt(params.cols, DEFAULT_COLS, 1, 400);
    const rows = positiveInt(params.rows, DEFAULT_ROWS, 1, 200);
    const cwd = params.cwd === undefined ? process.cwd() : String(params.cwd);
    if (!path.isAbsolute(cwd)) throw new Error("cwd must be an absolute path");
    const childEnv = {
      ...process.env,
      ...coerceEnv(params.env),
      TERM: String(params.env?.TERM ?? DEFAULT_TERM),
    };
    const sessionId = `s${this.nextId++}`;
    const session = new TerminalSession({
      sessionId,
      command,
      args,
      cwd,
      cols,
      rows,
      title: typeof params.title === "string" ? params.title : undefined,
      env: childEnv,
      termName: childEnv.TERM,
    });
    this.sessions.set(sessionId, session);
    return session;
  }

  get(sessionId) {
    const session = this.sessions.get(String(sessionId));
    if (!session) throw new Error(`unknown session: ${sessionId}`);
    return session;
  }

  list() {
    return [...this.sessions.values()].map((session) => ({
      sessionId: session.sessionId,
      pid: session.pid,
      title: session.title,
      command: session.command,
      cols: session.cols,
      rows: session.rows,
      running: session.running,
      exitCode: session.exitCode,
      idleMs: Date.now() - session.lastActivity,
    }));
  }

  async stop(sessionId, options) {
    const session = this.get(sessionId);
    await session.stop(options);
    this.sessions.delete(session.sessionId);
    return session;
  }

  async stopIdleSessions() {
    const now = Date.now();
    for (const session of this.sessions.values()) {
      if (now - session.lastActivity >= this.idleMs) {
        await session.stop({ force: true });
        this.sessions.delete(session.sessionId);
      }
    }
  }

  async stopAll() {
    for (const session of [...this.sessions.values()]) {
      await session.stop({ force: true });
      this.sessions.delete(session.sessionId);
    }
  }

  dispose() {
    clearInterval(this.reaper);
  }
}

export const testInternals = {
  DEFAULT_ALLOWLIST,
  DEFAULT_COLS,
  DEFAULT_ROWS,
  DEFAULT_TERM,
  osPlatform: os.platform(),
};

import fs from "node:fs";
import path from "node:path";
import { buildAsciinemaOverlayHtml, splitSemanticCast } from "./semantic_overlay_html.mjs";

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function eventLine(time, kind, data) {
  return `${JSON.stringify([Number(time.toFixed(6)), kind, data])}\n`;
}

function htmlEscape(text) {
  return String(text)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;");
}

export class AsciicastRecorder {
  constructor({ outputDir, cols, rows, title, recordInput = false, semanticOverlay = false, command }) {
    this.outputDir = outputDir;
    this.cols = cols;
    this.rows = rows;
    this.title = title ?? "Garazyk PTY Capture";
    this.recordInputEnabled = recordInput === true;
    this.semanticOverlay = semanticOverlay === true;
    this.command = command;
    this.startedAt = Date.now();
    this.closed = false;

    ensureDir(outputDir);
    this.castPath = path.join(outputDir, "session.cast");
    this.htmlPath = path.join(outputDir, "index.html");
    this.stream = fs.createWriteStream(this.castPath, { encoding: "utf8" });
    this.stream.write(`${JSON.stringify({
      version: 2,
      width: cols,
      height: rows,
      timestamp: Math.floor(this.startedAt / 1000),
      title: this.title,
      env: { TERM: "xterm-256color", SHELL: "" },
      command,
    })}\n`);
    this.stream.write(eventLine(0, "r", `${cols}x${rows}`));
  }

  elapsedSeconds() {
    return (Date.now() - this.startedAt) / 1000;
  }

  recordOutput(data) {
    if (this.closed) return;
    this.stream.write(eventLine(this.elapsedSeconds(), "o", data));
  }

  recordInput(data) {
    if (this.closed || !this.recordInputEnabled) return;
    this.stream.write(eventLine(this.elapsedSeconds(), "i", data));
  }

  recordSemanticSnapshot(snapshot) {
    if (this.closed || !this.semanticOverlay) return;
    this.stream.write(eventLine(this.elapsedSeconds(), "s", snapshot));
  }

  recordResize(cols, rows) {
    if (this.closed) return;
    this.cols = cols;
    this.rows = rows;
    this.stream.write(eventLine(this.elapsedSeconds(), "r", `${cols}x${rows}`));
  }

  async close() {
    if (this.closed) return;
    this.closed = true;
    await new Promise((resolve, reject) => {
      this.stream.end((err) => (err ? reject(err) : resolve()));
    });
    const castContent = fs.readFileSync(this.castPath, "utf8");
    const { standardCast, semanticEvents } = splitSemanticCast(castContent);

    // Write the clean cast (no semantic events) for Asciinema Player to fetch
    const playbackCastPath = path.join(this.outputDir, "playback.cast");
    fs.writeFileSync(playbackCastPath, standardCast);

    // Write semantic events as a separate JSON file for the overlay to fetch
    if (semanticEvents.length > 0) {
      const semanticPath = path.join(this.outputDir, "semantic-events.json");
      fs.writeFileSync(semanticPath, JSON.stringify(semanticEvents));
    }

    const html = buildStandaloneHtml({
      title: this.title,
      castContent,
      semanticOverlay: this.semanticOverlay,
    });
    fs.writeFileSync(this.htmlPath, html);
  }
}

export function defaultRecordingDir(baseDir = process.cwd(), startedAt = Date.now()) {
  // Use second granularity to avoid per-scenario dir collisions in batch runs
  const epochS = Math.floor(startedAt / 1000);
  return path.join(baseDir, "scripts", "scenarios", "reports", "pty-capture", `mcp-${epochS}`);
}

export function buildStandaloneHtml({ title, castContent, semanticOverlay = false }) {
  return buildAsciinemaOverlayHtml({ title, castContent, semanticOverlay });
}

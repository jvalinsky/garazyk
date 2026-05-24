import fs from "node:fs";
import path from "node:path";

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
    fs.writeFileSync(this.htmlPath, buildStandaloneHtml({
      title: this.title,
      castContent,
      semanticOverlay: this.semanticOverlay,
    }));
  }
}

export function defaultRecordingDir(baseDir = process.cwd(), startedAt = Date.now()) {
  return path.join(baseDir, "scripts", "scenarios", "reports", "pty-capture", `mcp-${startedAt}`);
}

export function buildStandaloneHtml({ title, castContent, semanticOverlay = false }) {
  const encodedCast = Buffer.from(castContent, "utf8").toString("base64");
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${htmlEscape(title)}</title>
  <style>
    :root { color-scheme: dark; --bg: #0d1117; --surface: #161b22; --border: #30363d; --text: #e6edf3; --muted: #8b949e; }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif; }
    main { padding: 20px; max-width: 1400px; margin: 0 auto; }
    header { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 16px; }
    h1 { font-size: 18px; margin: 0; font-weight: 600; }
    .btn-group { display: flex; gap: 6px; }
    button { border: 1px solid var(--border); background: var(--surface); color: var(--text); padding: 6px 12px; font: inherit; font-size: 13px; cursor: pointer; border-radius: 6px; }
    button:hover { background: #1f2937; }
    button[aria-pressed="true"] { background: #1a4a6e; border-color: #388bfd; }

    .layout { display: grid; grid-template-columns: 1fr 280px; gap: 16px; }
    @media (max-width: 900px) { .layout { grid-template-columns: 1fr; } }

    .terminal-frame { position: relative; border: 1px solid var(--border); border-radius: 8px; overflow: hidden; background: #000; }
    #terminal { white-space: pre; padding: 12px; margin: 0; line-height: 1.4; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 13px; font-variant-ligatures: none; tab-size: 1; }
    #overlay { position: absolute; top: 12px; left: 12px; pointer-events: none; }

    /* ── Overlay element styles ── */
    .ov { position: absolute; border-radius: 3px; pointer-events: none; transition: opacity .15s; }
    .ov-popup { border: 1.5px solid #f0883e; background: rgba(240,136,62,.06); }
    .ov-popup .ov-label { background: #f0883e; color: #000; }
    .ov-pane { border: 1px dashed #484f58; background: transparent; }
    .ov-pane .ov-label { background: #484f58; color: #e6edf3; }
    .ov-list { border: 1px solid rgba(56,139,253,.5); background: rgba(56,139,253,.04); }
    .ov-list .ov-label { background: #388bfd; color: #fff; }
    .ov-item { border-left: 2px solid #388bfd; background: rgba(56,139,253,.06); border-radius: 0 3px 3px 0; }
    .ov-item .ov-label { background: #1a4a6e; color: #79c0ff; }
    .ov-item-selected { border-left: 2px solid #3fb950; background: rgba(63,185,80,.08); }
    .ov-item-selected .ov-label { background: #238636; color: #fff; }
    .ov-status { border: 1px solid #da3633; background: rgba(218,54,51,.06); }
    .ov-status .ov-label { background: #da3633; color: #fff; }
    .ov-table { border: 1px solid #a371f7; background: rgba(163,113,247,.04); }
    .ov-table .ov-label { background: #8957e5; color: #fff; }
    .ov-fact { border: 1px dotted #8b949e; background: transparent; }
    .ov-fact .ov-label { background: #484f58; color: #e6edf3; }
    .ov-cursor { border: 1.5px solid #3fb950; background: rgba(63,185,80,.18); border-radius: 2px; animation: cursor-blink 1.2s step-end infinite; }
    .ov-gameBoard { border: 1.5px solid #f0883e; background: rgba(240,136,62,.03); }
    .ov-gameBoard .ov-label { background: #f0883e; color: #000; }
    .ov-player { border: 2px solid #3fb950; background: rgba(63,185,80,.22); border-radius: 3px; animation: player-pulse 1.5s ease-in-out infinite; }
    .ov-player .ov-label { background: #238636; color: #fff; }
    @keyframes player-pulse { 0%,100% { box-shadow: 0 0 4px rgba(63,185,80,.4); } 50% { box-shadow: 0 0 12px rgba(63,185,80,.8); } }
    .ov-gameEntity { border-left: 2px solid #d2a8ff; background: rgba(210,168,255,.06); border-radius: 0 3px 3px 0; }
    .ov-gameEntity .ov-label { background: #8957e5; color: #fff; }
    .ov-scoreBar { border: 1px solid #58a6ff; background: rgba(88,166,255,.06); }
    .ov-scoreBar .ov-label { background: #1a4a6e; color: #79c0ff; }
    .ov-titleBar { border-bottom: 1px solid #484f58; background: transparent; }
    .ov-titleBar .ov-label { background: #484f58; color: #e6edf3; }
    .ov-cardGame { border: 1.5px solid #a371f7; background: rgba(163,113,247,.04); }
    .ov-cardGame .ov-label { background: #8957e5; color: #fff; }
    .ov-cardFace { border: 1px solid #58a6ff; background: rgba(88,166,255,.08); border-radius: 3px; }
    .ov-cardFace .ov-label { background: #1a4a6e; color: #79c0ff; font-size: 10px; }
    .ov-cardFace-red .ov-label { background: #6e1a1a; color: #ff7b72; }
    .ov-brailleChart { border: 1px solid #3fb950; background: rgba(63,185,80,.06); }
    .ov-brailleChart .ov-label { background: #238636; color: #fff; }
    .ov-blockBar { border: 1px solid #d29922; background: rgba(210,153,34,.06); }
    .ov-blockBar .ov-label { background: #9e6a03; color: #fff; }
    .ov-pipeMeter { border: 1px solid #58a6ff; background: rgba(88,166,255,.06); }
    .ov-pipeMeter .ov-label { background: #1a4a6e; color: #79c0ff; }
    @keyframes cursor-blink { 50% { opacity: .4; } }

    .ov-label { position: absolute; top: -18px; left: -1px; max-width: 32ch; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; padding: 1px 6px; font: 11px/1.3 ui-monospace, SFMono-Regular, Menlo, monospace; border-radius: 3px 3px 0 0; z-index: 1; }
    .ov-key-badge { position: absolute; bottom: -16px; right: 2px; padding: 0 4px; font: 10px/1.3 ui-monospace, SFMono-Regular, Menlo, monospace; background: rgba(0,0,0,.85); border-radius: 3px; white-space: nowrap; }

    /* ── Capabilities sidebar ── */
    .sidebar { display: flex; flex-direction: column; gap: 12px; }
    .cap-card { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 12px; }
    .cap-card h3 { font-size: 11px; text-transform: uppercase; letter-spacing: .05em; color: var(--muted); margin: 0 0 8px 0; }
    .cap-row { display: flex; align-items: center; gap: 6px; margin-bottom: 4px; font-size: 12px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    .cap-key { display: inline-flex; align-items: center; justify-content: center; min-width: 22px; height: 20px; padding: 0 5px; background: #1a4a6e; color: #79c0ff; border: 1px solid #388bfd; border-radius: 4px; font-size: 11px; font-weight: 600; }
    .cap-action { color: var(--text); }
    .cap-source { color: var(--muted); font-size: 10px; margin-left: auto; }
    .app-badge { display: inline-flex; align-items: center; gap: 6px; padding: 4px 10px; background: #1a4a6e; border: 1px solid #388bfd; border-radius: 6px; font-size: 13px; font-weight: 600; color: #79c0ff; }
    .fw-badge { display: inline-flex; padding: 2px 8px; background: #1a1e23; border: 1px solid var(--border); border-radius: 4px; font-size: 11px; color: var(--muted); }
    .conf-bar { height: 4px; background: #1a1e23; border-radius: 2px; margin-top: 6px; overflow: hidden; }
    .conf-fill { height: 100%; background: #3fb950; border-radius: 2px; transition: width .3s; }

    #meta { color: var(--muted); font-size: 12px; margin-top: 10px; }
    #measure { position: absolute; visibility: hidden; white-space: pre; left: -1000px; top: -1000px; display: inline-block; line-height: 1.4; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 13px; font-variant-ligatures: none; tab-size: 1; }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>${htmlEscape(title)}</h1>
      <div class="btn-group">
        <button id="play" type="button">▶ Play</button>
        <button id="reset" type="button">⟲ Reset</button>
        <button id="toggle-overlay" type="button" aria-pressed="${semanticOverlay ? "true" : "false"}">🔍 Overlay</button>
      </div>
    </header>
    <div class="layout">
      <div>
        <div class="terminal-frame" id="terminal-frame">
          <pre id="terminal" aria-label="Terminal replay"></pre>
          <div id="overlay" aria-hidden="true"></div>
        </div>
        <div id="meta"></div>
      </div>
      <div class="sidebar" id="sidebar">
        <div class="cap-card" id="app-card">
          <h3>Application</h3>
          <div id="app-info">—</div>
        </div>
        <div class="cap-card" id="nav-card">
          <h3>Navigate</h3>
          <div id="nav-info">—</div>
        </div>
        <div class="cap-card" id="actions-card">
          <h3>Actions</h3>
          <div id="actions-info">—</div>
        </div>
        <div class="cap-card" id="quit-card">
          <h3>Quit / Dismiss</h3>
          <div id="quit-info">—</div>
        </div>
        <div class="cap-card" id="game-card" style="display:none">
          <h3>Game</h3>
          <div id="game-info">—</div>
        </div>
        <div class="card">
          <h3>Charts</h3>
          <div id="chart-info">—</div>
        </div>
      </div>
    </div>
    <span id="measure">MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM</span>
  </main>
  <script id="cast" type="application/octet-stream">${encodedCast}</script>
  <script>
    function decodeBase64Utf8(value) {
      const binary = atob(value);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
      return new TextDecoder().decode(bytes);
    }

    const raw = decodeBase64Utf8(document.getElementById("cast").textContent.trim());
    const rows = raw.trimEnd().split("\\n").map((line) => JSON.parse(line));
    const header = rows[0] || {};
    const events = rows.slice(1);
    const terminal = document.getElementById("terminal");
    const overlay = document.getElementById("overlay");
    const measure = document.getElementById("measure");
    const meta = document.getElementById("meta");
    const play = document.getElementById("play");
    const reset = document.getElementById("reset");
    const toggleOverlay = document.getElementById("toggle-overlay");
    let timers = [];
    const width = Number(header.width) || 80;
    const height = Number(header.height) || 24;
    let cursorX = 0;
    let cursorY = 0;
    let savedX = 0;
    let savedY = 0;
    let grid = [];
    let overlayEnabled = ${semanticOverlay ? "true" : "false"};
    const defaultStyle = Object.freeze({ fg: null, bg: null, bold: false, dim: false, underline: false, inverse: false });
    let currentStyle = { ...defaultStyle };
    let currentSemanticSnapshot = null;

    const ansi16 = [
      "#000000", "#cd0000", "#00cd00", "#cdcd00", "#0000ee", "#cd00cd", "#00cdcd", "#e5e5e5",
      "#7f7f7f", "#ff0000", "#00ff00", "#ffff00", "#5c5cff", "#ff00ff", "#00ffff", "#ffffff",
    ];

    function cloneStyle(style) {
      return { fg: style.fg, bg: style.bg, bold: style.bold, dim: style.dim, underline: style.underline, inverse: style.inverse };
    }

    function sameStyle(a, b) {
      return a.fg === b.fg && a.bg === b.bg && a.bold === b.bold && a.dim === b.dim &&
        a.underline === b.underline && a.inverse === b.inverse;
    }

    function blankCell() { return { ch: " ", style: cloneStyle(defaultStyle) }; }

    function color256(index) {
      if (index < 0 || index > 255) return null;
      if (index < 16) return ansi16[index];
      if (index >= 232) { const v = 8 + (index - 232) * 10; return "rgb(" + v + "," + v + "," + v + ")"; }
      const n = index - 16;
      const r = Math.floor(n / 36), g = Math.floor((n % 36) / 6), b = n % 6;
      const channel = (v) => v === 0 ? 0 : 55 + v * 40;
      return "rgb(" + channel(r) + "," + channel(g) + "," + channel(b) + ")";
    }

    function blankGrid() { return Array.from({ length: height }, () => Array.from({ length: width }, () => blankCell())); }

    function clampCursor() { cursorX = Math.max(0, Math.min(width - 1, cursorX)); cursorY = Math.max(0, Math.min(height - 1, cursorY)); }

    function clearLine(y, mode = 2) {
      if (y < 0 || y >= height) return;
      const start = mode === 0 ? cursorX : 0;
      const end = mode === 1 ? cursorX + 1 : width;
      for (let x = start; x < end; x += 1) grid[y][x] = blankCell();
    }

    function clearScreen(mode = 2) {
      if (mode === 2 || mode === 3) { grid = blankGrid(); cursorX = 0; cursorY = 0; return; }
      if (mode === 0) { clearLine(cursorY, 0); for (let y = cursorY + 1; y < height; y += 1) for (let x = 0; x < width; x += 1) grid[y][x] = blankCell(); }
      else if (mode === 1) { for (let y = 0; y < cursorY; y += 1) for (let x = 0; x < width; x += 1) grid[y][x] = blankCell(); clearLine(cursorY, 1); }
    }

    function newline() {
      cursorX = 0; cursorY += 1;
      if (cursorY >= height) { grid.shift(); grid.push(Array.from({ length: width }, () => blankCell())); cursorY = height - 1; }
    }

    function putChar(ch) {
      if (ch === "\\n") { newline(); return; }
      if (ch === "\\r") { cursorX = 0; return; }
      if (ch === "\\b") { cursorX = Math.max(0, cursorX - 1); return; }
      if (ch < " ") return;
      grid[cursorY][cursorX] = { ch, style: cloneStyle(currentStyle) };
      cursorX += 1;
      if (cursorX >= width) newline();
    }

    function csiParam(params, index, fallback) {
      const raw = params[index]; if (raw === undefined || raw === "") return fallback;
      const value = Number(raw); return Number.isFinite(value) ? value : fallback;
    }

    function handleSgr(paramsText) {
      const params = paramsText === "" ? [0] : paramsText.split(";").map((part) => part === "" ? 0 : Number(part));
      for (let i = 0; i < params.length; i += 1) {
        const code = Number.isFinite(params[i]) ? params[i] : 0;
        if (code === 0) currentStyle = { ...defaultStyle };
        else if (code === 1) currentStyle.bold = true;
        else if (code === 2) currentStyle.dim = true;
        else if (code === 3) {}
        else if (code === 4) currentStyle.underline = true;
        else if (code === 7) currentStyle.inverse = true;
        else if (code === 22) { currentStyle.bold = false; currentStyle.dim = false; }
        else if (code === 24) currentStyle.underline = false;
        else if (code === 27) currentStyle.inverse = false;
        else if (code === 39) currentStyle.fg = null;
        else if (code === 49) currentStyle.bg = null;
        else if (code >= 30 && code <= 37) currentStyle.fg = ansi16[code - 30];
        else if (code >= 40 && code <= 47) currentStyle.bg = ansi16[code - 40];
        else if (code >= 90 && code <= 97) currentStyle.fg = ansi16[8 + code - 90];
        else if (code >= 100 && code <= 107) currentStyle.bg = ansi16[8 + code - 100];
        else if ((code === 38 || code === 48) && params[i + 1] === 5) {
          const color = color256(params[i + 2]); if (code === 38) currentStyle.fg = color; else currentStyle.bg = color; i += 2;
        } else if ((code === 38 || code === 48) && params[i + 1] === 2) {
          const r = params[i + 2], g = params[i + 3], b = params[i + 4];
          if ([r, g, b].every((v) => Number.isFinite(v) && v >= 0 && v <= 255)) {
            const color = "rgb(" + r + "," + g + "," + b + ")"; if (code === 38) currentStyle.fg = color; else currentStyle.bg = color;
          }
          i += 4;
        }
      }
    }

    function handleCsi(paramsText, finalByte) {
      const params = paramsText.split(";").map((part) => part.replace(/^\\?/, ""));
      const n = csiParam(params, 0, 1);
      switch (finalByte) {
        case "A": cursorY -= n; break; case "B": cursorY += n; break;
        case "C": cursorX += n; break; case "D": cursorX -= n; break;
        case "E": cursorY += n; cursorX = 0; break; case "F": cursorY -= n; cursorX = 0; break;
        case "G": cursorX = n - 1; break;
        case "H": case "f": cursorY = csiParam(params, 0, 1) - 1; cursorX = csiParam(params, 1, 1) - 1; break;
        case "J": clearScreen(csiParam(params, 0, 0)); break;
        case "K": clearLine(cursorY, csiParam(params, 0, 0)); break;
        case "s": savedX = cursorX; savedY = cursorY; break;
        case "u": cursorX = savedX; cursorY = savedY; break;
        case "m": handleSgr(paramsText); break;
        case "h": case "l": break;
      }
      clampCursor();
    }

    function applyTerminalData(data) {
      for (let i = 0; i < data.length; i += 1) {
        const ch = data[i];
        if (ch === "\\x1b") {
          const next = data[i + 1];
          if (next === "[") {
            let j = i + 2; while (j < data.length && !/[A-Za-z~]/.test(data[j])) j += 1;
            if (j < data.length) { handleCsi(data.slice(i + 2, j), data[j]); i = j; continue; }
          } else if (next === "7") { savedX = cursorX; savedY = cursorY; i += 1; continue; }
          else if (next === "8") { cursorX = savedX; cursorY = savedY; clampCursor(); i += 1; continue; }
          else if (next === "=" || next === ">" || next === "(" || next === ")") { i += next === "(" || next === ")" ? 2 : 1; continue; }
        }
        putChar(ch);
      }
    }

    function escapeHtml(text) { return text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;"); }

    function styleToCss(style) {
      const fg = style.inverse ? style.bg : style.fg;
      const bg = style.inverse ? style.fg : style.bg;
      const parts = [];
      if (fg) parts.push("color:" + fg); if (bg) parts.push("background-color:" + bg);
      if (style.bold) parts.push("font-weight:700"); if (style.dim) parts.push("opacity:.72");
      if (style.underline) parts.push("text-decoration:underline");
      return parts.join(";");
    }

    function renderLine(line) {
      let end = line.length;
      while (end > 0 && line[end - 1].ch === " " && sameStyle(line[end - 1].style, defaultStyle)) end -= 1;
      let html = "", runText = "", runStyle = null;
      const flush = () => {
        if (runText === "") return;
        const css = styleToCss(runStyle || defaultStyle);
        html += css ? "<span style=\\"" + css + "\\">" + escapeHtml(runText) + "</span>" : escapeHtml(runText);
        runText = "";
      };
      for (let i = 0; i < end; i += 1) {
        const cell = line[i]; if (!runStyle || !sameStyle(runStyle, cell.style)) { flush(); runStyle = cell.style; }
        runText += cell.ch;
      }
      flush(); return html;
    }

    // ── Semantic overlay renderer ──

    function charMetrics() {
      if (measure.textContent.length < 64) {
        measure.textContent = "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM";
      }
      const rect = measure.getBoundingClientRect();
      const computed = window.getComputedStyle(measure);
      const lineHeight = Number.parseFloat(computed.lineHeight);
      return {
        charW: (rect.width / measure.textContent.length) || 8,
        lineH: Number.isFinite(lineHeight) ? lineHeight : (rect.height || 16),
      };
    }

    function boundsToPixels(bounds, charW, lineH) {
      const startX = Number.isFinite(bounds?.startX) ? bounds.startX : 0;
      const endX = Number.isFinite(bounds?.endX) ? bounds.endX : width - 1;
      const startY = Number.isFinite(bounds?.startY) ? bounds.startY : 0;
      const endY = Number.isFinite(bounds?.endY) ? bounds.endY : startY;
      return {
        x: startX * charW,
        y: startY * lineH,
        w: Math.max(charW, (endX - startX + 1) * charW),
        h: Math.max(lineH, (endY - startY + 1) * lineH),
      };
    }

    function makeBoundsBox(type, bounds, charW, lineH, label, extra) {
      const b = boundsToPixels(bounds, charW, lineH);
      return makeBox(type, b.x, b.y, b.w, b.h, label, extra);
    }

    function makeBox(type, x, y, w, h, label, extra) {
      const el = document.createElement("div");
      el.className = "semantic-box ov ov-" + type;
      el.style.left = x + "px"; el.style.top = y + "px";
      el.style.width = w + "px"; el.style.height = h + "px";
      if (label) {
        const lbl = document.createElement("span");
        lbl.className = "ov-label"; lbl.textContent = label;
        el.appendChild(lbl);
      }
      if (extra) {
        const badge = document.createElement("span");
        badge.className = "ov-key-badge"; badge.textContent = extra;
        el.appendChild(badge);
      }
      return el;
    }

    function renderSemanticOverlay() {
      overlay.innerHTML = "";
      if (!overlayEnabled || !currentSemanticSnapshot) return;
      const { charW, lineH } = charMetrics();
      overlay.style.width = (width * charW) + "px";
      overlay.style.height = (height * lineH) + "px";
      const snap = currentSemanticSnapshot;

      // 1. Popups (outermost containers)
      for (const p of (snap.popups || [])) {
        if (!p.bounds) continue;
        overlay.appendChild(makeBoundsBox("popup", p.bounds, charW, lineH, p.title || "popup"));
      }

      // 2. Panes (layout containers)
      const seenPanes = new Set();
      for (const p of (snap.panes || [])) {
        if (!p.bounds || seenPanes.has(p.id)) continue;
        seenPanes.add(p.id);
        overlay.appendChild(makeBoundsBox("pane", p.bounds, charW, lineH, p.title || null));
      }

      // 3. Lists (container) + list items (individual rows)
      for (const l of (snap.lists || [])) {
        if (!l.bounds) continue;
        if (l.role === "list") {
          // List container
          overlay.appendChild(makeBoundsBox("list", l.bounds, charW, lineH, l.label || "list"));
        } else if (l.role === "list_item") {
          const isSelected = l.selected === true;
          const type = isSelected ? "item-selected" : "item";
          const labelText = (l.label || "").substring(0, 40).trim();
          overlay.appendChild(makeBoundsBox(type, l.bounds, charW, lineH, labelText || "item"));
        }
      }

      // 4. Status bars
      for (const sb of (snap.statusBars || [])) {
        if (!sb.bounds) continue;
        const keyBadges = (sb.keyActions || []).map(ka => ka.key + "→" + ka.action).join("  ");
        overlay.appendChild(makeBoundsBox("status", sb.bounds, charW, lineH, "status", keyBadges || null));
      }

      // 5. Tables
      for (const t of (snap.tables || [])) {
        if (!t.bounds) continue;
        overlay.appendChild(makeBoundsBox("table", t.bounds, charW, lineH, t.label || "table"));
      }

      // 6. Facts with source bounds
      for (const f of (snap.facts || [])) {
        if (!f.sourceBounds) continue;
        overlay.appendChild(makeBoundsBox("fact", f.sourceBounds, charW, lineH,
          f.label + ": " + (f.value || "").substring(0, 20)));
      }

      // 7. Cursor
      if (snap.cursor) {
        overlay.appendChild(makeBox("cursor",
          snap.cursor.x * charW, snap.cursor.y * lineH, charW, lineH,
          null));
      }

      // 8. Game elements
      for (const ge of (snap.gameElements || [])) {
        if (!ge.bounds) continue;

        if (ge.role === "gameBoard") {
          // Board: full-width box spanning the wall lines
          overlay.appendChild(makeBoundsBox("gameBoard", ge.bounds, charW, lineH, ge.label));
        } else if (ge.role === "player") {
          // Player: single-cell highlight with pulsing glow
          overlay.appendChild(makeBox("player",
            ge.position.x * charW, ge.position.y * lineH, charW, lineH,
            ge.label));
        } else if (ge.role === "gameEntity") {
          // Entity: span from min to max positions
          const xs = ge.positions.map(p => p.x);
          const ys = ge.positions.map(p => p.y);
          const minX = Math.min(...xs), maxX = Math.max(...xs);
          const minY = Math.min(...ys), maxY = Math.max(...ys);
          const label = ge.entityRole === "body" ? "Snake (" + ge.count + ")" :
            ge.entityRole === "food" ? "Food" : "Bonus";
          const box = makeBox("gameEntity",
            minX * charW, minY * lineH,
            (maxX - minX + 1) * charW, (maxY - minY + 1) * lineH,
            label);
          // Add individual entity markers
          for (const p of ge.positions) {
            const dot = document.createElement("div");
            dot.style.cssText = "position:absolute;left:" + (p.x * charW + 1) + "px;top:" + (p.y * lineH + 1) + "px;width:" + (charW - 2) + "px;height:" + (lineH - 2) + "px;border-radius:2px;background:rgba(210,168,255,.25);pointer-events:none;";
            box.appendChild(dot);
          }
          overlay.appendChild(box);
        } else if (ge.role === "scoreBar") {
          // Score bar: full-width with parsed pairs
          const pairsText = (ge.pairs || []).map(p => p.label + ": " + p.value).join("  ");
          overlay.appendChild(makeBoundsBox("scoreBar", ge.bounds, charW, lineH, ge.label, pairsText || null));
        } else if (ge.role === "titleBar") {
          // Title bar: full-width with mode
          const titleText = ge.mode ? ge.label + " · " + ge.mode : ge.label;
          overlay.appendChild(makeBoundsBox("titleBar", ge.bounds, charW, lineH, titleText));
        } else if (ge.role === "cardGame") {
          // Card game: summary box spanning the card area
          const cardText = ge.cardCount + " cards, " + ge.faceDownCount + " face-down, " + ge.tableauColumns + " tableau cols";
          overlay.appendChild(makeBoundsBox("cardGame", ge.bounds, charW, lineH, ge.label, cardText));
        } else if (ge.role === "cardFace") {
          // Individual card face: small badge at the card position
          const cls = ge.suitColor === "red" ? "cardFace cardFace-red" : "cardFace";
          const box = makeBox(cls,
            ge.position.x * charW, ge.position.y * lineH,
            3 * charW, lineH,
            ge.label);
          overlay.appendChild(box);
        }
      }

      // 9. Charts
      for (const ch of (snap.charts || [])) {
        if (!ch.bounds) continue;

        if (ch.role === "brailleChart") {
          const info = ch.chartType === "sparkline"
            ? "Sparkline " + ch.lineCount + " rows"
            : "Bar chart " + ch.values?.length + " values";
          overlay.appendChild(makeBox("brailleChart",
            ch.startX * charW, ch.bounds.startY * lineH,
            (ch.endX - ch.startX + 1) * charW, (ch.bounds.endY - ch.bounds.startY + 1) * lineH,
            ch.label, info));
        } else if (ch.role === "blockBar") {
          overlay.appendChild(makeBox("blockBar",
            0, ch.bounds.startY * lineH, width * charW, lineH,
            ch.label, ch.barLabel + ": " + ch.value));
        } else if (ch.role === "pipeMeter") {
          const meterText = (ch.meters || []).map(m => m.label + " " + m.value).join("  ");
          overlay.appendChild(makeBox("pipeMeter",
            0, ch.bounds.startY * lineH, width * charW, lineH,
            ch.label, meterText || null));
        }
      }
    }

    // ── Capabilities sidebar ──

    function updateSidebar(snap) {
      if (!snap) return;
      const caps = snap.capabilities || {};

      // App card
      const appInfo = document.getElementById("app-info");
      const app = snap.app || "unknown";
      const fw = snap.framework || "unknown";
      const conf = snap.confidence || 0;
      appInfo.innerHTML =
        '<span class="app-badge">' + escapeHtml(app) + '</span> ' +
        '<span class="fw-badge">' + escapeHtml(fw) + '</span>' +
        '<div class="conf-bar"><div class="conf-fill" style="width:' + (conf * 100) + '%"></div></div>' +
        '<div style="color:var(--muted);font-size:11px;margin-top:4px">' + Math.round(conf * 100) + '% confidence</div>';

      // Navigate card
      const navInfo = document.getElementById("nav-info");
      const navKeys = (caps.navigate || {}).keys || [];
      navInfo.innerHTML = navKeys.map(k => '<div class="cap-row"><span class="cap-key">' + escapeHtml(k) + '</span><span class="cap-action">navigate</span></div>').join("") || '<div style="color:var(--muted)">—</div>';

      // Actions card
      const actionsInfo = document.getElementById("actions-info");
      const actions = caps.actions || [];
      const quitKeys = (caps.quit || {}).keys || [];
      const helpKeys = (caps.help || {}).keys || [];
      const dismissKeys = (caps.dismiss || {}).keys || [];
      let actHtml = actions.map(a => '<div class="cap-row"><span class="cap-key">' + escapeHtml(a.key) + '</span><span class="cap-action">' + escapeHtml(a.action) + '</span><span class="cap-source">' + escapeHtml(a.source || "") + '</span></div>').join("");
      actionsInfo.innerHTML = actHtml || '<div style="color:var(--muted)">—</div>';

      // Quit / Dismiss card
      const quitInfo = document.getElementById("quit-info");
      let qHtml = quitKeys.map(k => '<div class="cap-row"><span class="cap-key">' + escapeHtml(k) + '</span><span class="cap-action">quit</span></div>').join("");
      qHtml += helpKeys.map(k => '<div class="cap-row"><span class="cap-key">' + escapeHtml(k) + '</span><span class="cap-action">help</span></div>').join("");
      qHtml += dismissKeys.map(k => '<div class="cap-row"><span class="cap-key">' + escapeHtml(k) + '</span><span class="cap-action">dismiss</span></div>').join("");
      quitInfo.innerHTML = qHtml || '<div style="color:var(--muted)">—</div>';

      // Game card (only if game elements detected)
      const gameCard = document.getElementById("game-card");
      const gameEls = snap.gameElements || [];
      if (gameEls.length > 0) {
        gameCard.style.display = "";
        const gameInfo = document.getElementById("game-info");
        let gHtml = "";
        for (const ge of gameEls) {
          if (ge.role === "player") {
            gHtml += '<div class="cap-row"><span style="color:#3fb950;font-weight:700">@</span><span class="cap-action">Player (' + ge.position.x + ',' + ge.position.y + ')</span></div>';
          } else if (ge.role === "gameEntity" && ge.entityRole === "body") {
            gHtml += '<div class="cap-row"><span class="cap-key" style="background:#8957e5;border-color:#8957e5;color:#fff">o</span><span class="cap-action">Body (' + ge.count + ')</span></div>';
          } else if (ge.role === "gameEntity" && ge.entityRole === "food") {
            gHtml += '<div class="cap-row"><span class="cap-key" style="background:#da3633;border-color:#da3633;color:#fff">$</span><span class="cap-action">Food</span></div>';
          } else if (ge.role === "scoreBar" && ge.pairs?.length > 0) {
            for (const p of ge.pairs) {
              gHtml += '<div class="cap-row"><span class="cap-action">' + escapeHtml(p.label) + '</span><span class="cap-key">' + escapeHtml(p.value) + '</span></div>';
            }
          } else if (ge.role === "titleBar" && ge.mode) {
            gHtml += '<div class="cap-row"><span class="cap-action">Mode</span><span class="cap-key">' + escapeHtml(ge.mode) + '</span></div>';
          } else if (ge.role === "cardGame") {
            gHtml += '<div class="cap-row"><span style="color:#a371f7;font-weight:700">♠</span><span class="cap-action">Cards: ' + ge.cardCount + ' (' + ge.faceDownCount + ' down)</span></div>';
            gHtml += '<div class="cap-row"><span class="cap-action">Tableau</span><span class="cap-key">' + ge.tableauColumns + ' cols</span></div>';
          } else if (ge.role === "cardFace") {
            const suitIcon = ge.suitColor === "red" ? '<span style="color:#ff7b72">' + escapeHtml(ge.suit) + '</span>' : '<span style="color:#e6edf3">' + escapeHtml(ge.suit) + '</span>';
            gHtml += '<div class="cap-row">' + suitIcon + '<span class="cap-action">' + escapeHtml(ge.rank) + '</span></div>';
          }
        }
        gameInfo.innerHTML = gHtml || '<div style="color:var(--muted)">—</div>';
      } else {
        gameCard.style.display = "none";
      }

      // Charts card
      const chartCard = document.getElementById("chart-info")?.parentElement;
      const chartInfo = document.getElementById("chart-info");
      if (chartInfo && snap.charts?.length > 0) {
        if (chartCard) chartCard.style.display = "";
        let cHtml = "";
        for (const ch of snap.charts) {
          if (ch.role === "brailleChart") {
            const icon = ch.chartType === "sparkline" ? "📈" : "📊";
            cHtml += '<div class="cap-row"><span style="color:#3fb950">' + icon + '</span><span class="cap-action">' + escapeHtml(ch.label) + '</span>';
            cHtml += '<span class="cap-key">' + ch.lineCount + ' rows</span></div>';
            if (ch.values?.length) {
              cHtml += '<div class="cap-row" style="padding-left:18px"><span class="cap-action" style="color:var(--muted)">' + escapeHtml(ch.values.slice(0, 4).join(" ")) + '</span></div>';
            }
          } else if (ch.role === "blockBar") {
            cHtml += '<div class="cap-row"><span style="color:#d29922">▮</span><span class="cap-action">' + escapeHtml(ch.barLabel) + '</span>';
            cHtml += '<span class="cap-key">' + escapeHtml(ch.value) + '</span></div>';
          } else if (ch.role === "pipeMeter") {
            for (const m of (ch.meters || [])) {
              const pct = m.percent != null ? m.percent + "%" : m.value;
              cHtml += '<div class="cap-row"><span style="color:#58a6ff">▪</span><span class="cap-action">' + escapeHtml(m.label) + '</span>';
              cHtml += '<span class="cap-key">' + escapeHtml(pct) + '</span></div>';
            }
          }
        }
        chartInfo.innerHTML = cHtml || '<div style="color:var(--muted)">—</div>';
      } else {
        if (chartCard) chartCard.style.display = "none";
      }
    }

    function render() {
      terminal.innerHTML = grid.map(renderLine).join("\\n");
      renderSemanticOverlay();
      meta.textContent = "asciicast v2 · " + width + "×" + height + " · " + events.length + " events";
    }

    function clearTimers() { for (const timer of timers) clearTimeout(timer); timers = []; }

    reset.addEventListener("click", () => {
      clearTimers(); grid = blankGrid(); cursorX = 0; cursorY = 0; currentStyle = { ...defaultStyle }; render();
    });

    toggleOverlay.addEventListener("click", () => {
      overlayEnabled = !overlayEnabled;
      toggleOverlay.setAttribute("aria-pressed", overlayEnabled ? "true" : "false");
      renderSemanticOverlay();
    });

    play.addEventListener("click", () => {
      clearTimers(); grid = blankGrid(); cursorX = 0; cursorY = 0; currentStyle = { ...defaultStyle }; render();
      for (const event of events) {
        const [time, kind, data] = event;
        if (kind === "o") {
          timers.push(setTimeout(() => { applyTerminalData(data); render(); }, Math.max(0, time * 1000)));
        } else if (kind === "s") {
          timers.push(setTimeout(() => { currentSemanticSnapshot = data; renderSemanticOverlay(); updateSidebar(data); }, Math.max(0, time * 1000)));
        }
      }
    });

    grid = blankGrid(); render();
  </script>
</body>
</html>`;
}

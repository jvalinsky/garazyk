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
  constructor({ outputDir, cols, rows, title, recordInput = false, command }) {
    this.outputDir = outputDir;
    this.cols = cols;
    this.rows = rows;
    this.title = title ?? "Garazyk PTY Capture";
    this.recordInputEnabled = recordInput === true;
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
    }));
  }
}

export function defaultRecordingDir(baseDir = process.cwd(), startedAt = Date.now()) {
  return path.join(baseDir, "scripts", "scenarios", "reports", "pty-capture", `mcp-${startedAt}`);
}

export function buildStandaloneHtml({ title, castContent }) {
  const encodedCast = Buffer.from(castContent, "utf8").toString("base64");
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${htmlEscape(title)}</title>
  <style>
    :root { color-scheme: dark; }
    body { margin: 0; background: #111; color: #eee; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    main { padding: 20px; max-width: 1200px; margin: 0 auto; }
    header { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 12px; }
    h1 { font-size: 18px; margin: 0; font-weight: 600; }
    button { border: 1px solid #555; background: #1d1d1d; color: #eee; padding: 6px 10px; font: inherit; cursor: pointer; }
    button:hover { background: #2a2a2a; }
    #terminal { white-space: pre; border: 1px solid #333; padding: 16px; overflow: auto; background: #000; min-height: 60vh; line-height: 1.35; }
    .cell { display: inline; }
    #meta { color: #aaa; font-size: 12px; margin-top: 10px; }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>${htmlEscape(title)}</h1>
      <div>
        <button id="play" type="button">Play</button>
        <button id="reset" type="button">Reset</button>
      </div>
    </header>
    <pre id="terminal" aria-label="Terminal replay"></pre>
    <div id="meta"></div>
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
    const meta = document.getElementById("meta");
    const play = document.getElementById("play");
    const reset = document.getElementById("reset");
    let timers = [];
    const width = Number(header.width) || 80;
    const height = Number(header.height) || 24;
    let cursorX = 0;
    let cursorY = 0;
    let savedX = 0;
    let savedY = 0;
    let grid = [];
    const defaultStyle = Object.freeze({ fg: null, bg: null, bold: false, dim: false, underline: false, inverse: false });
    let currentStyle = { ...defaultStyle };

    const ansi16 = [
      "#000000", "#cd0000", "#00cd00", "#cdcd00", "#0000ee", "#cd00cd", "#00cdcd", "#e5e5e5",
      "#7f7f7f", "#ff0000", "#00ff00", "#ffff00", "#5c5cff", "#ff00ff", "#00ffff", "#ffffff",
    ];

    function cloneStyle(style) {
      return {
        fg: style.fg,
        bg: style.bg,
        bold: style.bold,
        dim: style.dim,
        underline: style.underline,
        inverse: style.inverse,
      };
    }

    function sameStyle(a, b) {
      return a.fg === b.fg && a.bg === b.bg && a.bold === b.bold && a.dim === b.dim &&
        a.underline === b.underline && a.inverse === b.inverse;
    }

    function blankCell() {
      return { ch: " ", style: cloneStyle(defaultStyle) };
    }

    function color256(index) {
      if (index < 0 || index > 255) return null;
      if (index < 16) return ansi16[index];
      if (index >= 232) {
        const v = 8 + (index - 232) * 10;
        return "rgb(" + v + "," + v + "," + v + ")";
      }
      const n = index - 16;
      const r = Math.floor(n / 36);
      const g = Math.floor((n % 36) / 6);
      const b = n % 6;
      const channel = (value) => value === 0 ? 0 : 55 + value * 40;
      return "rgb(" + channel(r) + "," + channel(g) + "," + channel(b) + ")";
    }

    function blankGrid() {
      return Array.from({ length: height }, () => Array.from({ length: width }, () => blankCell()));
    }

    function clampCursor() {
      cursorX = Math.max(0, Math.min(width - 1, cursorX));
      cursorY = Math.max(0, Math.min(height - 1, cursorY));
    }

    function clearLine(y, mode = 2) {
      if (y < 0 || y >= height) return;
      const start = mode === 0 ? cursorX : 0;
      const end = mode === 1 ? cursorX + 1 : width;
      for (let x = start; x < end; x += 1) grid[y][x] = blankCell();
    }

    function clearScreen(mode = 2) {
      if (mode === 2 || mode === 3) {
        grid = blankGrid();
        cursorX = 0;
        cursorY = 0;
        return;
      }
      if (mode === 0) {
        clearLine(cursorY, 0);
        for (let y = cursorY + 1; y < height; y += 1) {
          for (let x = 0; x < width; x += 1) grid[y][x] = blankCell();
        }
      } else if (mode === 1) {
        for (let y = 0; y < cursorY; y += 1) {
          for (let x = 0; x < width; x += 1) grid[y][x] = blankCell();
        }
        clearLine(cursorY, 1);
      }
    }

    function newline() {
      cursorX = 0;
      cursorY += 1;
      if (cursorY >= height) {
        grid.shift();
        grid.push(Array.from({ length: width }, () => blankCell()));
        cursorY = height - 1;
      }
    }

    function putChar(ch) {
      if (ch === "\\n") {
        newline();
        return;
      }
      if (ch === "\\r") {
        cursorX = 0;
        return;
      }
      if (ch === "\\b") {
        cursorX = Math.max(0, cursorX - 1);
        return;
      }
      if (ch < " ") return;
      grid[cursorY][cursorX] = { ch, style: cloneStyle(currentStyle) };
      cursorX += 1;
      if (cursorX >= width) newline();
    }

    function csiParam(params, index, fallback) {
      const raw = params[index];
      if (raw === undefined || raw === "") return fallback;
      const value = Number(raw);
      return Number.isFinite(value) ? value : fallback;
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
          const color = color256(params[i + 2]);
          if (code === 38) currentStyle.fg = color;
          else currentStyle.bg = color;
          i += 2;
        } else if ((code === 38 || code === 48) && params[i + 1] === 2) {
          const r = params[i + 2];
          const g = params[i + 3];
          const b = params[i + 4];
          if ([r, g, b].every((value) => Number.isFinite(value) && value >= 0 && value <= 255)) {
            const color = "rgb(" + r + "," + g + "," + b + ")";
            if (code === 38) currentStyle.fg = color;
            else currentStyle.bg = color;
          }
          i += 4;
        }
      }
    }

    function handleCsi(paramsText, finalByte) {
      const params = paramsText.split(";").map((part) => part.replace(/^\\?/, ""));
      const n = csiParam(params, 0, 1);
      switch (finalByte) {
        case "A": cursorY -= n; break;
        case "B": cursorY += n; break;
        case "C": cursorX += n; break;
        case "D": cursorX -= n; break;
        case "E": cursorY += n; cursorX = 0; break;
        case "F": cursorY -= n; cursorX = 0; break;
        case "G": cursorX = n - 1; break;
        case "H":
        case "f":
          cursorY = csiParam(params, 0, 1) - 1;
          cursorX = csiParam(params, 1, 1) - 1;
          break;
        case "J": clearScreen(csiParam(params, 0, 0)); break;
        case "K": clearLine(cursorY, csiParam(params, 0, 0)); break;
        case "s": savedX = cursorX; savedY = cursorY; break;
        case "u": cursorX = savedX; cursorY = savedY; break;
        case "m":
          handleSgr(paramsText);
          break;
        case "h":
        case "l":
          break;
      }
      clampCursor();
    }

    function applyTerminalData(data) {
      for (let i = 0; i < data.length; i += 1) {
        const ch = data[i];
        if (ch === "\\x1b") {
          const next = data[i + 1];
          if (next === "[") {
            let j = i + 2;
            while (j < data.length && !/[A-Za-z~]/.test(data[j])) j += 1;
            if (j < data.length) {
              handleCsi(data.slice(i + 2, j), data[j]);
              i = j;
              continue;
            }
          } else if (next === "7") {
            savedX = cursorX; savedY = cursorY; i += 1; continue;
          } else if (next === "8") {
            cursorX = savedX; cursorY = savedY; clampCursor(); i += 1; continue;
          } else if (next === "=" || next === ">" || next === "(" || next === ")") {
            i += next === "(" || next === ")" ? 2 : 1;
            continue;
          }
        }
        putChar(ch);
      }
    }

    function escapeHtml(text) {
      return text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
    }

    function styleToCss(style) {
      const fg = style.inverse ? style.bg : style.fg;
      const bg = style.inverse ? style.fg : style.bg;
      const parts = [];
      if (fg) parts.push("color:" + fg);
      if (bg) parts.push("background-color:" + bg);
      if (style.bold) parts.push("font-weight:700");
      if (style.dim) parts.push("opacity:.72");
      if (style.underline) parts.push("text-decoration:underline");
      return parts.join(";");
    }

    function renderLine(line) {
      let end = line.length;
      while (end > 0 && line[end - 1].ch === " " && sameStyle(line[end - 1].style, defaultStyle)) end -= 1;
      let html = "";
      let runText = "";
      let runStyle = null;
      const flush = () => {
        if (runText === "") return;
        const css = styleToCss(runStyle || defaultStyle);
        html += css ? "<span class=\\"cell\\" style=\\"" + css + "\\">" + escapeHtml(runText) + "</span>" : escapeHtml(runText);
        runText = "";
      };
      for (let i = 0; i < end; i += 1) {
        const cell = line[i];
        if (!runStyle || !sameStyle(runStyle, cell.style)) {
          flush();
          runStyle = cell.style;
        }
        runText += cell.ch;
      }
      flush();
      return html;
    }

    function render() {
      terminal.innerHTML = grid.map(renderLine).join("\\n");
      meta.textContent = "asciicast v2, " + width + "x" + height + ", " + events.length + " events";
    }

    function clearTimers() {
      for (const timer of timers) clearTimeout(timer);
      timers = [];
    }

    reset.addEventListener("click", () => {
      clearTimers();
      grid = blankGrid();
      cursorX = 0;
      cursorY = 0;
      currentStyle = { ...defaultStyle };
      render();
    });

    play.addEventListener("click", () => {
      clearTimers();
      grid = blankGrid();
      cursorX = 0;
      cursorY = 0;
      currentStyle = { ...defaultStyle };
      render();
      for (const event of events) {
        const [time, kind, data] = event;
        if (kind !== "o") continue;
        timers.push(setTimeout(() => {
          applyTerminalData(data);
          render();
        }, Math.max(0, time * 1000)));
      }
    });

    grid = blankGrid();
    render();
  </script>
</body>
</html>
`;
}

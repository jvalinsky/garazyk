import path from "node:path";

export function extractGrid(buffer, cols, rows) {
  const grid = [];
  for (let y = 0; y < rows; y++) {
    const line = buffer.getLine(buffer.viewportY + y);
    const rowCells = [];
    if (line) {
      for (let x = 0; x < cols; x++) {
        const cell = line.getCell(x);
        if (cell) {
          rowCells.push({
            char: cell.getChars() || " ",
            bold: cell.isBold(),
            inverse: cell.isInverse(),
            underline: cell.isUnderline(),
          });
        } else {
          rowCells.push({ char: " ", bold: false, inverse: false, underline: false });
        }
      }
    } else {
      for (let x = 0; x < cols; x++) {
        rowCells.push({ char: " ", bold: false, inverse: false, underline: false });
      }
    }
    grid.push(rowCells);
  }
  return grid;
}

export function guessApplication(command, lines) {
  const base = path.basename(command || "");
  let guess = "unknown";
  let confidence = 0;

  if (base === "top") {
    guess = "top";
    confidence = 0.9;
  } else if (base === "btop") {
    guess = "btop";
    confidence = 0.9;
  } else if (base === "htop") {
    guess = "htop";
    confidence = 0.9;
  } else if (base === "vim" || base === "vi" || base === "nvim") {
    guess = "vim";
    confidence = 0.9;
  } else if (base === "less" || base === "more") {
    guess = "less";
    confidence = 0.9;
  } else if (base === "tmux") {
    guess = "tmux";
    confidence = 0.9;
  } else if (base === "git") {
    guess = "git";
    confidence = 0.8;
  } else if (base === "nano") {
    guess = "nano";
    confidence = 0.9;
  } else {
    // heuristics
    if (lines.length > 0 && lines[0].includes("Tasks:") && lines[1] && lines[1].includes("Load avg:")) {
      guess = "top";
      confidence = 0.7;
    } else if (lines.length > 0 && lines.some(l => l.includes("VIM - Vi IMproved"))) {
      guess = "vim";
      confidence = 0.7;
    } else if (lines.some(l => l.includes("commit ") && l.match(/[0-9a-f]{7,40}/)) && lines.some(l => l.includes("Author:"))) {
      guess = "git log";
      confidence = 0.8;
    } else if (lines.length > 0 && lines.some(l => l.includes("GNU nano"))) {
      guess = "nano";
      confidence = 0.8;
    } else if (lines.length > 0 && lines[lines.length - 1].match(/\[\d+\] \d+:/)) {
      guess = "tmux";
      confidence = 0.7;
    }
  }

  return { app: guess, confidence };
}

export function detectStatusLines(grid, lines) {
  const facts = [];
  const rows = grid.length;
  if (rows === 0) return facts;

  // Many TUIs have status line at bottom or top
  // Let's check last line for VIM-like "-- INSERT --" or LESS-like ":" or top-like "top -"
  
  const lastLine = lines[rows - 1];
  const firstLine = lines[0];

  if (lastLine && lastLine.includes("-- INSERT --")) {
    facts.push({ label: "Mode", value: "Insert", sourceBounds: { startY: rows - 1, endY: rows - 1 }, confidence: 0.9 });
  } else if (lastLine && lastLine.includes("-- VISUAL --")) {
    facts.push({ label: "Mode", value: "Visual", sourceBounds: { startY: rows - 1, endY: rows - 1 }, confidence: 0.9 });
  } else if (lastLine && lastLine.trim() === ":" && lastLine.length > 0) {
    facts.push({ label: "Mode", value: "Command", sourceBounds: { startY: rows - 1, endY: rows - 1 }, confidence: 0.6 });
  }

  if (firstLine && firstLine.includes("top -")) {
    facts.push({ label: "Header", value: "System top", sourceBounds: { startY: 0, endY: 0 }, confidence: 0.9 });
  }

  return facts;
}

export function detectTables(grid, lines) {
  const tables = [];
  // Detect top-like process tables
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line.match(/PID\s+USER\s+PR\s+NI\s+VIRT\s+RES/i) || line.match(/PID\s+COMMAND\s+%CPU\s+TIME/i)) {
      // found header
      tables.push({
        id: "process_table",
        role: "table",
        columns: line.trim().split(/\s+/),
        bounds: { startY: i, endY: lines.length - 1 },
        confidence: 0.8,
        evidence: [line]
      });
      break;
    }
  }
  return tables;
}

export function detectContainers(grid, lines) {
  const regions = [];
  // Basic heuristic: lines starting with ~ are vim blank lines
  const vimBlankStart = lines.findIndex(l => l.startsWith("~"));
  if (vimBlankStart !== -1) {
    let end = vimBlankStart;
    while (end < lines.length && lines[end].startsWith("~")) {
      end++;
    }
    regions.push({
      id: "filler",
      role: "empty_space",
      bounds: { startY: vimBlankStart, endY: end - 1 },
      confidence: 0.8,
      evidence: ["~ lines"]
    });
  }
  return regions;
}

export function detectControls(grid, lines) {
  const controls = [];
  const rows = lines.length;

  for (let i = 0; i < rows; i++) {
    const line = lines[i];
    if (!line) continue;

    const checkboxRegex = /\[[ xX]\]|\([ *]\)/g;
    let match;
    while ((match = checkboxRegex.exec(line)) !== null) {
      controls.push({
        role: "checkbox",
        bounds: { startY: i, endY: i },
        confidence: 0.8,
        label: line.substring(match.index + match[0].length).split("  ")[0].trim() || match[0],
        evidence: [line]
      });
    }

    const buttonRegex = /\[\s+[A-Za-z0-9_]+\s+\]|\<\s*[A-Za-z0-9_]+\s*\>/g;
    while ((match = buttonRegex.exec(line)) !== null) {
      controls.push({
        role: "button",
        bounds: { startY: i, endY: i },
        confidence: 0.8,
        label: match[0],
        evidence: [line]
      });
    }
  }

  for (let y = 0; y < rows; y++) {
    let inputStart = -1;
    let runLength = 0;
    const rowCells = grid[y] || [];
    for (let x = 0; x < rowCells.length; x++) {
      const cell = rowCells[x];
      if (cell.underline || cell.inverse) {
        if (inputStart === -1) inputStart = x;
        runLength++;
      } else {
        if (runLength > 4) {
          controls.push({
            role: "input",
            bounds: { startY: y, endY: y },
            confidence: 0.7,
            label: "Input field",
            evidence: ["Styled cells"]
          });
        }
        inputStart = -1;
        runLength = 0;
      }
    }
    if (runLength > 4) {
      controls.push({
        role: "input",
        bounds: { startY: y, endY: y },
        confidence: 0.7,
        label: "Input field",
        evidence: ["Styled cells"]
      });
    }
  }

  return controls;
}

export function buildAgentPrompt(appGuess) {
  return `You are a semantic analyzer for terminal UIs.
The user is requesting an interpretation of a terminal screen.
The terminal is currently running an application guessed to be: ${appGuess}.

Below is a structured "Semantic Snapshot" of the terminal buffer, including the raw text lines and deterministically detected regions, tables, controls, and facts.

Your task is to infer higher-level meaning from this evidence. For example:
- Identify what the user is currently looking at or doing.
- Point out any important warnings, errors, or prominent metrics.
- Determine the state of the application (e.g., editing a file, viewing a list, waiting for input).
- Decide which interactive controls are actionable.

Respond strictly in JSON matching this schema:
{
  "summary": "A brief 1-2 sentence summary of the screen state",
  "appState": "A short string describing the state (e.g., 'Normal mode', 'Viewing process list')",
  "keyMetrics": [{"name": "CPU Usage", "value": "12.3%"}],
  "warnings": ["Any warnings visible on screen"],
  "availableActions": ["A list of suggested tool calls to interact with the detected controls using pty_action"]
}
`;
}

export function buildSemanticSnapshot(session, detail = "compact", includePrompt = false) {
  const buffer = session.term.buffer.active;
  const cols = session.cols;
  const rows = session.rows;
  
  // Get raw lines
  const lines = [];
  for (let row = 0; row < rows; row += 1) {
    const lineObj = buffer.getLine(buffer.viewportY + row);
    lines.push(lineObj ? lineObj.translateToString(true) : "");
  }

  const grid = extractGrid(buffer, cols, rows);
  const appGuess = guessApplication(session.command, lines);

  const facts = detectStatusLines(grid, lines);
  const tables = detectTables(grid, lines);
  const containers = detectContainers(grid, lines);
  const controls = detectControls(grid, lines);

  const regions = [...containers];

  const snapshot = {
    sessionId: session.sessionId,
    app: appGuess.app,
    confidence: appGuess.confidence,
    cursor: { x: buffer.cursorX, y: buffer.cursorY },
    facts,
    tables,
    regions,
    controls,
  };

  if (detail === "full") {
    snapshot.lines = lines;
  }

  const result = {
    snapshot,
  };

  if (includePrompt) {
    result.prompt = buildAgentPrompt(appGuess.app);
  }

  return result;
}

const STANDARD_ASCIICAST_EVENTS = new Set(["o", "i", "r", "m"]);

export function splitSemanticCast(castContent) {
  const lines = String(castContent || "").trimEnd().split("\n").filter(Boolean);
  if (lines.length === 0) throw new Error("empty asciicast content");

  const header = JSON.parse(lines[0]);
  const standardLines = [JSON.stringify(header)];
  const semanticEvents = [];

  for (const line of lines.slice(1)) {
    let event;
    try {
      event = JSON.parse(line);
    } catch {
      continue;
    }
    if (!Array.isArray(event) || event.length !== 3) continue;
    const [time, kind, data] = event;
    if (kind === "s") {
      semanticEvents.push({ time: Number(time) || 0, snapshot: data });
      continue;
    }
    if (STANDARD_ASCIICAST_EVENTS.has(kind)) {
      standardLines.push(JSON.stringify(event));
    }
  }

  return {
    header,
    standardCast: standardLines.join("\n") + "\n",
    semanticEvents,
  };
}

/**
 * Streaming variant of splitSemanticCast for large cast files.
 * Reads line-by-line to avoid V8 string size limits (~512MB).
 */
import fs from "node:fs";
import readline from "node:readline";

export async function splitSemanticCastFile(castPath) {
  const stream = fs.createReadStream(castPath, { encoding: "utf8" });
  const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });

  let header = null;
  const standardLines = [];
  const semanticEvents = [];

  let lineNum = 0;
  for await (const line of rl) {
    lineNum++;
    const trimmed = line.trim();
    if (!trimmed) continue;

    if (lineNum === 1) {
      header = JSON.parse(trimmed);
      standardLines.push(JSON.stringify(header));
      continue;
    }

    let event;
    try {
      event = JSON.parse(trimmed);
    } catch {
      continue;
    }
    if (!Array.isArray(event) || event.length !== 3) continue;
    const [time, kind, data] = event;
    if (kind === "s") {
      semanticEvents.push({ time: Number(time) || 0, snapshot: data });
      continue;
    }
    if (STANDARD_ASCIICAST_EVENTS.has(kind)) {
      standardLines.push(JSON.stringify(event));
    }
  }

  if (!header) throw new Error("empty asciicast content");

  return {
    header,
    standardCast: standardLines.join("\n") + "\n",
    semanticEvents,
  };
}

export function latestSemanticSnapshotAt(events, timeSeconds) {
  let current = null;
  for (const event of events) {
    if (event.time <= timeSeconds) current = event.snapshot;
    else break;
  }
  return current;
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

/**
 * Write tiered semantic data files for fast incremental loading.
 *
 * Produces:
 *   semantic-index.json   — tiny (~40KB), loaded immediately for sidebar
 *   semantic-snapshots.json — deduped (~2MB), loaded lazily when overlay is toggled on
 *
 * Fields stripped (never used by overlay): world, lines, sessionId, frameId,
 * relations, diagnostics, vdomViz
 */
export function writeTieredSemanticData(semanticEvents, outputDir, fsMod = fs, pathMod = path) {
  // Dedup snapshots by content hash
  const snapshotMap = new Map(); // JSON string → numeric id
  const snapshots = [];          // array of {elements, capabilities, controls, facts, ...}
  const OVERLAY_FIELDS = ["elements", "capabilities", "controls", "facts", "tables", "regions",
    "tabs", "panes", "lists", "statusBars", "popups", "gameElements", "charts", "actions"];
  const INDEX_FIELDS = ["app", "framework", "confidence", "cursor", "altScreen", "cols", "rows"];

  const index = [];

  for (const event of semanticEvents) {
    const s = event.snapshot || event[2] || {};
    const time = event.time ?? event[0] ?? 0;

    // Build sidebar-only index entry
    const idx = { t: time };
    for (const k of INDEX_FIELDS) {
      if (s[k] !== undefined) idx[k] = s[k];
    }

    // Build stripped snapshot for dedup (only overlay-relevant fields)
    const stripped = {};
    for (const k of OVERLAY_FIELDS) {
      if (s[k] !== undefined) stripped[k] = s[k];
    }
    const key = JSON.stringify(stripped);

    let sid;
    if (snapshotMap.has(key)) {
      sid = snapshotMap.get(key);
    } else {
      sid = snapshots.length;
      snapshotMap.set(key, sid);
      snapshots.push(stripped);
    }
    idx.sid = sid;
    index.push(idx);
  }

  const indexPath = pathMod.join(outputDir, "semantic-index.json");
  const snapshotsPath = pathMod.join(outputDir, "semantic-snapshots.json");

  fsMod.writeFileSync(indexPath, JSON.stringify(index));
  fsMod.writeFileSync(snapshotsPath, JSON.stringify(snapshots));

  return {
    indexSize: fsMod.statSync(indexPath).size,
    snapshotsSize: fsMod.statSync(snapshotsPath).size,
    eventCount: index.length,
    snapshotCount: snapshots.length,
  };
}

export function buildAsciinemaOverlayHtml({ title, castContent, semanticOverlay = false, castFileName = "playback.cast", semanticFileName = "semantic-events.json" }) {
  const splitResult = castContent ? splitSemanticCast(castContent) : { standardCast: "", semanticEvents: [] };
  const { standardCast, semanticEvents } = splitResult;
  const overlayEnabled = semanticOverlay === true;
  const hasSemanticEvents = semanticEvents.length > 0 || !!semanticFileName;

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)}</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/asciinema-player@3.8.0/dist/bundle/asciinema-player.css">
  <style>
    :root { color-scheme: dark; --bg: #0d1117; --surface: #161b22; --border: #30363d; --text: #e6edf3; --muted: #8b949e; }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif; }
    main { padding: 20px; max-width: 1400px; margin: 0 auto; }
    header { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 16px; }
    h1 { font-size: 18px; margin: 0; font-weight: 600; }
    button { border: 1px solid var(--border); background: var(--surface); color: var(--text); padding: 6px 12px; font: inherit; font-size: 13px; cursor: pointer; border-radius: 6px; }
    button[aria-pressed="true"] { background: #1a4a6e; border-color: #388bfd; }
    .layout { display: grid; grid-template-columns: 1fr 280px; gap: 16px; }
    @media (max-width: 900px) { .layout { grid-template-columns: 1fr; } }
    .player-frame { position: relative; border: 1px solid var(--border); border-radius: 8px; overflow: hidden; background: #000; }
    #player { position: relative; }
    #semantic-overlay { position: absolute; inset: 0; pointer-events: none; z-index: 4; }
    .semantic-box { position: absolute; border: 1px solid #388bfd; background: rgba(56,139,253,.06); border-radius: 3px; }
    .semantic-box.popup { border-color: #f0883e; background: rgba(240,136,62,.06); }
    .semantic-box.selected { border-color: #3fb950; background: rgba(63,185,80,.08); }
    .semantic-box.game { border-color: #bc8cff; background: rgba(188,140,255,.06); }
    .semantic-box.chart { border-color: #79c0ff; background: rgba(121,192,255,.06); }
    .semantic-label { position: absolute; top: -18px; left: -1px; max-width: 32ch; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; padding: 1px 6px; font: 11px/1.3 ui-monospace, SFMono-Regular, Menlo, monospace; background: #1a4a6e; color: #79c0ff; border-radius: 3px 3px 0 0; }
    .semantic-box.popup .semantic-label { background: #6e3a1a; color: #f0883e; }
    .semantic-box.selected .semantic-label { background: #1a4a2e; color: #3fb950; }
    .sidebar { display: flex; flex-direction: column; gap: 12px; }
    .cap-card { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 12px; }
    .cap-card h3 { font-size: 11px; text-transform: uppercase; letter-spacing: .05em; color: var(--muted); margin: 0 0 8px; }
    .cap-row { display: flex; align-items: center; gap: 6px; margin-bottom: 4px; font-size: 12px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    .cap-key { display: inline-flex; align-items: center; justify-content: center; min-width: 22px; height: 20px; padding: 0 5px; background: #1a4a6e; color: #79c0ff; border: 1px solid #388bfd; border-radius: 4px; font-size: 11px; font-weight: 600; }
    .game-log { display: none; max-height: 300px; overflow-y: auto; font-size: 11px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    .game-log.visible { display: block; }
    .game-turn { padding: 6px 0; border-bottom: 1px solid var(--border); }
    .game-turn:last-child { border-bottom: none; }
    .turn-header { display: flex; align-items: center; gap: 6px; margin-bottom: 4px; }
    .turn-badge { display: inline-flex; align-items: center; justify-content: center; min-width: 28px; height: 18px; padding: 0 4px; background: #6e3a1a; color: #f0883e; border: 1px solid #f0883e; border-radius: 4px; font-size: 10px; font-weight: 700; }
    .turn-move { color: var(--text); font-weight: 600; }
    .turn-reason { color: var(--muted); font-size: 10px; }
    .turn-state { color: #8b949e; font-size: 10px; margin-top: 2px; }
    .turn-score { color: #3fb950; font-size: 10px; }
    .turn-fail { color: #f85149; font-size: 10px; }
    .beam-seq { color: #bc8cff; font-size: 10px; margin-top: 2px; }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>${escapeHtml(title)}</h1>
      <button id="toggle-overlay" type="button" aria-pressed="${overlayEnabled ? "true" : "false"}">Overlay</button>
    </header>
    <div class="layout">
      <div class="player-frame">
        <div id="player"></div>
        <div id="semantic-overlay" aria-hidden="true"></div>
      </div>
      <aside class="sidebar" id="sidebar">
        <div class="cap-card"><h3>Application</h3><div id="app-info">-</div></div>
        <div class="cap-card"><h3>Navigate</h3><div id="nav-info">-</div></div>
        <div class="cap-card"><h3>Actions</h3><div id="actions-info">-</div></div>
        <div class="cap-card" id="game-log-card" style="display:none"><h3>Move Log</h3><div class="game-log" id="game-log"></div></div>
        <div class="cap-card" style="font-size:11px;font-family:monospace;white-space:pre-wrap"><h3>Debug</h3><div id="debug-info">-</div></div>
      </aside>
    </div>
  </main>
  <script src="https://cdn.jsdelivr.net/npm/asciinema-player@3.8.0/dist/bundle/asciinema-player.min.js"></script>
  <script>
    const CAST_URL = "${escapeHtml(castFileName)}";
    const SEMANTIC_INDEX_URL = "semantic-index.json";
    const SEMANTIC_SNAPSHOTS_URL = "semantic-snapshots.json";
    const GAME_LOG_URL = "game-log.json";
    let SEMANTIC_INDEX = [];       // [{t, sid, app, framework, confidence, cursor, altScreen}]
    let SEMANTIC_SNAPSHOTS = null;  // [{elements, capabilities, controls, ...}] or null if not loaded yet
    let GAME_LOG = null;           // [{turn, t, state, legalMoves, beamSearch, chosen, outcome}] or null
    let snapshotsLoading = false;
    let overlayEnabled = ${overlayEnabled ? "true" : "false"};

    // --- Part 3: Cell Metrics ---

    let cachedMetrics = null;

    function findTerminalMetrics() {
      if (cachedMetrics) return cachedMetrics;

      const apTerm = document.querySelector("#player pre.ap-terminal");
      if (!apTerm) return null;

      const cs = getComputedStyle(apTerm);
      const cols = parseInt(cs.getPropertyValue("--term-cols"))
        || parseInt(apTerm.style.getPropertyValue("--term-cols"));
      const lineHeightEm = parseFloat(cs.getPropertyValue("--term-line-height"))
        || parseFloat(apTerm.style.getPropertyValue("--term-line-height"))
        || 1.3333; // default line-height for monospace
      const fontSize = parseFloat(cs.fontSize);

      if (!cols || !fontSize) return null;

      // Calculate rows from terminal height and line height
      const lineHeight = fontSize * lineHeightEm;
      const termRect = apTerm.getBoundingClientRect();
      const rows = Math.round(termRect.height / lineHeight);

      if (!rows) return null;

      // pre.ap-terminal is content-box with no border/padding
      const cellWidth = termRect.width / cols;
      const cellHeight = termRect.height / rows;

      cachedMetrics = {
        offsetX: 0,
        offsetY: 0,
        cellWidth,
        cellHeight,
        cols, rows, fontSize,
      };
      return cachedMetrics;
    }

    function invalidateMetrics() {
      cachedMetrics = null;
    }

    // --- Part 4: Time Sync ---

    function currentPlayerTime() {
      try {
        return player ? player.getCurrentTime() : 0;
      } catch {
        // Internal clock not ready yet (recording still loading)
        return 0;
      }
    }

    // Binary search the index for the latest event at or before timeSeconds
    function latestIndexAt(timeSeconds) {
      let lo = 0, hi = SEMANTIC_INDEX.length - 1, result = null;
      while (lo <= hi) {
        const mid = (lo + hi) >> 1;
        if (SEMANTIC_INDEX[mid].t <= timeSeconds + 0.05) { result = SEMANTIC_INDEX[mid]; lo = mid + 1; }
        else { hi = mid - 1; }
      }
      return result;
    }

    // Reconstruct a full snapshot from index entry + snapshots table
    function snapshotFromIndex(idx) {
      if (!idx) return null;
      const base = { app: idx.app, framework: idx.framework, confidence: idx.confidence, cursor: idx.cursor, altScreen: idx.altScreen };
      if (SEMANTIC_SNAPSHOTS && idx.sid !== undefined) {
        const detail = SEMANTIC_SNAPSHOTS[idx.sid];
        if (detail) return Object.assign({}, base, detail);
      }
      return base; // sidebar-only data if snapshots not loaded yet
    }

    let player = null;
    let lastSid = -1; // track snapshot ID changes to avoid re-rendering same snapshot
    let pollInterval = null;

    function syncOverlay() {
      const t = currentPlayerTime();
      const idx = latestIndexAt(t);
      const dbg = document.getElementById("debug-info");
      if (dbg) dbg.textContent =
        "time: " + t.toFixed(2) + "\\n" +
        "events: " + SEMANTIC_INDEX.length + "\\n" +
        "snapshots: " + (SEMANTIC_SNAPSHOTS ? SEMANTIC_SNAPSHOTS.length : "not loaded") + "\\n" +
        "overlay: " + overlayEnabled + "\\n" +
        "app: " + (idx ? idx.app : "null") + "\\n" +
        "sid: " + (idx ? idx.sid : "-") + "\\n" +
        "metrics: " + (findTerminalMetrics() ? "ok" : "null");

      // Always update sidebar (works with just index data)
      if (idx) updateSidebarFromIndex(idx);

      // Only re-render overlay if snapshot changed and snapshots are loaded
      if (idx && idx.sid !== lastSid) {
        lastSid = idx.sid;
        if (SEMANTIC_SNAPSHOTS) {
          const snapshot = snapshotFromIndex(idx);
          renderSemanticOverlay(snapshot);
        }
      }

      // Sync game log to current time
      syncGameLog(t);
    }

    function startPolling() {
      if (pollInterval) return;
      pollInterval = setInterval(syncOverlay, 100);
    }

    function stopPolling() {
      if (pollInterval) {
        clearInterval(pollInterval);
        pollInterval = null;
      }
    }

    // --- Part 5: Overlay Rendering ---

    function displayText(value) {
      if (value == null) return "";
      if (typeof value === "object") return value.name || value.label || JSON.stringify(value);
      return String(value);
    }

    function escapeHtml(value) {
      return displayText(value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
    }

    function overlayTypeForNode(node) {
      if (node.role === "popup") return "popup";
      if (node.role === "list_item" && node.state?.selected) return "selected";
      if (node.role === "tab" && node.state?.selected) return "selected";
      if (node.role === "game_element") return "game";
      if (node.role === "chart") return "chart";
      return "default";
    }

    function renderSemanticOverlay(snapshot) {
      const overlay = document.getElementById("semantic-overlay");
      overlay.innerHTML = "";
      if (!overlayEnabled || !snapshot) return;

      const metrics = findTerminalMetrics();
      if (!metrics) return;

      const nodes = (snapshot.elements || []).filter(
        (node) => node?.bounds && node.role !== "screen"
      );

      for (const node of nodes) {
        const b = node.bounds;
        const box = document.createElement("div");
        box.className = "semantic-box " + overlayTypeForNode(node);
        box.style.left = (metrics.offsetX + b.x * metrics.cellWidth) + "px";
        box.style.top = (metrics.offsetY + b.y * metrics.cellHeight) + "px";
        box.style.width = (b.w * metrics.cellWidth) + "px";
        box.style.height = (b.h * metrics.cellHeight) + "px";

        const label = node.label || node.role;
        if (label && node.role !== "cursor") {
          const labelEl = document.createElement("span");
          labelEl.className = "semantic-label";
          labelEl.textContent = label;
          box.appendChild(labelEl);
        }

        overlay.appendChild(box);
      }

      updateSidebarFromSnapshot(snapshot);
    }

    // Sidebar update from index data only (no snapshots needed)
    function updateSidebarFromIndex(idx) {
      const app = idx.app || "unknown";
      const framework = idx.framework || "";
      document.getElementById("app-info").innerHTML =
        escapeHtml(app) +
        (framework
          ? '<br><span style="color:var(--muted)">' + escapeHtml(framework) + "</span>"
          : "");
    }

    // Full sidebar update from snapshot (when overlays are loaded)
    function updateSidebarFromSnapshot(snapshot) {
      updateSidebarFromIndex(snapshot);
      const caps = snapshot.capabilities || {};
      const navKeys = caps.navigate?.keys || [];
      document.getElementById("nav-info").innerHTML = navKeys.length
        ? navKeys
            .map(
              (k) =>
                '<div class="cap-row"><span class="cap-key">' +
                escapeHtml(k) +
                "</span><span>navigate</span></div>"
            )
            .join("")
        : "-";

      const actions = caps.actions || [];
      document.getElementById("actions-info").innerHTML = actions.length
        ? actions
            .map(
              (a) =>
                '<div class="cap-row"><span class="cap-key">' +
                escapeHtml(a.key) +
                "</span><span>" +
                escapeHtml(a.action) +
                "</span></div>"
            )
            .join("")
        : "-";
    }

    // --- Lazy snapshot loading ---

    async function loadSnapshots() {
      if (SEMANTIC_SNAPSHOTS || snapshotsLoading) return;
      snapshotsLoading = true;
      try {
        const resp = await fetch(SEMANTIC_SNAPSHOTS_URL);
        if (resp.ok) {
          SEMANTIC_SNAPSHOTS = await resp.json();
          console.log("Loaded " + SEMANTIC_SNAPSHOTS.length + " semantic snapshots");
          // Re-render with full data now
          lastSid = -1;
          syncOverlay();
        } else {
          console.warn("Snapshots fetch failed: " + resp.status);
        }
      } catch (err) {
        console.warn("Failed to load semantic snapshots:", err);
      }
      snapshotsLoading = false;
    }

    // --- Game Log ---

    async function loadGameLog() {
      if (GAME_LOG) return;
      try {
        const resp = await fetch(GAME_LOG_URL);
        if (resp.ok) {
          GAME_LOG = await resp.json();
          console.log("Loaded " + GAME_LOG.length + " game log entries");
          const card = document.getElementById("game-log-card");
          if (card && GAME_LOG.length > 0) {
            card.style.display = "";
            renderGameLog();
          }
        } else if (resp.status !== 404) {
          console.warn("Game log fetch failed: " + resp.status);
        }
      } catch (err) {
        // 404 is fine — not all recordings have game logs
        if (!err.message?.includes("404")) console.warn("Failed to load game log:", err);
      }
    }

    function moveLabel(m) {
      if (!m) return "?";
      const card = m.card || "";
      switch (m.type) {
        case "waste_to_foundation": return card + " → F" + m.to;
        case "tableau_to_foundation": return card + " → F" + m.to;
        case "tableau_to_tableau": return card + " T" + m.from + "→T" + m.to;
        case "waste_to_tableau": return card + " → T" + m.to;
        case "deal_stock": return "deal";
        case "recycle_stock": return "recycle";
        default: return m.type;
      }
    }

    function renderGameLog() {
      const el = document.getElementById("game-log");
      if (!el || !GAME_LOG) return;
      el.classList.add("visible");
      el.innerHTML = "";
      for (const entry of GAME_LOG) {
        const div = document.createElement("div");
        div.className = "game-turn";
        div.dataset.turn = entry.turn;
        div.dataset.t = entry.t;

        const chosen = moveLabel(entry.chosen?.move);
        const reason = entry.chosen?.reason || "";
        const success = entry.outcome?.success;
        const state = entry.state;
        const beam = entry.beamSearch?.topSequences || [];

        let html = '<div class="turn-header">';
        html += '<span class="turn-badge">' + entry.turn + '</span>';
        html += '<span class="turn-move">' + escapeHtml(chosen) + '</span>';
        if (success === false) html += ' <span class="turn-fail">FAILED</span>';
        else if (success === true) html += ' <span class="turn-score">✓</span>';
        html += '</div>';
        html += '<div class="turn-reason">' + escapeHtml(reason) + '</div>';

        // Compact state: foundations + face-down count
        if (state) {
          const fStr = (state.foundations || []).map(f => f.length > 0 ? f[f.length-1] : "·").join(" ");
          html += '<div class="turn-state">F:' + fStr + ' ↓' + (state.faceDownCount ?? "?") + '</div>';
        }

        // Top beam sequences (compact)
        if (beam.length > 1) {
          html += '<div class="beam-seq">';
          html += 'beam: ' + beam.slice(0, 2).map(s =>
            s.moves.map(m => moveLabel(m)).join("→") + " (" + s.score + ")"
          ).join(" | ");
          html += '</div>';
        }

        div.innerHTML = html;
        el.appendChild(div);
      }
    }

    function syncGameLog(t) {
      if (!GAME_LOG || GAME_LOG.length === 0) return;
      const el = document.getElementById("game-log");
      if (!el) return;

      // Find the latest turn at or before current time
      let lo = 0, hi = GAME_LOG.length - 1, result = null;
      while (lo <= hi) {
        const mid = (lo + hi) >> 1;
        if (GAME_LOG[mid].t <= t + 0.05) { result = GAME_LOG[mid]; lo = mid + 1; }
        else { hi = mid - 1; }
      }

      // Highlight the current turn, scroll to it
      const turns = el.querySelectorAll(".game-turn");
      let found = false;
      for (const turn of turns) {
        if (result && Number(turn.dataset.turn) === result.turn) {
          if (!turn.classList.contains("active")) {
            turn.classList.add("active");
            turn.style.background = "rgba(56,139,253,.08)";
            if (!found) turn.scrollIntoView({ block: "nearest", behavior: "smooth" });
            found = true;
          }
        } else {
          turn.classList.remove("active");
          turn.style.background = "";
        }
      }
    }

    // --- Initialization ---

    async function loadSemanticIndex() {
      ${hasSemanticEvents ? `try {
        const resp = await fetch(SEMANTIC_INDEX_URL);
        if (resp.ok) {
          SEMANTIC_INDEX = await resp.json();
          console.log("Loaded " + SEMANTIC_INDEX.length + " semantic index entries");
        } else {
          console.warn("Semantic index fetch failed: " + resp.status);
        }
      } catch (err) {
        console.warn("Failed to load semantic index:", err);
      }` : `// No semantic events in this recording`}
    }

    async function initPlayer() {
      await loadSemanticIndex();

      // If overlay is enabled by default, start loading snapshots immediately
      if (overlayEnabled && SEMANTIC_INDEX.length > 0) {
        loadSnapshots();
      }

      // Load game log eagerly (it's tiny — ~100KB)
      loadGameLog();

      try {
        player = window.AsciinemaPlayer.create(
          CAST_URL,
          document.getElementById("player"),
          { autoPlay: false, preload: true }
        );
      } catch (err) {
        console.error("AsciinemaPlayer.create failed:", err);
        document.getElementById("app-info").textContent = "Player failed: " + err.message;
        return;
      }

      if (!player) {
        console.error("AsciinemaPlayer.create returned null");
        document.getElementById("app-info").textContent = "Player returned null";
        return;
      }

      // Event-driven sync for state transitions
      player.addEventListener("play", () => {
        startPolling();
        syncOverlay();
      });

      player.addEventListener("pause", () => {
        stopPolling();
        syncOverlay();
      });

      player.addEventListener("seeked", () => {
        lastSid = -1; // force re-render even if same snapshot
        syncOverlay();
      });

      player.addEventListener("ended", () => {
        stopPolling();
        syncOverlay();
      });

      player.addEventListener("resize", () => {
        invalidateMetrics();
        if (lastSid >= 0) {
          const idx = latestIndexAt(currentPlayerTime());
          if (idx) renderSemanticOverlay(snapshotFromIndex(idx));
        }
      });

      // ResizeObserver for font-loading layout shifts on ap-terminal
      const apTermObserver = new ResizeObserver(() => {
        invalidateMetrics();
        if (lastSid >= 0) {
          const idx = latestIndexAt(currentPlayerTime());
          if (idx) renderSemanticOverlay(snapshotFromIndex(idx));
        }
      });

      const waitForApTerm = setInterval(() => {
        const apTerm = document.querySelector("#player pre.ap-terminal");
        if (apTerm) {
          apTermObserver.observe(apTerm);
          clearInterval(waitForApTerm);
        }
      }, 200);

      // Initial sync
      syncOverlay();
    }

    // Overlay toggle — loads snapshots lazily on first enable
    document.getElementById("toggle-overlay").addEventListener("click", () => {
      overlayEnabled = !overlayEnabled;
      document.getElementById("toggle-overlay").setAttribute(
        "aria-pressed", overlayEnabled ? "true" : "false"
      );
      // Lazy-load snapshots when overlay is first enabled
      if (overlayEnabled && !SEMANTIC_SNAPSHOTS && SEMANTIC_INDEX.length > 0) {
        loadSnapshots();
      }
      if (overlayEnabled && SEMANTIC_SNAPSHOTS) {
        lastSid = -1;
        syncOverlay();
      } else {
        document.getElementById("semantic-overlay").innerHTML = "";
      }
    });

    // Window resize
    window.addEventListener("resize", () => {
      invalidateMetrics();
      if (lastSid >= 0) {
        const idx = latestIndexAt(currentPlayerTime());
        if (idx) renderSemanticOverlay(snapshotFromIndex(idx));
      }
    });

    // Wait for DOM + AsciinemaPlayer to be ready
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", () => { initPlayer(); });
    } else {
      initPlayer();
    }
  </script>
</body>
</html>`;
}

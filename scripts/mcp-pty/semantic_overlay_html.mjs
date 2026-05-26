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

export function buildAsciinemaOverlayHtml({ title, castContent, semanticOverlay = false, castFileName = "playback.cast", semanticFileName = "semantic-events.json" }) {
  const { standardCast, semanticEvents } = splitSemanticCast(castContent);
  const overlayEnabled = semanticOverlay === true;
  const hasSemanticEvents = semanticEvents.length > 0;

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
        <div class="cap-card" style="font-size:11px;font-family:monospace;white-space:pre-wrap"><h3>Debug</h3><div id="debug-info">-</div></div>
      </aside>
    </div>
  </main>
  <script src="https://cdn.jsdelivr.net/npm/asciinema-player@3.8.0/dist/bundle/asciinema-player.min.js"></script>
  <script>
    const CAST_URL = "${escapeHtml(castFileName)}";
    const SEMANTIC_URL = "${escapeHtml(semanticFileName)}";
    let SEMANTIC_EVENTS = [];
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

    function latestSemanticSnapshotAt(timeSeconds) {
      let current = null;
      for (const event of SEMANTIC_EVENTS) {
        if (event.time <= timeSeconds) current = event.snapshot;
        else break;
      }
      return current;
    }

    let player = null;
    let lastSnapshot = null;
    let pollInterval = null;

    function syncOverlay() {
      const t = currentPlayerTime();
      const snapshot = latestSemanticSnapshotAt(t);
      const dbg = document.getElementById("debug-info");
      if (dbg) dbg.textContent =
        "time: " + t.toFixed(2) + "\\n" +
        "events: " + SEMANTIC_EVENTS.length + "\\n" +
        "overlay: " + overlayEnabled + "\\n" +
        "snapshot: " + (snapshot ? snapshot.app : "null") + "\\n" +
        "metrics: " + (findTerminalMetrics() ? "ok" : "null");
      if (snapshot !== lastSnapshot) {
        lastSnapshot = snapshot;
        renderSemanticOverlay(snapshot);
      }
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

      updateSidebar(snapshot);
    }

    function updateSidebar(snapshot) {
      const app = snapshot.app || "unknown";
      const framework = snapshot.framework || "";
      document.getElementById("app-info").innerHTML =
        escapeHtml(app) +
        (framework
          ? '<br><span style="color:var(--muted)">' + escapeHtml(framework) + "</span>"
          : "");

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

    // --- Initialization ---

    async function loadSemanticEvents() {
      ${hasSemanticEvents ? `try {
        const resp = await fetch(SEMANTIC_URL);
        if (resp.ok) {
          SEMANTIC_EVENTS = await resp.json();
          console.log("Loaded " + SEMANTIC_EVENTS.length + " semantic events");
        } else {
          console.warn("Semantic fetch failed: " + resp.status);
        }
      } catch (err) {
        console.warn("Failed to load semantic events:", err);
      }` : `// No semantic events in this recording`}
    }

    async function initPlayer() {
      await loadSemanticEvents();

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
        lastSnapshot = null; // force re-render even if same snapshot
        syncOverlay();
      });

      player.addEventListener("ended", () => {
        stopPolling();
        syncOverlay();
      });

      player.addEventListener("resize", () => {
        invalidateMetrics();
        if (lastSnapshot) renderSemanticOverlay(lastSnapshot);
      });

      // ResizeObserver for font-loading layout shifts on ap-terminal
      const apTermObserver = new ResizeObserver(() => {
        invalidateMetrics();
        if (lastSnapshot) renderSemanticOverlay(lastSnapshot);
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

    // Overlay toggle
    document.getElementById("toggle-overlay").addEventListener("click", () => {
      overlayEnabled = !overlayEnabled;
      document.getElementById("toggle-overlay").setAttribute(
        "aria-pressed", overlayEnabled ? "true" : "false"
      );
      renderSemanticOverlay(lastSnapshot);
    });

    // Window resize
    window.addEventListener("resize", () => {
      invalidateMetrics();
      if (lastSnapshot) renderSemanticOverlay(lastSnapshot);
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

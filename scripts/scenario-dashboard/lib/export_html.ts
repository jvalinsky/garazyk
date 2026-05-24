/**
 * Generate standalone HTML replay bundle for a run.
 *
 * @module lib/export_html
 */

import { extractMarkers, parseAsciicast } from "@garazyk/tui/testing";
import type { RunEventRow } from "../db/queries.ts";

/** Build a self-contained HTML page for offline replay. */
export function buildExportHtml(options: {
  runId: string;
  castContent?: string;
  events: RunEventRow[];
  startedAt: number;
}): string {
  const { runId, castContent, events, startedAt } = options;

  const markers = events
    .filter((e) =>
      e.eventType === "scenario_started" ||
      e.eventType === "scenario_finished" ||
      e.eventType === "run_failed"
    )
    .map((e) => ({
      t: e.timestamp - startedAt,
      label: formatEventLabel(e),
    }));

  const castMarkers = castContent
    ? extractMarkers(parseAsciicast(castContent).events).map((m) => ({
      t: m.t * 1000,
      label: m.label,
    }))
    : [];

  const allMarkers = [...markers, ...castMarkers];
  const castJson = castContent
    ? JSON.stringify(castContent)
    : "null";

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Run replay — ${escapeHtml(runId)}</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/asciinema-player@3.8.0/dist/bundle/asciinema-player.css" />
  <style>
    body { font-family: system-ui, sans-serif; margin: 1.5rem; background: #0f1419; color: #e6edf3; }
    h1 { font-size: 1.25rem; }
    .markers { display: flex; flex-wrap: wrap; gap: 0.5rem; margin: 1rem 0; }
    .markers button { background: #21262d; color: #e6edf3; border: 1px solid #30363d; padding: 0.25rem 0.5rem; border-radius: 4px; cursor: pointer; }
    #player { margin-top: 1rem; }
    .events { margin-top: 2rem; font-size: 0.875rem; max-height: 240px; overflow: auto; }
    .events li { margin: 0.25rem 0; }
  </style>
</head>
<body>
  <h1>Run replay: ${escapeHtml(runId)}</h1>
  <div class="markers" id="markers"></div>
  <div id="player"></div>
  <ul class="events" id="events"></ul>
  <script src="https://cdn.jsdelivr.net/npm/asciinema-player@3.8.0/dist/bundle/asciinema-player.min.js"></script>
  <script>
    const CAST = ${castJson};
    const MARKERS = ${JSON.stringify(allMarkers)};
    const EVENTS = ${JSON.stringify(events.map((e) => ({
    t: e.timestamp - startedAt,
    type: e.eventType,
    detail: e.detail,
  })))};

    const markersEl = document.getElementById("markers");
    MARKERS.forEach((m) => {
      const b = document.createElement("button");
      b.textContent = m.label + " (" + (m.t / 1000).toFixed(1) + "s)";
      b.onclick = () => { if (player && player.seek) player.seek(m.t / 1000); };
      markersEl.appendChild(b);
    });

    const eventsEl = document.getElementById("events");
    EVENTS.forEach((e) => {
      const li = document.createElement("li");
      li.textContent = (e.t / 1000).toFixed(1) + "s — " + e.type;
      eventsEl.appendChild(li);
    });

    let player = null;
    if (CAST && window.AsciinemaPlayer) {
      player = window.AsciinemaPlayer.create(
        { data: () => Promise.resolve(CAST) },
        document.getElementById("player"),
        { autoPlay: false, preload: true }
      );
    } else {
      document.getElementById("player").textContent = "No TUI recording for this run.";
    }
  </script>
</body>
</html>`;
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function formatEventLabel(row: RunEventRow): string {
  const d = row.detail;
  if (d.type === "scenario_started") {
    return `${d.scenarioId} started`;
  }
  if (d.type === "scenario_finished") {
    return `${d.scenarioId} ${d.status}`;
  }
  if (d.type === "run_failed") {
    return "run failed";
  }
  return row.eventType;
}

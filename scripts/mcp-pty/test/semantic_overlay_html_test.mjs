import test from "node:test";
import assert from "node:assert";
import {
  buildAsciinemaOverlayHtml,
  latestSemanticSnapshotAt,
  splitSemanticCast,
} from "../semantic_overlay_html.mjs";

// --- Part 1: Cast Splitting ---

test("splitSemanticCast extracts semantic events and keeps standard asciicast events", () => {
  const header = { version: 2, width: 20, height: 5, title: "demo" };
  const firstSnap = {
    app: "demo",
    elements: [{ role: "pane", bounds: { x: 1, y: 1, w: 5, h: 2 } }],
  };
  const secondSnap = {
    app: "demo",
    elements: [{ role: "popup", bounds: { x: 2, y: 1, w: 6, h: 3 } }],
  };
  const cast = [
    JSON.stringify(header),
    JSON.stringify([0, "r", "20x5"]),
    JSON.stringify([0.1, "o", "\x1b[2J\x1b[Hhello"]),
    JSON.stringify([0.2, "s", firstSnap]),
    JSON.stringify([0.3, "i", "j"]),
    JSON.stringify([0.4, "s", secondSnap]),
  ].join("\n");

  const result = splitSemanticCast(cast);

  assert.equal(result.semanticEvents.length, 2);
  assert.deepEqual(result.semanticEvents[0], { time: 0.2, snapshot: firstSnap });
  assert.deepEqual(result.semanticEvents[1], { time: 0.4, snapshot: secondSnap });

  const standardLines = result.standardCast.trimEnd().split("\n").map((line) => JSON.parse(line));
  assert.deepEqual(standardLines[0], header);
  assert.deepEqual(standardLines.slice(1).map((event) => event[1]), ["r", "o", "i"]);
});

test("splitSemanticCast skips malformed lines", () => {
  const header = { version: 2, width: 20, height: 5 };
  const cast = [
    JSON.stringify(header),
    "not json",
    JSON.stringify([0.1, "o", "hello"]),
    JSON.stringify([0.2]),  // wrong arity
    JSON.stringify([0.3, "s", { app: "demo" }]),
  ].join("\n");

  const result = splitSemanticCast(cast);

  assert.equal(result.semanticEvents.length, 1);
  assert.deepEqual(result.semanticEvents[0], { time: 0.3, snapshot: { app: "demo" } });

  const standardLines = result.standardCast.trimEnd().split("\n").map((l) => JSON.parse(l));
  assert.equal(standardLines.length, 2); // header + one o event
});

test("splitSemanticCast throws on empty input", () => {
  assert.throws(() => splitSemanticCast(""), /empty asciicast/i);
  assert.throws(() => splitSemanticCast(null), /empty asciicast/i);
});

test("latestSemanticSnapshotAt returns null before first event", () => {
  const events = [
    { time: 0.2, snapshot: { app: "first" } },
  ];
  assert.equal(latestSemanticSnapshotAt(events, 0.1), null);
});

test("latestSemanticSnapshotAt returns latest snapshot at or before given time", () => {
  const events = [
    { time: 0.2, snapshot: { app: "first" } },
    { time: 0.4, snapshot: { app: "second" } },
  ];
  assert.deepEqual(latestSemanticSnapshotAt(events, 0.2), { app: "first" });
  assert.deepEqual(latestSemanticSnapshotAt(events, 0.3), { app: "first" });
  assert.deepEqual(latestSemanticSnapshotAt(events, 0.5), { app: "second" });
});

test("latestSemanticSnapshotAt returns last snapshot for times after all events", () => {
  const events = [
    { time: 0.2, snapshot: { app: "first" } },
    { time: 0.4, snapshot: { app: "second" } },
  ];
  assert.deepEqual(latestSemanticSnapshotAt(events, 10.0), { app: "second" });
});

test("latestSemanticSnapshotAt returns null for empty events", () => {
  assert.equal(latestSemanticSnapshotAt([], 0.5), null);
});

// --- Part 2: HTML Shell ---

test("buildAsciinemaOverlayHtml embeds standard cast and semantic timeline separately", () => {
  const cast = [
    JSON.stringify({ version: 2, width: 20, height: 5, title: "demo" }),
    JSON.stringify([0.1, "o", "hello"]),
    JSON.stringify([0.2, "s", { app: "demo", elements: [] }]),
  ].join("\n");

  const html = buildAsciinemaOverlayHtml({
    title: "demo",
    castContent: cast,
    semanticOverlay: true,
  });

  assert.match(html, /asciinema-player@3\.8\.0/);
  assert.match(html, /id="semantic-overlay"/);
  assert.match(html, /id="player"/);
  assert.match(html, /id="sidebar"/);
  assert.match(html, /id="toggle-overlay"/);
  assert.match(html, /aria-pressed="true"/);
  assert.doesNotMatch(html, /applyTerminalData/);
  assert.doesNotMatch(html, /function handleCsi/);
});

test("buildAsciinemaOverlayHtml uses relative URL for cast source", () => {
  const cast = [
    JSON.stringify({ version: 2, width: 20, height: 5, title: "demo" }),
    JSON.stringify([0.1, "o", "hello"]),
  ].join("\n");

  const html = buildAsciinemaOverlayHtml({
    title: "demo",
    castContent: cast,
    semanticOverlay: false,
  });

  assert.match(html, /CAST_URL/);
  assert.match(html, /playback\.cast/);
  assert.doesNotMatch(html, /URL\.createObjectURL/);
  assert.doesNotMatch(html, /new Blob/);
  assert.doesNotMatch(html, /STANDARD_CAST_BASE64/);
});

test("buildAsciinemaOverlayHtml fetches semantic events from separate file", () => {
  const cast = [
    JSON.stringify({ version: 2, width: 20, height: 5, title: "demo" }),
    JSON.stringify([0.1, "o", "hello"]),
    JSON.stringify([0.2, "s", { app: "demo", elements: [] }]),
  ].join("\n");

  const html = buildAsciinemaOverlayHtml({
    title: "demo",
    castContent: cast,
    semanticOverlay: true,
  });

  assert.match(html, /SEMANTIC_URL/);
  assert.match(html, /semantic-events\.json/);
  assert.match(html, /fetch\(SEMANTIC_URL\)/);
  // No inline embedding of large semantic data (only empty initializer)
  assert.doesNotMatch(html, /SEMANTIC_EVENTS\s*=\s*\[{/);
});

test("buildAsciinemaOverlayHtml skips semantic fetch when no events", () => {
  const cast = [
    JSON.stringify({ version: 2, width: 20, height: 5, title: "demo" }),
    JSON.stringify([0.1, "o", "hello"]),
  ].join("\n");

  const html = buildAsciinemaOverlayHtml({
    title: "demo",
    castContent: cast,
    semanticOverlay: true,
  });

  assert.match(html, /No semantic events in this recording/);
  assert.doesNotMatch(html, /fetch\(SEMANTIC_URL\)/);
});

test("buildAsciinemaOverlayHtml sets overlay toggle to false when semanticOverlay is false", () => {
  const cast = [
    JSON.stringify({ version: 2, width: 20, height: 5, title: "demo" }),
    JSON.stringify([0.1, "o", "hello"]),
  ].join("\n");

  const html = buildAsciinemaOverlayHtml({
    title: "demo",
    castContent: cast,
    semanticOverlay: false,
  });

  assert.match(html, /aria-pressed="false"/);
  assert.match(html, /let overlayEnabled = false/);
});

test("buildAsciinemaOverlayHtml HTML-escapes title", () => {
  const cast = [
    JSON.stringify({ version: 2, width: 20, height: 5, title: "x" }),
    JSON.stringify([0.1, "o", "hello"]),
  ].join("\n");

  const html = buildAsciinemaOverlayHtml({
    title: '<script>alert("xss")</script>',
    castContent: cast,
  });

  assert.doesNotMatch(html, /<script>alert/);
  assert.match(html, /&lt;script&gt;/);
});

// --- Part 3: Cell Metrics ---

test("buildAsciinemaOverlayHtml includes findTerminalMetrics using ap-terminal CSS custom properties", () => {
  const cast = [
    JSON.stringify({ version: 2, width: 20, height: 5, title: "demo" }),
    JSON.stringify([0.1, "o", "hello"]),
    JSON.stringify([0.2, "s", { app: "demo", elements: [] }]),
  ].join("\n");

  const html = buildAsciinemaOverlayHtml({
    title: "demo",
    castContent: cast,
    semanticOverlay: true,
  });

  assert.match(html, /querySelector.*ap-terminal/);
  assert.match(html, /--term-cols/);
  assert.match(html, /--term-line-height/);
  assert.match(html, /cachedMetrics/);
  assert.match(html, /invalidateMetrics/);
  assert.doesNotMatch(html, /probe\.getBoundingClientRect/);
  assert.doesNotMatch(html, /0\.75/);
});

test("buildAsciinemaOverlayHtml includes ResizeObserver for layout shifts", () => {
  const cast = [
    JSON.stringify({ version: 2, width: 20, height: 5, title: "demo" }),
    JSON.stringify([0.1, "o", "hello"]),
  ].join("\n");

  const html = buildAsciinemaOverlayHtml({
    title: "demo",
    castContent: cast,
    semanticOverlay: true,
  });

  assert.match(html, /ResizeObserver/);
});

// --- Part 4: Time Sync ---

test("buildAsciinemaOverlayHtml includes player time polling via getCurrentTime()", () => {
  const cast = [
    JSON.stringify({ version: 2, width: 20, height: 5, title: "demo" }),
    JSON.stringify([0.1, "o", "hello"]),
    JSON.stringify([0.2, "s", { app: "demo", elements: [] }]),
  ].join("\n");

  const html = buildAsciinemaOverlayHtml({
    title: "demo",
    castContent: cast,
    semanticOverlay: true,
  });

  assert.match(html, /player\.getCurrentTime/);
  assert.match(html, /setInterval.*syncOverlay/);
});

test("buildAsciinemaOverlayHtml includes seeked event listener", () => {
  const cast = [
    JSON.stringify({ version: 2, width: 20, height: 5, title: "demo" }),
    JSON.stringify([0.1, "o", "hello"]),
  ].join("\n");

  const html = buildAsciinemaOverlayHtml({
    title: "demo",
    castContent: cast,
    semanticOverlay: true,
  });

  assert.match(html, /addEventListener.*seeked/);
  assert.match(html, /addEventListener.*play/);
  assert.match(html, /addEventListener.*pause/);
});

test("buildAsciinemaOverlayHtml does NOT include synthetic clock fallback", () => {
  const cast = [
    JSON.stringify({ version: 2, width: 20, height: 5, title: "demo" }),
    JSON.stringify([0.1, "o", "hello"]),
  ].join("\n");

  const html = buildAsciinemaOverlayHtml({
    title: "demo",
    castContent: cast,
    semanticOverlay: true,
  });

  assert.doesNotMatch(html, /syntheticStartTime/);
  assert.doesNotMatch(html, /notePlaybackStarted/);
});

test("buildAsciinemaOverlayHtml uses relative URL for AsciinemaPlayer.create", () => {
  const cast = [
    JSON.stringify({ version: 2, width: 20, height: 5, title: "demo" }),
    JSON.stringify([0.1, "o", "hello"]),
  ].join("\n");

  const html = buildAsciinemaOverlayHtml({
    title: "demo",
    castContent: cast,
    semanticOverlay: true,
  });

  assert.match(html, /AsciinemaPlayer\.create/);
  assert.match(html, /CAST_URL/);
  assert.doesNotMatch(html, /new Blob/);
  assert.doesNotMatch(html, /URL\.createObjectURL/);
  assert.doesNotMatch(html, /STANDARD_CAST_BASE64/);
});

test("buildAsciinemaOverlayHtml uses custom castFileName when provided", () => {
  const cast = [
    JSON.stringify({ version: 2, width: 20, height: 5, title: "demo" }),
    JSON.stringify([0.1, "o", "hello"]),
  ].join("\n");

  const html = buildAsciinemaOverlayHtml({
    title: "demo",
    castContent: cast,
    semanticOverlay: true,
    castFileName: "custom-recording.cast",
  });

  assert.match(html, /custom-recording\.cast/);
});

// --- Part 5: Overlay Rendering ---

test("buildAsciinemaOverlayHtml includes renderSemanticOverlay function", () => {
  const cast = [
    JSON.stringify({ version: 2, width: 20, height: 5, title: "demo" }),
    JSON.stringify([0.1, "o", "hello"]),
    JSON.stringify([0.2, "s", {
      app: "gitui",
      framework: "ratatui",
      elements: [
        { role: "pane", bounds: { x: 0, y: 0, w: 20, h: 5 } },
        { role: "popup", label: "Help", bounds: { x: 5, y: 1, w: 10, h: 3 } },
        { role: "list_item", state: { selected: true }, label: "Unstaged", bounds: { x: 1, y: 1, w: 8, h: 1 } },
      ],
      capabilities: {
        navigate: { keys: ["j", "k", "h", "l"] },
        actions: [{ key: "q", action: "quit" }, { key: "?", action: "help" }],
      },
    }]),
  ].join("\n");

  const html = buildAsciinemaOverlayHtml({
    title: "demo",
    castContent: cast,
    semanticOverlay: true,
  });

  assert.match(html, /function renderSemanticOverlay/);
  assert.match(html, /function overlayTypeForNode/);
  assert.match(html, /function updateSidebar/);
  assert.match(html, /function escapeHtml/);
});

test("buildAsciinemaOverlayHtml includes all overlay type CSS classes", () => {
  const cast = [
    JSON.stringify({ version: 2, width: 20, height: 5, title: "demo" }),
    JSON.stringify([0.1, "o", "hello"]),
  ].join("\n");

  const html = buildAsciinemaOverlayHtml({
    title: "demo",
    castContent: cast,
    semanticOverlay: true,
  });

  assert.match(html, /\.semantic-box\.popup/);
  assert.match(html, /\.semantic-box\.selected/);
  assert.match(html, /\.semantic-box\.game/);
  assert.match(html, /\.semantic-box\.chart/);
  assert.match(html, /\.semantic-label/);
});

test("buildAsciinemaOverlayHtml sidebar has all cap-card sections", () => {
  const cast = [
    JSON.stringify({ version: 2, width: 20, height: 5, title: "demo" }),
    JSON.stringify([0.1, "o", "hello"]),
  ].join("\n");

  const html = buildAsciinemaOverlayHtml({
    title: "demo",
    castContent: cast,
    semanticOverlay: true,
  });

  assert.match(html, /id="app-info"/);
  assert.match(html, /id="nav-info"/);
  assert.match(html, /id="actions-info"/);
});

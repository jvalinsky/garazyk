import test from "node:test";
import assert from "node:assert";
import { buildStandaloneHtml } from "../recording.mjs";

test("buildStandaloneHtml delegates to Asciinema Player (no custom emulator)", () => {
  const html = buildStandaloneHtml({
    title: "metrics",
    castContent: `${JSON.stringify({ version: 2, width: 10, height: 4 })}\n`,
    semanticOverlay: true,
  });

  // Asciinema Player is used instead of custom terminal emulator
  assert.match(html, /AsciinemaPlayer\.create/);
  assert.match(html, /id="player"/);
  assert.match(html, /id="semantic-overlay"/);
  assert.match(html, /CAST_URL/);
  assert.match(html, /SEMANTIC_EVENTS/);

  // No base64 embedding or Blob URL
  assert.doesNotMatch(html, /STANDARD_CAST_BASE64/);

  // Custom emulator code should be gone
  assert.doesNotMatch(html, /applyTerminalData/);
  assert.doesNotMatch(html, /function handleCsi/);
  assert.doesNotMatch(html, /function handleSgr/);
  assert.doesNotMatch(html, /function charMetrics/);
  assert.doesNotMatch(html, /function boundsToPixels/);
  assert.doesNotMatch(html, /function makeBoundsBox/);
  assert.doesNotMatch(html, /id="measure"/);
});

test("buildStandaloneHtml uses CSS custom properties for cell metrics (no JS measurement)", () => {
  const html = buildStandaloneHtml({
    title: "metrics",
    castContent: `${JSON.stringify({ version: 2, width: 10, height: 4 })}\n`,
    semanticOverlay: true,
  });

  // Cell metrics from pre.ap-terminal CSS custom properties
  assert.match(html, /querySelector.*ap-terminal/);
  assert.match(html, /--term-cols/);
  assert.match(html, /cachedMetrics/);

  // No probe element measurement
  assert.doesNotMatch(html, /probe\.getBoundingClientRect/);
});

test("buildStandaloneHtml uses player clock (no synthetic fallback)", () => {
  const html = buildStandaloneHtml({
    title: "playback",
    castContent: [
      JSON.stringify({ version: 2, width: 10, height: 4 }),
      JSON.stringify([0, "r", "10x4"]),
      JSON.stringify([0.01, "o", "\x1b[2J\x1b[Habcdefghij\r\nnext"]),
      JSON.stringify([0.02, "s", {
        app: "demo",
        confidence: 0.9,
        framework: "unknown",
        capabilities: { navigate: { keys: [] }, quit: { keys: [] } },
      }]),
    ].join("\n"),
    semanticOverlay: true,
  });

  // Uses player.getCurrentTime() for time sync
  assert.match(html, /player\.getCurrentTime/);

  // Listens for seeked event
  assert.match(html, /addEventListener.*seeked/);

  // No synthetic clock fallback
  assert.doesNotMatch(html, /syntheticStartTime/);
  assert.doesNotMatch(html, /notePlaybackStarted/);

  // Semantic overlay rendering functions exist
  assert.match(html, /function renderSemanticOverlay/);
  assert.match(html, /function displayText/);
  assert.match(html, /function escapeHtml/);
});

test("buildStandaloneHtml uses relative URL for cast source", () => {
  const html = buildStandaloneHtml({
    title: "url",
    castContent: `${JSON.stringify({ version: 2, width: 10, height: 4 })}\n`,
    semanticOverlay: true,
  });

  assert.match(html, /CAST_URL/);
  assert.match(html, /playback\.cast/);
  assert.doesNotMatch(html, /STANDARD_CAST_BASE64/);
  assert.doesNotMatch(html, /new Blob/);
  assert.doesNotMatch(html, /URL\.createObjectURL/);
});

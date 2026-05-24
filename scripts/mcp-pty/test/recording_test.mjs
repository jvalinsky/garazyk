import test from "node:test";
import assert from "node:assert";
import { buildStandaloneHtml } from "../recording.mjs";

test("standalone replay measures overlay cells with terminal font metrics", () => {
  const html = buildStandaloneHtml({
    title: "metrics",
    castContent: `${JSON.stringify({ version: 2, width: 10, height: 4 })}\n`,
    semanticOverlay: true,
  });

  assert.match(html, /#terminal \{[^}]*font-family: ui-monospace/);
  assert.match(html, /#measure \{[^}]*font-family: ui-monospace/);
  assert.match(html, /rect\.width \/ measure\.textContent\.length/);
  assert.match(html, /function boundsToPixels/);
});

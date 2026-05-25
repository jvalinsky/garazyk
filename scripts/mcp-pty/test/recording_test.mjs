import test from "node:test";
import assert from "node:assert";
import { buildStandaloneHtml } from "../recording.mjs";

test("standalone replay positions overlay cells with CSS ch/lh units (no JS measurement)", () => {
  const html = buildStandaloneHtml({
    title: "metrics",
    castContent: `${JSON.stringify({ version: 2, width: 10, height: 4 })}\n`,
    semanticOverlay: true,
  });

  // Terminal and overlay share the same monospace font so ch/lh resolve correctly
  assert.match(html, /#terminal \{[^}]*font-family: ui-monospace/);
  assert.match(html, /#overlay \{[^}]*font-family: ui-monospace/);
  assert.match(html, /#overlay \{[^}]*font-size: 13px/);
  assert.match(html, /#overlay \{[^}]*line-height: 1\.4/);

  // Check overlay uses CSS ch/lh units via custom properties
  assert.match(html, /left:\s*calc\(var\(--x\)\s*\*\s*1ch\)/);
  assert.match(html, /top:\s*calc\(var\(--y\)\s*\*\s*1lh\)/);
  assert.match(html, /width:\s*calc\(var\(--w\)\s*\*\s*1ch\)/);
  assert.match(html, /height:\s*calc\(var\(--h\)\s*\*\s*1lh\)/);

  // Verify no charMetrics / boundsToPixels / #measure JS measurement remains
  assert.match(html, /function makeBox/, "makeBox should exist");
  assert.doesNotMatch(html, /function charMetrics/, "charMetrics should be removed");
  assert.doesNotMatch(html, /function boundsToPixels/, "boundsToPixels should be removed");
  assert.doesNotMatch(html, /function makeBoundsBox/, "makeBoundsBox should be removed");
  assert.doesNotMatch(html, /id="measure"/, "#measure element should be removed");
});

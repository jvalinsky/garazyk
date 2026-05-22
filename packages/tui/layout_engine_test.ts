/**
 * Tests for the pure layout engine — geometry utilities.
 *
 * @module tui/layout_engine_test
 */

import { assert, assertEquals } from "@std/assert";
import {
  type BoundingBox,
  clipBox,
  computePanelGeometry,
  contains,
  isValidBox,
  overlaps,
  type PanelLayout,
  pointInBox,
  translateBox,
} from "./layout_engine.ts";

Deno.test("computePanelGeometry: computes outer, inner, and scrollable areas", () => {
  const panel: PanelLayout = {
    id: "network",
    x: 0,
    y: 1,
    width: 50,
    height: 20,
  };

  const geometry = computePanelGeometry(panel, false);

  // Outer should match panel dimensions
  assertEquals(geometry.outer, { x: 0, y: 1, width: 50, height: 20 });

  // Inner should be inside borders (1 cell on each side)
  assertEquals(geometry.inner, { x: 1, y: 2, width: 48, height: 18 });

  // Scrollable should match inner when no action hints
  assertEquals(geometry.scrollable, { x: 1, y: 2, width: 48, height: 18 });
});

Deno.test("computePanelGeometry: reduces scrollable height with action hints", () => {
  const panel: PanelLayout = {
    id: "network",
    x: 0,
    y: 1,
    width: 50,
    height: 20,
  };

  const geometry = computePanelGeometry(panel, true);

  // Inner should be inside borders
  assertEquals(geometry.inner, { x: 1, y: 2, width: 48, height: 18 });

  // Scrollable should be 1 row less than inner (for action hints)
  assertEquals(geometry.scrollable, { x: 1, y: 2, width: 48, height: 17 });
});

Deno.test("computePanelGeometry: handles small panels", () => {
  const panel: PanelLayout = {
    id: "network",
    x: 0,
    y: 0,
    width: 2,
    height: 2,
  };

  const geometry = computePanelGeometry(panel, false);

  // Inner dimensions should be 0 (too small for borders)
  assertEquals(geometry.inner.width, 0);
  assertEquals(geometry.inner.height, 0);
  assertEquals(geometry.scrollable.width, 0);
  assertEquals(geometry.scrollable.height, 0);
});

Deno.test("overlaps: detects overlapping boxes", () => {
  const box1: BoundingBox = { x: 0, y: 0, width: 10, height: 10 };
  const box2: BoundingBox = { x: 5, y: 5, width: 10, height: 10 };

  assert(overlaps(box1, box2), "Boxes should overlap");
  assert(overlaps(box2, box1), "Overlap should be symmetric");
});

Deno.test("overlaps: detects non-overlapping boxes", () => {
  const box1: BoundingBox = { x: 0, y: 0, width: 10, height: 10 };
  const box2: BoundingBox = { x: 10, y: 0, width: 10, height: 10 };

  assert(!overlaps(box1, box2), "Adjacent boxes should not overlap");
});

Deno.test("overlaps: handles completely separate boxes", () => {
  const box1: BoundingBox = { x: 0, y: 0, width: 10, height: 10 };
  const box2: BoundingBox = { x: 20, y: 20, width: 10, height: 10 };

  assert(!overlaps(box1, box2), "Separate boxes should not overlap");
});

Deno.test("contains: detects contained box", () => {
  const outer: BoundingBox = { x: 0, y: 0, width: 100, height: 50 };
  const inner: BoundingBox = { x: 10, y: 10, width: 20, height: 20 };

  assert(contains(inner, outer), "Inner box should be contained");
});

Deno.test("contains: detects box extending beyond bounds", () => {
  const outer: BoundingBox = { x: 0, y: 0, width: 100, height: 50 };
  const partial: BoundingBox = { x: 50, y: 40, width: 60, height: 20 };

  assert(!contains(partial, outer), "Partial box should not be contained");
});

Deno.test("contains: handles box on boundary", () => {
  const outer: BoundingBox = { x: 0, y: 0, width: 100, height: 50 };
  const boundary: BoundingBox = { x: 0, y: 0, width: 100, height: 50 };

  assert(contains(boundary, outer), "Box on boundary should be contained");
});

Deno.test("pointInBox: detects point inside box", () => {
  const box: BoundingBox = { x: 10, y: 10, width: 20, height: 20 };

  assert(pointInBox(15, 15, box), "Point should be inside box");
  assert(pointInBox(10, 10, box), "Point on top-left corner should be inside");
});

Deno.test("pointInBox: detects point outside box", () => {
  const box: BoundingBox = { x: 10, y: 10, width: 20, height: 20 };

  assert(!pointInBox(5, 5, box), "Point before box should be outside");
  assert(
    !pointInBox(30, 30, box),
    "Point on bottom-right boundary should be outside",
  );
  assert(!pointInBox(35, 35, box), "Point after box should be outside");
});

Deno.test("clipBox: clips box to region", () => {
  const box: BoundingBox = { x: 0, y: 0, width: 100, height: 50 };
  const clip: BoundingBox = { x: 50, y: 25, width: 100, height: 50 };

  const clipped = clipBox(box, clip);

  assertEquals(clipped, { x: 50, y: 25, width: 50, height: 25 });
});

Deno.test("clipBox: returns zero-size box for non-overlapping regions", () => {
  const box: BoundingBox = { x: 0, y: 0, width: 10, height: 10 };
  const clip: BoundingBox = { x: 20, y: 20, width: 10, height: 10 };

  const clipped = clipBox(box, clip);

  assertEquals(clipped.width, 0);
  assertEquals(clipped.height, 0);
});

Deno.test("clipBox: handles box fully inside clip region", () => {
  const box: BoundingBox = { x: 10, y: 10, width: 20, height: 20 };
  const clip: BoundingBox = { x: 0, y: 0, width: 100, height: 100 };

  const clipped = clipBox(box, clip);

  assertEquals(clipped, box);
});

Deno.test("isValidBox: validates correct boxes", () => {
  assert(isValidBox({ x: 0, y: 0, width: 10, height: 10 }));
  assert(isValidBox({ x: 100, y: 50, width: 1, height: 1 }));
});

Deno.test("isValidBox: rejects invalid boxes", () => {
  assert(!isValidBox({ x: -1, y: 0, width: 10, height: 10 }), "Negative x");
  assert(!isValidBox({ x: 0, y: -1, width: 10, height: 10 }), "Negative y");
  assert(!isValidBox({ x: 0, y: 0, width: 0, height: 10 }), "Zero width");
  assert(!isValidBox({ x: 0, y: 0, width: 10, height: 0 }), "Zero height");
  assert(!isValidBox({ x: 0, y: 0, width: -5, height: 10 }), "Negative width");
});

Deno.test("translateBox: moves box by offset", () => {
  const box: BoundingBox = { x: 10, y: 10, width: 20, height: 20 };

  const translated = translateBox(box, 5, -3);

  assertEquals(translated, { x: 15, y: 7, width: 20, height: 20 });
});

Deno.test("translateBox: handles zero offset", () => {
  const box: BoundingBox = { x: 10, y: 10, width: 20, height: 20 };

  const translated = translateBox(box, 0, 0);

  assertEquals(translated, box);
});

Deno.test("translateBox: handles negative offsets", () => {
  const box: BoundingBox = { x: 10, y: 10, width: 20, height: 20 };

  const translated = translateBox(box, -5, -5);

  assertEquals(translated, { x: 5, y: 5, width: 20, height: 20 });
});

// ── Non-overlap property tests (using tree solver) ───────────────────────────

import {
  dashboardLayoutTree,
  findResolvedNode,
  PANEL_IDS,
  solveLayout,
} from "./layout.ts";

/**
 * Helper: assert that no two panels in a resolved layout overlap.
 *
 * Validates Property 1 from the design doc:
 *   ∀ p1, p2 ∈ panels where p1 ≠ p2: ¬overlaps(p1, p2)
 */
function assertNoPanelOverlap(cols: number, rows: number): void {
  const tree = dashboardLayoutTree(cols, rows);
  assert(tree !== null, `Expected non-null tree for ${cols}x${rows}`);
  const layout = solveLayout(tree, { x: 0, y: 0, width: cols, height: rows });

  const panels = PANEL_IDS.map((id) => findResolvedNode(layout, id)!).filter(
    Boolean,
  );
  for (let i = 0; i < panels.length; i++) {
    for (let j = i + 1; j < panels.length; j++) {
      const p1 = panels[i]!;
      const p2 = panels[j]!;
      assert(
        !overlaps(p1, p2),
        `Panels "${p1.id}" and "${p2.id}" overlap in ${cols}x${rows} layout: ` +
          `p1=(${p1.x},${p1.y},${p1.width}x${p1.height}) ` +
          `p2=(${p2.x},${p2.y},${p2.width}x${p2.height})`,
      );
    }
  }
}

// Wide layout (cols >= 100) — 2x2 grid

Deno.test("non-overlap: wide layout 100x24 (minimum wide)", () => {
  assertNoPanelOverlap(100, 24);
});

Deno.test("non-overlap: wide layout 120x30", () => {
  assertNoPanelOverlap(120, 30);
});

Deno.test("non-overlap: wide layout 160x40", () => {
  assertNoPanelOverlap(160, 40);
});

Deno.test("non-overlap: wide layout 200x50 (large terminal)", () => {
  assertNoPanelOverlap(200, 50);
});

Deno.test("non-overlap: wide layout 220x60 (very large terminal)", () => {
  assertNoPanelOverlap(220, 60);
});

// Narrow layout (cols < 100) — vertical stack

Deno.test("non-overlap: narrow layout 40x16 (minimum size)", () => {
  assertNoPanelOverlap(40, 16);
});

Deno.test("non-overlap: narrow layout 80x24 (standard 80-col terminal)", () => {
  assertNoPanelOverlap(80, 24);
});

Deno.test("non-overlap: narrow layout 99x30 (just below wide threshold)", () => {
  assertNoPanelOverlap(99, 30);
});

Deno.test("non-overlap: narrow layout 60x40", () => {
  assertNoPanelOverlap(60, 40);
});

Deno.test("non-overlap: narrow layout 50x20", () => {
  assertNoPanelOverlap(50, 20);
});

// Terminal too small — dashboardLayoutTree returns null

Deno.test("non-overlap: returns null for too-small terminal (cols < 40)", () => {
  const tree = dashboardLayoutTree(39, 24);
  assertEquals(tree, null, "Should return null for cols < 40");
});

Deno.test("non-overlap: returns null for too-small terminal (rows < 16)", () => {
  const tree = dashboardLayoutTree(80, 15);
  assertEquals(tree, null, "Should return null for rows < 16");
});

Deno.test("non-overlap: returns null for tiny terminal", () => {
  const tree = dashboardLayoutTree(10, 10);
  assertEquals(tree, null, "Should return null for tiny terminal");
});

// Boundary between wide and narrow

Deno.test("non-overlap: layout at wide threshold boundary (99 vs 100 cols)", () => {
  assertNoPanelOverlap(99, 24); // narrow
  assertNoPanelOverlap(100, 24); // wide
});

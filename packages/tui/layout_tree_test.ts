/**
 * Tests for the generic layout tree solver.
 *
 * @module tui/layout_tree_test
 */

import { assertEquals } from "@std/assert";
import { type LayoutNode, solveLayout } from "./layout_tree.ts";

Deno.test("solveLayout: single node fills bounds", () => {
  const root: LayoutNode = { id: "root" };
  const bounds = { x: 0, y: 0, width: 80, height: 24 };
  const resolved = solveLayout(root, bounds);

  assertEquals(resolved.x, 0);
  assertEquals(resolved.y, 0);
  assertEquals(resolved.width, 80);
  assertEquals(resolved.height, 24);
  assertEquals(resolved.children.length, 0);
});

Deno.test("solveLayout: vertical stack with fixed heights", () => {
  const root: LayoutNode = {
    id: "root",
    direction: "column",
    children: [
      { id: "header", height: 1 },
      { id: "content", height: 22 },
      { id: "footer", height: 1 },
    ],
  };
  const bounds = { x: 0, y: 0, width: 80, height: 24 };
  const resolved = solveLayout(root, bounds);

  assertEquals(resolved.children[0].id, "header");
  assertEquals(resolved.children[0].y, 0);
  assertEquals(resolved.children[0].height, 1);

  assertEquals(resolved.children[1].id, "content");
  assertEquals(resolved.children[1].y, 1);
  assertEquals(resolved.children[1].height, 22);

  assertEquals(resolved.children[2].id, "footer");
  assertEquals(resolved.children[2].y, 23);
  assertEquals(resolved.children[2].height, 1);
});

Deno.test("solveLayout: horizontal stack with growing widths", () => {
  const root: LayoutNode = {
    id: "root",
    direction: "row",
    children: [
      { id: "left", width: "grow" },
      { id: "right", width: "grow" },
    ],
  };
  const bounds = { x: 0, y: 0, width: 80, height: 24 };
  const resolved = solveLayout(root, bounds);

  assertEquals(resolved.children[0].id, "left");
  assertEquals(resolved.children[0].x, 0);
  assertEquals(resolved.children[0].width, 40);

  assertEquals(resolved.children[1].id, "right");
  assertEquals(resolved.children[1].x, 40);
  assertEquals(resolved.children[1].width, 40);
});

Deno.test("solveLayout: nested layout (2x2 grid)", () => {
  const root: LayoutNode = {
    id: "root",
    direction: "column",
    children: [
      {
        direction: "row",
        height: "grow",
        children: [
          { id: "top-left", width: "grow" },
          { id: "top-right", width: "grow" },
        ],
      },
      {
        direction: "row",
        height: "grow",
        children: [
          { id: "bottom-left", width: "grow" },
          { id: "bottom-right", width: "grow" },
        ],
      },
    ],
  };
  const bounds = { x: 0, y: 0, width: 100, height: 20 };
  const resolved = solveLayout(root, bounds);

  assertEquals(resolved.children[0].children[0].id, "top-left");
  assertEquals(resolved.children[0].children[0].width, 50);
  assertEquals(resolved.children[0].children[0].height, 10);

  assertEquals(resolved.children[1].children[1].id, "bottom-right");
  assertEquals(resolved.children[1].children[1].x, 50);
  assertEquals(resolved.children[1].children[1].y, 10);
});

Deno.test("solveLayout: supports gaps", () => {
  const root: LayoutNode = {
    id: "root",
    direction: "row",
    gap: 2,
    children: [
      { id: "left", width: 30 },
      { id: "right", width: "grow" },
    ],
  };
  const bounds = { x: 0, y: 0, width: 80, height: 24 };
  const resolved = solveLayout(root, bounds);

  assertEquals(resolved.children[0].width, 30);
  assertEquals(resolved.children[1].x, 32); // 30 + 2 gap
  assertEquals(resolved.children[1].width, 48); // 80 - 30 - 2
});

import { assertEquals } from "@std/assert";
import { solveLayout } from "./layout_tree.ts";

Deno.test("solveLayout: respects maxWidth", () => {
  const root = {
    direction: "row" as const,
    children: [
      { id: "left", width: "grow" as const, maxWidth: 10 },
      { id: "right", width: "grow" as const },
    ],
  };
  const bounds = { x: 0, y: 0, width: 100, height: 10 };
  const resolved = solveLayout(root, bounds);

  const left = resolved.children.find((c) => c.id === "left")!;
  const right = resolved.children.find((c) => c.id === "right")!;

  assertEquals(left.width, 10);
  assertEquals(right.width, 90);
});

Deno.test("solveLayout: respects minWidth", () => {
  const root = {
    direction: "row" as const,
    children: [
      { id: "left", width: 10, minWidth: 20 },
      { id: "right", width: "grow" as const },
    ],
  };
  const bounds = { x: 0, y: 0, width: 100, height: 10 };
  const resolved = solveLayout(root, bounds);

  const left = resolved.children.find((c) => c.id === "left")!;
  assertEquals(left.width, 20);
});

Deno.test("solveLayout: respects padding (number)", () => {
  const root = {
    padding: 2,
    children: [{
      id: "child",
      width: "grow" as const,
      height: "grow" as const,
    }],
  };
  const bounds = { x: 0, y: 0, width: 100, height: 100 };
  const resolved = solveLayout(root, bounds);

  const child = resolved.children[0];
  assertEquals(child.x, 2);
  assertEquals(child.y, 2);
  assertEquals(child.width, 96);
  assertEquals(child.height, 96);
});

Deno.test("solveLayout: respects padding (object)", () => {
  const root = {
    padding: { top: 1, left: 2, right: 3, bottom: 4 },
    children: [{
      id: "child",
      width: "grow" as const,
      height: "grow" as const,
    }],
  };
  const bounds = { x: 0, y: 0, width: 10, height: 10 };
  const resolved = solveLayout(root, bounds);

  const child = resolved.children[0];
  assertEquals(child.x, 2);
  assertEquals(child.y, 1);
  assertEquals(child.width, 10 - 2 - 3);
  assertEquals(child.height, 10 - 1 - 4);
});

Deno.test("solveLayout: deterministic remainder distribution", () => {
  const root = {
    direction: "row" as const,
    children: [
      { id: "c1", width: "grow" as const },
      { id: "c2", width: "grow" as const },
      { id: "c3", width: "grow" as const },
    ],
  };
  // 10 / 3 = 3 remainder 1. The last child should get the remainder.
  const bounds = { x: 0, y: 0, width: 10, height: 1 };
  const resolved = solveLayout(root, bounds);

  assertEquals(resolved.children[0].width, 3);
  assertEquals(resolved.children[1].width, 3);
  assertEquals(resolved.children[2].width, 4);
});

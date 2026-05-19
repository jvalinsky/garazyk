/**
 * Tests for the render command pipeline and rasterizer.
 *
 * @module tui/command_test
 */

import { assert, assertEquals } from "@std/assert";
import { ANSI, DEFAULT_STYLE, fg, ScreenBuffer } from "./renderer.ts";
import { type BoundingBox, rasterize, type RenderCommand } from "./command.ts";

// ── TextCommand ──────────────────────────────────────────────────────────────

Deno.test("rasterize: TextCommand writes text at position", () => {
  const buf = new ScreenBuffer(20, 5);
  const commands: RenderCommand[] = [
    { type: "text", x: 2, y: 1, text: "Hello", style: fg(ANSI.GREEN) },
  ];
  rasterize(commands, buf);

  assertEquals(buf.getCell(2, 1)?.char, "H");
  assertEquals(buf.getCell(3, 1)?.char, "e");
  assertEquals(buf.getCell(6, 1)?.char, "o"); // last char of "Hello"
  assertEquals(buf.getCell(7, 1)?.char, " "); // past the text
});

Deno.test("rasterize: TextCommand with clip region", () => {
  const buf = new ScreenBuffer(20, 5);
  const clip: BoundingBox = { x: 3, y: 0, width: 5, height: 5 };
  const commands: RenderCommand[] = [
    {
      type: "text",
      x: 0,
      y: 1,
      text: "ABCDEFGHIJ",
      style: DEFAULT_STYLE,
      clip,
    },
  ];
  rasterize(commands, buf);

  // Characters before clip region should not be written
  assertEquals(buf.getCell(0, 1)?.char, " ");
  assertEquals(buf.getCell(1, 1)?.char, " ");
  assertEquals(buf.getCell(2, 1)?.char, " ");

  // Characters inside clip region should be written
  assertEquals(buf.getCell(3, 1)?.char, "D");
  assertEquals(buf.getCell(4, 1)?.char, "E");
  assertEquals(buf.getCell(5, 1)?.char, "F");
  assertEquals(buf.getCell(6, 1)?.char, "G");
  assertEquals(buf.getCell(7, 1)?.char, "H");

  // Characters after clip region should not be written
  assertEquals(buf.getCell(8, 1)?.char, " ");
});

// ── RectCommand ──────────────────────────────────────────────────────────────

Deno.test("rasterize: RectCommand fills rectangular region", () => {
  const buf = new ScreenBuffer(20, 10);
  const commands: RenderCommand[] = [
    {
      type: "rect",
      box: { x: 2, y: 2, width: 4, height: 3 },
      char: "X",
      style: DEFAULT_STYLE,
    },
  ];
  rasterize(commands, buf);

  for (let row = 2; row < 5; row++) {
    for (let col = 2; col < 6; col++) {
      assertEquals(
        buf.getCell(col, row)?.char,
        "X",
        `Cell (${col},${row}) should be X`,
      );
    }
  }
  // Outside the rect should be empty
  assertEquals(buf.getCell(1, 2)?.char, " ");
  assertEquals(buf.getCell(6, 2)?.char, " ");
  assertEquals(buf.getCell(2, 1)?.char, " ");
  assertEquals(buf.getCell(2, 5)?.char, " ");
});

Deno.test("rasterize: RectCommand with clip region", () => {
  const buf = new ScreenBuffer(20, 10);
  const clip: BoundingBox = { x: 3, y: 3, width: 2, height: 1 };
  const commands: RenderCommand[] = [
    {
      type: "rect",
      box: { x: 2, y: 2, width: 4, height: 3 },
      char: "X",
      style: DEFAULT_STYLE,
      clip,
    },
  ];
  rasterize(commands, buf);

  // Only cells within the clip region should be written
  assertEquals(buf.getCell(3, 3)?.char, "X");
  assertEquals(buf.getCell(4, 3)?.char, "X");

  // Cells outside clip should be empty
  assertEquals(buf.getCell(2, 2)?.char, " ");
  assertEquals(buf.getCell(2, 3)?.char, " ");
  assertEquals(buf.getCell(5, 3)?.char, " ");
  assertEquals(buf.getCell(3, 2)?.char, " ");
});

// ── BoxCommand ───────────────────────────────────────────────────────────────

Deno.test("rasterize: BoxCommand draws border", () => {
  const buf = new ScreenBuffer(20, 10);
  const commands: RenderCommand[] = [
    {
      type: "box",
      box: { x: 1, y: 1, width: 6, height: 4 },
      style: DEFAULT_STYLE,
    },
  ];
  rasterize(commands, buf);

  // Corners
  assertEquals(buf.getCell(1, 1)?.char, "┌");
  assertEquals(buf.getCell(6, 1)?.char, "┐");
  assertEquals(buf.getCell(1, 4)?.char, "└");
  assertEquals(buf.getCell(6, 4)?.char, "┘");

  // Top edge
  assertEquals(buf.getCell(3, 1)?.char, "─");

  // Side edge
  assertEquals(buf.getCell(1, 2)?.char, "│");
});

Deno.test("rasterize: BoxCommand with title draws title", () => {
  const buf = new ScreenBuffer(20, 5);
  const commands: RenderCommand[] = [
    {
      type: "box",
      box: { x: 0, y: 0, width: 15, height: 4 },
      style: DEFAULT_STYLE,
      title: "Test",
    },
  ];
  rasterize(commands, buf);

  // Title should be rendered somewhere in the top border
  const topRow = buf.getCell(5, 0)?.char;
  assert(
    topRow !== " " && topRow !== "─",
    "Title should be visible in top border",
  );
});

Deno.test("rasterize: BoxCommand with focused draws bold border", () => {
  const buf = new ScreenBuffer(20, 10);
  const commands: RenderCommand[] = [
    {
      type: "box",
      box: { x: 1, y: 1, width: 6, height: 4 },
      style: DEFAULT_STYLE,
      focused: true,
    },
  ];
  rasterize(commands, buf);

  // Focused border should use cyan bold style
  const cornerStyle = buf.getCell(1, 1)?.style;
  assert(cornerStyle?.bold, "Focused box corner should be bold");
  assertEquals(cornerStyle?.fg, ANSI.CYAN);
});

// ── ScrollBoxCommand ─────────────────────────────────────────────────────────

Deno.test("rasterize: ScrollBoxCommand applies scroll offset", () => {
  const buf = new ScreenBuffer(20, 10);
  const commands: RenderCommand[] = [
    {
      type: "scrollbox",
      box: { x: 0, y: 0, width: 20, height: 5 },
      content: [
        { type: "text", x: 0, y: 0, text: "Line 0" },
        { type: "text", x: 0, y: 1, text: "Line 1" },
        { type: "text", x: 0, y: 2, text: "Line 2" },
        { type: "text", x: 0, y: 3, text: "Line 3" },
      ],
      scrollOffset: 2,
      totalHeight: 4,
    },
  ];
  rasterize(commands, buf);

  // With scrollOffset=2, "Line 2" should be at y=0 (y=2 - scrollOffset=2)
  assertEquals(buf.getCell(0, 0)?.char, "L");
  // "Line 3" should be at y=1
  assertEquals(buf.getCell(0, 1)?.char, "L");
});

Deno.test("rasterize: ScrollBoxCommand applies its own position", () => {
  const buf = new ScreenBuffer(30, 10);
  const commands: RenderCommand[] = [
    {
      type: "scrollbox",
      box: { x: 5, y: 2, width: 10, height: 3 },
      content: [
        { type: "text", x: 0, y: 0, text: "ABC" },
        { type: "text", x: 0, y: 1, text: "DEF" },
      ],
      scrollOffset: 0,
      totalHeight: 2,
    },
  ];
  rasterize(commands, buf);

  // "ABC" should be at (5, 2) — scrollbox position + child position
  assertEquals(buf.getCell(5, 2)?.char, "A");
  assertEquals(buf.getCell(6, 2)?.char, "B");
  assertEquals(buf.getCell(7, 2)?.char, "C");
  // "DEF" should be at (5, 3)
  assertEquals(buf.getCell(5, 3)?.char, "D");
  // Outside the scrollbox should be empty
  assertEquals(buf.getCell(4, 2)?.char, " ");
  assertEquals(buf.getCell(5, 1)?.char, " ");
});

Deno.test("rasterize: ScrollBoxCommand clips children to viewport", () => {
  const buf = new ScreenBuffer(30, 10);
  const commands: RenderCommand[] = [
    {
      type: "scrollbox",
      box: { x: 5, y: 2, width: 5, height: 2 },
      content: [
        // Text that extends beyond the scrollbox width
        { type: "text", x: 0, y: 0, text: "ABCDEFGHIJ" },
        // Text that is below the scrollbox height
        { type: "text", x: 0, y: 1, text: "KLMNO" },
        { type: "text", x: 0, y: 2, text: "PQRST" },
      ],
      scrollOffset: 0,
      totalHeight: 3,
    },
  ];
  rasterize(commands, buf);

  // "ABC" should be visible at (5,2)-(7,2)
  assertEquals(buf.getCell(5, 2)?.char, "A");
  assertEquals(buf.getCell(9, 2)?.char, "E");
  // "F" at x=10 should be clipped (scrollbox width=5, so x 5-9 only)
  assertEquals(buf.getCell(10, 2)?.char, " ");
  // Row at y=4 should be clipped (scrollbox is y=2, height=2, so y 2-3 only)
  assertEquals(buf.getCell(5, 4)?.char, " ");
});

Deno.test("rasterize: ScrollBoxCommand intersects child clip with viewport", () => {
  const buf = new ScreenBuffer(30, 10);
  const commands: RenderCommand[] = [
    {
      type: "scrollbox",
      box: { x: 5, y: 2, width: 5, height: 3 },
      content: [
        // Child has a clip that extends beyond the scrollbox
        {
          type: "text",
          x: 0,
          y: 0,
          text: "ABCDEFGHIJ",
          clip: { x: 0, y: 0, width: 30, height: 10 },
        },
      ],
      scrollOffset: 0,
      totalHeight: 1,
    },
  ];
  rasterize(commands, buf);

  // Text should be clipped to the INTERSECTION of child clip and scrollbox
  // Scrollbox viewport: x=5..9, y=2..4
  assertEquals(buf.getCell(5, 2)?.char, "A");
  assertEquals(buf.getCell(9, 2)?.char, "E");
  // Beyond scrollbox viewport should be empty even though child clip allows it
  assertEquals(buf.getCell(10, 2)?.char, " ");
  assertEquals(buf.getCell(5, 5)?.char, " ");
});

// ── Clipping correctness ─────────────────────────────────────────────────────

Deno.test("rasterize: clipping prevents writes outside clip region", () => {
  const buf = new ScreenBuffer(30, 10);
  const clip: BoundingBox = { x: 5, y: 2, width: 10, height: 3 };
  const commands: RenderCommand[] = [
    {
      type: "text",
      x: 0,
      y: 3,
      text: "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
      style: DEFAULT_STYLE,
      clip,
    },
  ];
  rasterize(commands, buf);

  // Verify no writes outside clip region
  for (let x = 0; x < 30; x++) {
    for (let y = 0; y < 10; y++) {
      const cell = buf.getCell(x, y);
      if (cell && cell.char !== " ") {
        const inClip = x >= clip.x && x < clip.x + clip.width &&
          y >= clip.y && y < clip.y + clip.height;
        assert(inClip, `Non-empty cell at (${x},${y}) is outside clip region`);
      }
    }
  }
});

// ── Idempotence ──────────────────────────────────────────────────────────────

Deno.test("rasterize: produces identical buffer states for identical commands", () => {
  const commands: RenderCommand[] = [
    { type: "text", x: 0, y: 0, text: "Hello", style: fg(ANSI.GREEN) },
    {
      type: "rect",
      box: { x: 0, y: 1, width: 5, height: 1 },
      char: "X",
      style: DEFAULT_STYLE,
    },
    {
      type: "box",
      box: { x: 0, y: 2, width: 10, height: 3 },
      style: DEFAULT_STYLE,
      title: "Test",
    },
  ];

  const buf1 = new ScreenBuffer(20, 10);
  rasterize(commands, buf1);

  const buf2 = new ScreenBuffer(20, 10);
  rasterize(commands, buf2);

  // Compare all cells
  for (let x = 0; x < 20; x++) {
    for (let y = 0; y < 10; y++) {
      const c1 = buf1.getCell(x, y);
      const c2 = buf2.getCell(x, y);
      assertEquals(c1?.char, c2?.char, `Char mismatch at (${x},${y})`);
      assertEquals(c1?.style.fg, c2?.style.fg, `Style mismatch at (${x},${y})`);
    }
  }
});

// ── Empty command array ─────────────────────────────────────────────────────

Deno.test("rasterize: empty command array is a no-op", () => {
  const buf = new ScreenBuffer(20, 10);
  rasterize([], buf);

  // All cells should be empty
  for (let x = 0; x < 20; x++) {
    for (let y = 0; y < 10; y++) {
      assertEquals(buf.getCell(x, y)?.char, " ");
    }
  }
});

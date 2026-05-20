/**
 * Tests for the ScreenBuffer renderer.
 *
 * @module tui/renderer_test
 */

import { assertEquals, assert } from "@std/assert";
import { ScreenBuffer, DEFAULT_STYLE, ANSI, fg, bg, bold, dim, currentTheme } from "./renderer.ts";

Deno.test("ScreenBuffer: setCell and getCell", () => {
  const buf = new ScreenBuffer(10, 5);
  assertEquals(buf.width, 10);
  assertEquals(buf.height, 5);

  const cell = { char: "A", style: fg(ANSI.RED) };
  buf.setCell(3, 2, cell);
  const got = buf.getCell(3, 2);
  assertEquals(got?.char, "A");
  assertEquals(got?.style.fg, ANSI.RED);
});

Deno.test("ScreenBuffer: getCell out of bounds returns undefined", () => {
  const buf = new ScreenBuffer(10, 5);
  assertEquals(buf.getCell(-1, 0), undefined);
  assertEquals(buf.getCell(0, -1), undefined);
  assertEquals(buf.getCell(10, 0), undefined);
  assertEquals(buf.getCell(0, 5), undefined);
});

Deno.test("ScreenBuffer: setCell out of bounds is no-op", () => {
  const buf = new ScreenBuffer(10, 5);
  buf.setCell(-1, 0, { char: "X", style: DEFAULT_STYLE });
  buf.setCell(10, 0, { char: "X", style: DEFAULT_STYLE });
  // No crash = pass
});

Deno.test("ScreenBuffer: write places text with style", () => {
  const buf = new ScreenBuffer(20, 5);
  const style = fg(ANSI.CYAN);
  buf.write(2, 1, "Hello", style);

  assertEquals(buf.getCell(2, 1)?.char, "H");
  assertEquals(buf.getCell(3, 1)?.char, "e");
  assertEquals(buf.getCell(4, 1)?.char, "l");
  assertEquals(buf.getCell(5, 1)?.char, "l");
  assertEquals(buf.getCell(6, 1)?.char, "o");
  assertEquals(buf.getCell(2, 1)?.style.fg, ANSI.CYAN);
});

Deno.test("ScreenBuffer: write clips at right edge", () => {
  const buf = new ScreenBuffer(5, 3);
  buf.write(3, 0, "Hello", DEFAULT_STYLE);
  // Only "He" fits (positions 3, 4)
  assertEquals(buf.getCell(3, 0)?.char, "H");
  assertEquals(buf.getCell(4, 0)?.char, "e");
});

Deno.test("ScreenBuffer: write handles surrogate pairs (emoji)", () => {
  const buf = new ScreenBuffer(10, 3);
  buf.write(0, 0, "🎉Hi", DEFAULT_STYLE);
  // Emoji is a single code point rendered as one cell
  assertEquals(buf.getCell(0, 0)?.char, "🎉");
  assertEquals(buf.getCell(1, 0)?.char, "H");
  assertEquals(buf.getCell(2, 0)?.char, "i");
});

Deno.test("ScreenBuffer: write handles wide characters (CJK)", () => {
  const buf = new ScreenBuffer(10, 3);
  buf.write(0, 0, "A中B", DEFAULT_STYLE);
  // 'A' at pos 0, '中' at pos 1-2 (width 2), 'B' at pos 3
  assertEquals(buf.getCell(0, 0)?.char, "A");
  assertEquals(buf.getCell(1, 0)?.char, "中");
  assertEquals(buf.getCell(2, 0)?.char, ""); // continuation cell
  assertEquals(buf.getCell(3, 0)?.char, "B");
});

Deno.test("ScreenBuffer: clear resets all cells", () => {
  const buf = new ScreenBuffer(10, 5);
  buf.write(0, 0, "Test", fg(ANSI.RED));
  buf.clear();
  assertEquals(buf.getCell(0, 0)?.char, " ");
  assertEquals(buf.getCell(0, 0)?.style.fg, -1);
});

Deno.test("ScreenBuffer: clear does not alias cells (each cell is independent)", () => {
  const buf = new ScreenBuffer(10, 5);
  buf.clear();
  // Mutate one cell — others must remain unchanged
  buf.setCell(0, 0, { char: "X", style: fg(ANSI.RED) });
  assertEquals(buf.getCell(0, 0)?.char, "X");
  assertEquals(buf.getCell(1, 0)?.char, " ");
  assertEquals(buf.getCell(0, 1)?.char, " ");
  // Verify the mutated cell's style is independent
  assertEquals(buf.getCell(0, 0)?.style.fg, ANSI.RED);
  assertEquals(buf.getCell(1, 0)?.style.fg, -1);
});

Deno.test("ScreenBuffer: resize resets dimensions and content", () => {
  const buf = new ScreenBuffer(10, 5);
  buf.write(0, 0, "Test", DEFAULT_STYLE);
  buf.resize(20, 10);
  assertEquals(buf.width, 20);
  assertEquals(buf.height, 10);
  assertEquals(buf.getCell(0, 0)?.char, " ");
});

Deno.test("ScreenBuffer: fillRect fills a region", () => {
  const buf = new ScreenBuffer(10, 5);
  const style = fg(ANSI.GREEN);
  buf.fillRect(2, 1, 3, 2, "█", style);

  assertEquals(buf.getCell(2, 1)?.char, "█");
  assertEquals(buf.getCell(3, 1)?.char, "█");
  assertEquals(buf.getCell(4, 1)?.char, "█");
  assertEquals(buf.getCell(2, 2)?.char, "█");
  assertEquals(buf.getCell(3, 2)?.char, "█");
  assertEquals(buf.getCell(4, 2)?.char, "█");
  assertEquals(buf.getCell(2, 1)?.style.fg, ANSI.GREEN);

  // Outside the rect should be space
  assertEquals(buf.getCell(5, 1)?.char, " ");
  assertEquals(buf.getCell(2, 0)?.char, " ");
});

Deno.test("ScreenBuffer: box draws border", () => {
  const buf = new ScreenBuffer(10, 5);
  buf.box(1, 0, 8, 4, DEFAULT_STYLE, false);

  // Corners
  assertEquals(buf.getCell(1, 0)?.char, "┌");
  assertEquals(buf.getCell(8, 0)?.char, "┐");
  assertEquals(buf.getCell(1, 3)?.char, "└");
  assertEquals(buf.getCell(8, 3)?.char, "┘");

  // Top edge
  assertEquals(buf.getCell(2, 0)?.char, "─");
  assertEquals(buf.getCell(7, 0)?.char, "─");

  // Side edges
  assertEquals(buf.getCell(1, 1)?.char, "│");
  assertEquals(buf.getCell(8, 1)?.char, "│");
});

Deno.test("ScreenBuffer: box with focused uses theme borderFocused color", () => {
  const buf = new ScreenBuffer(10, 5);
  buf.box(1, 0, 8, 4, DEFAULT_STYLE, true);

  const cornerStyle = buf.getCell(1, 0)?.style;
  assertEquals(cornerStyle?.fg, currentTheme.borderFocused);
  assertEquals(cornerStyle?.bold, true);
});

Deno.test("ScreenBuffer: boxTitle places title in top border", () => {
  const buf = new ScreenBuffer(20, 5);
  buf.box(0, 0, 20, 5, DEFAULT_STYLE, false);
  buf.boxTitle(0, 0, 20, "Network", DEFAULT_STYLE);

  // Title should be centered in the top border
  // " Network " = 9 chars, centered in 20 = starts at ~5
  const found = buf.getCell(6, 0);
  assertEquals(found?.char, "N");
  assertEquals(found?.style.bold, true);
});

Deno.test("ScreenBuffer: diff produces output for changed cells", () => {
  const buf = new ScreenBuffer(10, 3);
  buf.write(0, 0, "Hello", fg(ANSI.GREEN));
  const output = buf.diff();
  assert(output.length > 0, "diff should produce output for changed cells");
});

Deno.test("ScreenBuffer: diff returns empty for unchanged frame", () => {
  const buf = new ScreenBuffer(10, 3);
  buf.write(0, 0, "Hello", fg(ANSI.GREEN));
  // First diff
  buf.diff();
  // Second diff with no changes
  const output = buf.diff();
  assertEquals(output, "");
});

Deno.test("ScreenBuffer: fullRedraw produces output", () => {
  const buf = new ScreenBuffer(10, 3);
  buf.write(0, 0, "Test", DEFAULT_STYLE);
  const output = buf.fullRedraw();
  assert(output.length > 0, "fullRedraw should produce output");
});

Deno.test("Style helpers: fg sets foreground color", () => {
  const style = fg(ANSI.RED);
  assertEquals(style.fg, ANSI.RED);
  assertEquals(style.bg, -1);
  assertEquals(style.bold, false);
});

Deno.test("Style helpers: bold sets bold flag", () => {
  const style = bold(fg(ANSI.CYAN));
  assertEquals(style.bold, true);
  assertEquals(style.fg, ANSI.CYAN);
});

Deno.test("Style helpers: dim sets dim flag", () => {
  const style = dim(DEFAULT_STYLE);
  assertEquals(style.dim, true);
});

Deno.test("Style helpers: bg sets background color", () => {
  const style = bg(ANSI.RED);
  assertEquals(style.bg, ANSI.RED);
  assertEquals(style.fg, -1);
});

Deno.test("Encoding: bright background colors use 256-color mode", () => {
  const buf = new ScreenBuffer(10, 3);
  // Bright red background (color 9)
  const style = bg(9);
  buf.setCell(0, 0, { char: "X", style });
  const output = buf.diff();
  // Bright backgrounds should use 48;5;9 (256-color), not 40+1 (which is dim red)
  assert(output.includes("48;5;9"), `Expected 48;5;9 in output, got: ${output}`);
});

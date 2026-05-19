/**
 * Tests for text layout and measuring primitives.
 *
 * @module tui/text_test
 */

import { assert, assertEquals } from "@std/assert";
import {
  getCharWidth,
  measureText,
  measureTextWithAnsi,
  stripAnsi,
  truncate,
  wrapText,
} from "./text.ts";

// ── getCharWidth ─────────────────────────────────────────────────────────────

Deno.test("getCharWidth: ASCII characters are 1 cell", () => {
  assertEquals(getCharWidth("A"), 1);
  assertEquals(getCharWidth("z"), 1);
  assertEquals(getCharWidth("0"), 1);
  assertEquals(getCharWidth(" "), 1);
  assertEquals(getCharWidth("!"), 1);
});

Deno.test("getCharWidth: CJK characters are 2 cells", () => {
  assertEquals(getCharWidth("你"), 2);
  assertEquals(getCharWidth("好"), 2);
  assertEquals(getCharWidth("世"), 2);
  assertEquals(getCharWidth("界"), 2);
});

Deno.test("getCharWidth: fullwidth forms are 2 cells", () => {
  assertEquals(getCharWidth("Ａ"), 2); // U+FF21 Fullwidth Latin Capital Letter A
  assertEquals(getCharWidth("０"), 2); // U+FF10 Fullwidth Digit Zero
});

Deno.test("getCharWidth: control characters are 0 cells", () => {
  assertEquals(getCharWidth("\x00"), 0);
  assertEquals(getCharWidth("\x01"), 0);
  assertEquals(getCharWidth("\x1b"), 0); // ESC
});

Deno.test("getCharWidth: empty string returns 0", () => {
  assertEquals(getCharWidth(""), 0);
});

// ── measureText ──────────────────────────────────────────────────────────────

Deno.test("measureText: ASCII string", () => {
  assertEquals(measureText("Hello"), 5);
  assertEquals(measureText(""), 0);
  assertEquals(measureText("A"), 1);
});

Deno.test("measureText: CJK string", () => {
  assertEquals(measureText("你好"), 4); // 2 chars × 2 cells
  assertEquals(measureText("Hello世界"), 9); // 5 + 4
});

Deno.test("measureText: mixed ASCII and CJK", () => {
  // H(1) + i(1) + 你(2) + 好(2) + B(1) + y(1) + e(1) = 9
  assertEquals(measureText("Hi你好Bye"), 9);
});

// ── measureTextWithAnsi ──────────────────────────────────────────────────────

Deno.test("measureTextWithAnsi: strips ANSI and measures visual width", () => {
  const result = measureTextWithAnsi("\x1b[31mHello\x1b[0m");
  assertEquals(result.visual, 5);
  assert(result.raw > 5, "Raw length should include ANSI codes");
});

Deno.test("measureTextWithAnsi: plain string has equal visual and raw", () => {
  const result = measureTextWithAnsi("Hello");
  assertEquals(result.visual, 5);
  assertEquals(result.raw, 5);
});

// ── stripAnsi ────────────────────────────────────────────────────────────────

Deno.test("stripAnsi: removes CSI sequences", () => {
  assertEquals(stripAnsi("\x1b[31mHello\x1b[0m"), "Hello");
  assertEquals(stripAnsi("\x1b[1;32mBold Green\x1b[0m"), "Bold Green");
});

Deno.test("stripAnsi: plain string unchanged", () => {
  assertEquals(stripAnsi("Hello World"), "Hello World");
});

Deno.test("stripAnsi: empty string", () => {
  assertEquals(stripAnsi(""), "");
});

Deno.test("stripAnsi: multiple sequences", () => {
  assertEquals(stripAnsi("\x1b[1m\x1b[31mRed Bold\x1b[0m"), "Red Bold");
});

// ── wrapText ─────────────────────────────────────────────────────────────────

Deno.test("wrapText: word mode wraps at word boundaries", () => {
  const lines = wrapText("Hello world foo bar", {
    maxWidth: 10,
    wrapMode: "word",
  });
  for (const line of lines) {
    assert(
      measureText(line) <= 10,
      `Line "${line}" exceeds maxWidth (width=${measureText(line)})`,
    );
  }
  // Content preservation: joining with space should reconstruct original
  assertEquals(lines.join(" "), "Hello world foo bar");
});

Deno.test("wrapText: character-wraps long words", () => {
  const lines = wrapText("Supercalifragilistic", {
    maxWidth: 5,
    wrapMode: "word",
  });
  for (const line of lines) {
    assert(measureText(line) <= 5, `Line "${line}" exceeds maxWidth`);
  }
});

Deno.test("wrapText: char mode wraps at character boundaries", () => {
  const lines = wrapText("HelloWorld", { maxWidth: 3, wrapMode: "char" });
  assertEquals(lines, ["Hel", "loW", "orl", "d"]);
});

Deno.test("wrapText: none mode returns single line", () => {
  const lines = wrapText("Hello world", { maxWidth: 5, wrapMode: "none" });
  assertEquals(lines, ["Hello world"]);
});

Deno.test("wrapText: empty string returns empty array", () => {
  const lines = wrapText("", { maxWidth: 10, wrapMode: "word" });
  assertEquals(lines, []);
});

Deno.test("wrapText: CJK characters wrap correctly", () => {
  const lines = wrapText("你好世界", { maxWidth: 4, wrapMode: "char" });
  // 你好 = 4 cells, 世界 = 4 cells
  assertEquals(lines, ["你好", "世界"]);
});

Deno.test("wrapText: preserves content (word mode)", () => {
  const text = "This is a test of the wrapping algorithm with multiple words";
  const lines = wrapText(text, { maxWidth: 15, wrapMode: "word" });
  assertEquals(lines.join(" "), text);
});

// ── truncate ─────────────────────────────────────────────────────────────────

Deno.test("truncate: short string unchanged", () => {
  assertEquals(truncate("Hi", 10), "Hi");
  assertEquals(truncate("Hello", 5), "Hello");
});

Deno.test("truncate: truncates with ellipsis", () => {
  const result = truncate("Hello, world!", 8);
  assertEquals(measureText(result), 8);
  assert(result.endsWith("…"), "Should end with ellipsis");
});

Deno.test("truncate: custom ellipsis", () => {
  const result = truncate("Hello, world!", 10, "...");
  assert(result.endsWith("..."), "Should end with custom ellipsis");
  assert(measureText(result) <= 10, "Should fit within maxWidth");
});

Deno.test("truncate: CJK text truncation", () => {
  const result = truncate("你好世界", 5);
  // 你好 = 4 cells, + … = 1 cell = 5 total
  assertEquals(measureText(result), 5);
  assert(result.endsWith("…"));
});

Deno.test("truncate: very small maxWidth", () => {
  const result = truncate("Hello", 1);
  assertEquals(measureText(result), 1);
});

Deno.test("truncate: exact width returns unchanged", () => {
  assertEquals(truncate("Hello", 5), "Hello");
});

Deno.test("truncate: empty string", () => {
  assertEquals(truncate("", 5), "");
});

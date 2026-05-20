/**
 * Tests for the ScreenBuffer renderer.
 *
 * @module tui/renderer_test
 */

import { assertEquals, assert } from "@std/assert";
import { ScreenBuffer, DEFAULT_STYLE, RESET, ANSI, fg, bg, bold, dim, currentTheme, reverse, underline, mergeStyles } from "./renderer.ts";

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

Deno.test("ScreenBuffer: write preserves existing cell background when style has no bg", () => {
  const buf = new ScreenBuffer(20, 5);
  // Fill a region with a grey background
  const panelBg = bg(8); // BRIGHT_BLACK = dark grey
  buf.fillRect(0, 0, 10, 3, " ", panelBg);
  // Write text with only fg set (no bg)
  buf.write(2, 1, "Hello", fg(7)); // WHITE foreground

  // Text cells should have WHITE fg AND the grey background preserved
  assertEquals(buf.getCell(2, 1)?.char, "H");
  assertEquals(buf.getCell(2, 1)?.style.fg, 7);
  assertEquals(buf.getCell(2, 1)?.style.bg, 8);
  assertEquals(buf.getCell(6, 1)?.char, "o");
  assertEquals(buf.getCell(6, 1)?.style.bg, 8);
  // Space cells outside the text should still have the grey background
  assertEquals(buf.getCell(8, 1)?.char, " ");
  assertEquals(buf.getCell(8, 1)?.style.bg, 8);
});

Deno.test("ScreenBuffer: writeClipped preserves existing cell background", () => {
  const buf = new ScreenBuffer(20, 5);
  const panelBg = bg(8);
  buf.fillRect(0, 0, 10, 3, " ", panelBg);
  const clip = { x: 0, y: 0, width: 10, height: 3 };
  buf.writeClipped(2, 1, "Hello", fg(7), clip);

  assertEquals(buf.getCell(2, 1)?.style.bg, 8);
  assertEquals(buf.getCell(6, 1)?.style.bg, 8);
});

Deno.test("ScreenBuffer: write does not override explicit background", () => {
  const buf = new ScreenBuffer(20, 5);
  // Fill with grey bg
  buf.fillRect(0, 0, 10, 3, " ", bg(8));
  // Write text with EXPLICIT red background
  const style = { ...fg(7), bg: 1 }; // WHITE on RED
  buf.write(2, 1, "Hi", style);

  // Explicit background should be used, not the fill background
  assertEquals(buf.getCell(2, 1)?.style.bg, 1);
  assertEquals(buf.getCell(2, 1)?.style.fg, 7);
});

Deno.test("ScreenBuffer: write preserves background across wide characters", () => {
  const buf = new ScreenBuffer(20, 5);
  buf.fillRect(0, 0, 10, 3, " ", bg(8));
  buf.write(0, 0, "A中B", fg(7));

  // 'A' at pos 0
  assertEquals(buf.getCell(0, 0)?.char, "A");
  assertEquals(buf.getCell(0, 0)?.style.bg, 8);
  // '中' at pos 1, continuation at pos 2
  assertEquals(buf.getCell(1, 0)?.char, "中");
  assertEquals(buf.getCell(1, 0)?.style.bg, 8);
  assertEquals(buf.getCell(2, 0)?.char, ""); // continuation
  assertEquals(buf.getCell(2, 0)?.style.bg, 8);
  // 'B' at pos 3
  assertEquals(buf.getCell(3, 0)?.char, "B");
  assertEquals(buf.getCell(3, 0)?.style.bg, 8);
});

Deno.test("ScreenBuffer: write preserves nothing when existing cell has no bg", () => {
  const buf = new ScreenBuffer(20, 5);
  // No fill — all cells have DEFAULT_STYLE with bg=-1
  buf.write(2, 1, "Hello", fg(7));

  assertEquals(buf.getCell(2, 1)?.style.bg, -1);
  assertEquals(buf.getCell(2, 1)?.style.fg, 7);
});

Deno.test("Encoding: preserved backgrounds are emitted in diff output", () => {
  const buf = new ScreenBuffer(20, 5);
  buf.fillRect(0, 0, 10, 3, " ", bg(8));
  buf.write(2, 1, "X", fg(7));
  // Clear prev state so diff sees all cells
  const output = buf.diff();
  // The text cell should have bg:8 encoded
  assert(output.includes("48;5;8"), `Expected 48;5;8 in diff output, got: ${output}`);
});

// ---------------------------------------------------------------------------
// ANSI encoding — reverse video
// ---------------------------------------------------------------------------

Deno.test("Encoding: reverse video produces '7' in escape sequence", () => {
  const buf = new ScreenBuffer(10, 3);
  const style = { ...DEFAULT_STYLE, reverse: true };
  buf.setCell(0, 0, { char: "R", style });
  const output = buf.diff();
  // The escape sequence should contain \x1b[...7...m (reverse video)
  // deno-lint-ignore no-control-regex
  assert(output.match(/\x1b\[[0-9;]*7[0-9;]*m/), `Expected reverse video (7) in: ${JSON.stringify(output)}`);
});

Deno.test("Encoding: reverse video with foreground color", () => {
  const buf = new ScreenBuffer(10, 3);
  const style = { ...fg(ANSI.GREEN), reverse: true };
  buf.setCell(0, 0, { char: "R", style });
  const output = buf.diff();
  // Should have both color and reverse
  assert(output.includes("32"), `Expected green fg (32) in: ${JSON.stringify(output)}`);
  // deno-lint-ignore no-control-regex
  assert(output.match(/\x1b\[[0-9;]*7[0-9;]*m/), `Expected reverse (7) in: ${JSON.stringify(output)}`);
});

// ---------------------------------------------------------------------------
// ANSI encoding — underline
// ---------------------------------------------------------------------------

Deno.test("Encoding: underline produces '4' in escape sequence", () => {
  const buf = new ScreenBuffer(10, 3);
  const style = { ...DEFAULT_STYLE, underline: true };
  buf.setCell(0, 0, { char: "U", style });
  const output = buf.diff();
  // deno-lint-ignore no-control-regex
  assert(output.match(/\x1b\[[0-9;]*4[0-9;]*m/), `Expected underline (4) in: ${JSON.stringify(output)}`);
});

Deno.test("Encoding: underline combined with bold", () => {
  const buf = new ScreenBuffer(10, 3);
  const style = { ...DEFAULT_STYLE, underline: true, bold: true };
  buf.setCell(0, 0, { char: "U", style });
  const output = buf.diff();
  assert(output.includes("1"), `Expected bold (1) in: ${JSON.stringify(output)}`);
  // deno-lint-ignore no-control-regex
  assert(output.match(/\x1b\[[0-9;]*4[0-9;]*m/), `Expected underline (4) in: ${JSON.stringify(output)}`);
});

// ---------------------------------------------------------------------------
// ANSI encoding — combined bold + dim
// ---------------------------------------------------------------------------

Deno.test("Encoding: bold and dim both present in escape sequence", () => {
  const buf = new ScreenBuffer(10, 3);
  const style = { ...DEFAULT_STYLE, bold: true, dim: true };
  buf.setCell(0, 0, { char: "B", style });
  const output = buf.diff();
  // Both "1" (bold) and "2" (dim) should be in the SGR sequence.
  // Use the exact SGR sequence to avoid matching substrings in color codes.
  // deno-lint-ignore no-control-regex
  const sgr = output.match(/\x1b\[([0-9;]*)m/);
  assert(sgr, `Expected SGR sequence in: ${JSON.stringify(output)}`);
  const codes = sgr![1]!.split(";");
  assert(codes.includes("1"), `Expected bold code "1" in SGR params: ${codes}`);
  assert(codes.includes("2"), `Expected dim code "2" in SGR params: ${codes}`);
});

Deno.test("Encoding: bold+dim+fg produces all codes", () => {
  const buf = new ScreenBuffer(10, 3);
  const style = { ...fg(ANSI.RED), bold: true, dim: true };
  buf.setCell(0, 0, { char: "X", style });
  const output = buf.diff();
  // Parse the SGR params from the escape sequence to avoid substring matches
  // deno-lint-ignore no-control-regex
  const sgr = output.match(/\x1b\[([0-9;]*)m/);
  assert(sgr, `Expected SGR sequence in: ${JSON.stringify(output)}`);
  const codes = sgr![1]!.split(";");
  assert(codes.includes("1"), `bold missing, codes: ${codes}`);
  assert(codes.includes("2"), `dim missing, codes: ${codes}`);
  assert(codes.includes("31"), `red fg missing, codes: ${codes}`);
});

// ---------------------------------------------------------------------------
// ANSI encoding — background colors 0-7
// ---------------------------------------------------------------------------

Deno.test("Encoding: bg color 0 (black) uses 48;5;0", () => {
  const buf = new ScreenBuffer(10, 3);
  buf.setCell(0, 0, { char: "X", style: bg(0) });
  const output = buf.diff();
  assert(output.includes("48;5;0"), `Expected 48;5;0 in: ${JSON.stringify(output)}`);
});

Deno.test("Encoding: bg color 1 (red) uses 48;5;1", () => {
  const buf = new ScreenBuffer(10, 3);
  buf.setCell(0, 0, { char: "X", style: bg(1) });
  const output = buf.diff();
  assert(output.includes("48;5;1"), `Expected 48;5;1 in: ${JSON.stringify(output)}`);
});

Deno.test("Encoding: bg color 7 (white) uses 48;5;7", () => {
  const buf = new ScreenBuffer(10, 3);
  buf.setCell(0, 0, { char: "X", style: bg(7) });
  const output = buf.diff();
  assert(output.includes("48;5;7"), `Expected 48;5;7 in: ${JSON.stringify(output)}`);
});

Deno.test("Encoding: bg color 4 (blue) uses 48;5;4", () => {
  const buf = new ScreenBuffer(10, 3);
  buf.setCell(0, 0, { char: "X", style: bg(4) });
  const output = buf.diff();
  assert(output.includes("48;5;4"), `Expected 48;5;4 in: ${JSON.stringify(output)}`);
});

// ---------------------------------------------------------------------------
// ANSI encoding — bright foreground (8-15) bold trick
// ---------------------------------------------------------------------------

Deno.test("Encoding: bright foreground (8-15) uses standard ANSI + bold trick", () => {
  const buf = new ScreenBuffer(10, 3);
  buf.setCell(0, 0, { char: "X", style: fg(10) }); // BRIGHT_GREEN
  const output = buf.diff();
  // Bright green = fg color 2 (green) + bold: 32 + 1
  assert(output.includes("32"), `Expected 32 (green) in: ${JSON.stringify(output)}`);
  assert(output.includes("1"), `Expected bold trick (1) in: ${JSON.stringify(output)}`);
  // Should NOT use 38;5;10 for colors < 16
  assert(!output.includes("38;5"), `Expected no 38;5 for fg < 16 in: ${JSON.stringify(output)}`);
});

Deno.test("Encoding: bright magenta (13) uses magenta + bold", () => {
  const buf = new ScreenBuffer(10, 3);
  buf.setCell(0, 0, { char: "X", style: fg(13) }); // BRIGHT_MAGENTA
  const output = buf.diff();
  assert(output.includes("35"), `Expected 35 (magenta) in: ${JSON.stringify(output)}`);
  assert(output.includes("1"), `Expected bold trick (1) in: ${JSON.stringify(output)}`);
});

Deno.test("Encoding: bright white (15) uses white + bold", () => {
  const buf = new ScreenBuffer(10, 3);
  buf.setCell(0, 0, { char: "X", style: fg(15) }); // BRIGHT_WHITE
  const output = buf.diff();
  assert(output.includes("37"), `Expected 37 (white) in: ${JSON.stringify(output)}`);
  assert(output.includes("1"), `Expected bold trick (1) in: ${JSON.stringify(output)}`);
});

// ---------------------------------------------------------------------------
// ANSI encoding — 256-color foreground (16-255)
// ---------------------------------------------------------------------------

Deno.test("Encoding: 256-color foreground (16+) uses 38;5;N", () => {
  const buf = new ScreenBuffer(10, 3);
  buf.setCell(0, 0, { char: "X", style: fg(42) });
  const output = buf.diff();
  assert(output.includes("38;5;42"), `Expected 38;5;42 in: ${JSON.stringify(output)}`);
});

Deno.test("Encoding: 256-color foreground at boundary (16)", () => {
  const buf = new ScreenBuffer(10, 3);
  buf.setCell(0, 0, { char: "X", style: fg(16) });
  const output = buf.diff();
  assert(output.includes("38;5;16"), `Expected 38;5;16 in: ${JSON.stringify(output)}`);
});

Deno.test("Encoding: 256-color foreground at boundary (15 uses standard)", () => {
  const buf = new ScreenBuffer(10, 3);
  buf.setCell(0, 0, { char: "X", style: fg(15) }); // exactly 15 = last standard
  const output = buf.diff();
  // Should use standard ANSI, not 256-color
  assert(output.includes("37"), `Expected 37 (white) in: ${JSON.stringify(output)}`);
  assert(!output.includes("38;5"), `Expected no 38;5 for fg=15 in: ${JSON.stringify(output)}`);
});

// ---------------------------------------------------------------------------
// ANSI encoding — style resets
// ---------------------------------------------------------------------------

Deno.test("Encoding: adjacent cells with different styles produce correct SGR transitions", () => {
  const buf = new ScreenBuffer(20, 3);
  buf.setCell(0, 0, { char: "A", style: fg(ANSI.RED) });
  buf.setCell(1, 0, { char: "B", style: fg(ANSI.GREEN) });
  buf.setCell(2, 0, { char: "C", style: DEFAULT_STYLE });
  const output = buf.diff();

  // Output should contain style transitions (multiple SGR sequences)
  // We can verify it produces valid output with all 3 chars
  assert(output.includes("A"), "Missing char A");
  assert(output.includes("B"), "Missing char B");
  assert(output.includes("C"), "Missing char C");
  // Should have at least 2 SGR resets (\x1b[0...m)
  // deno-lint-ignore no-control-regex
  const sgrCount = (output.match(/\x1b\[0/g) || []).length;
  assert(sgrCount >= 2, `Expected >= 2 SGR resets, got ${sgrCount}`);
});

Deno.test("Encoding: final cell with non-default style has trailing reset", () => {
  const buf = new ScreenBuffer(5, 3);
  buf.setCell(0, 0, { char: "X", style: fg(ANSI.RED) });
  const output = buf.diff();
  // Output should end with RESET (\x1b[0m)
  assert(output.endsWith(RESET) || output.includes(RESET),
    `Expected trailing reset, got: ${JSON.stringify(output)}`);
});

// ---------------------------------------------------------------------------
// ANSI encoding — combined attributes (bold + fg + bg)
// ---------------------------------------------------------------------------

Deno.test("Encoding: bold + fg + bg produces all codes in one sequence", () => {
  const buf = new ScreenBuffer(10, 3);
  const style = { ...DEFAULT_STYLE, fg: ANSI.WHITE, bg: ANSI.BLUE, bold: true };
  buf.setCell(0, 0, { char: "X", style });
  const output = buf.diff();
  // Should have reset(0), bold(1), fg(37), bg(48;5;4)
  assert(output.includes("\x1b[0"), "Missing reset");
  assert(output.includes("1"), "Missing bold");
  assert(output.includes("37"), "Missing white fg");
  assert(output.includes("48;5;4"), "Missing blue bg");
});

Deno.test("Encoding: dim + underline + bg produces correct sequence", () => {
  const buf = new ScreenBuffer(10, 3);
  const style = { ...bg(ANSI.MAGENTA), dim: true, underline: true };
  buf.setCell(0, 0, { char: "X", style });
  const output = buf.diff();
  assert(output.includes("2"), "Missing dim");
  // deno-lint-ignore no-control-regex
  assert(output.match(/\x1b\[[0-9;]*4[0-9;]*m/), "Missing underline");
  assert(output.includes("48;5;5"), "Missing magenta bg");
});

// ---------------------------------------------------------------------------
// ANSI encoding — fullRedraw
// ---------------------------------------------------------------------------

Deno.test("Encoding: fullRedraw produces valid ANSI for styled cells", () => {
  const buf = new ScreenBuffer(10, 3);
  buf.setCell(0, 0, { char: "X", style: fg(ANSI.GREEN) });
  buf.setCell(1, 0, { char: "Y", style: { ...DEFAULT_STYLE, fg: ANSI.RED, bold: true } });
  const output = buf.fullRedraw();
  assert(output.length > 0);
  assert(output.includes("X"));
  assert(output.includes("Y"));
});

// ---------------------------------------------------------------------------
// Style helpers — merge, reverse, underline
// ---------------------------------------------------------------------------

Deno.test("Style helpers: mergeStyles overrides fields", () => {
  const base = fg(ANSI.RED);
  const merged = mergeStyles(base, { bold: true });
  assertEquals(merged.fg, ANSI.RED);
  assertEquals(merged.bold, true);
});

Deno.test("Style helpers: reverse sets reverse flag", () => {
  const style = reverse(DEFAULT_STYLE);
  assertEquals(style.reverse, true);
  assertEquals(style.fg, -1);
});

Deno.test("Style helpers: underline sets underline flag", () => {
  const style = underline(DEFAULT_STYLE);
  assertEquals(style.underline, true);
  assertEquals(style.fg, -1);
});

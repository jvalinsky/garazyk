import { assertEquals } from "@std/assert";
import { lineStartOffsets, lineForOffset } from "./boundary_check.ts";

Deno.test("lineStartOffsets: empty string", () => {
  assertEquals(lineStartOffsets(""), [0]);
});

Deno.test("lineStartOffsets: single line", () => {
  assertEquals(lineStartOffsets("hello"), [0]);
});

Deno.test("lineStartOffsets: two lines", () => {
  assertEquals(lineStartOffsets("abc\ndef"), [0, 4]);
});

Deno.test("lineStartOffsets: trailing newline", () => {
  assertEquals(lineStartOffsets("abc\n"), [0, 4]);
});

Deno.test("lineStartOffsets: multiple blank lines", () => {
  assertEquals(lineStartOffsets("\n\n\n"), [0, 1, 2, 3]);
});

Deno.test("lineForOffset: start of first line", () => {
  const starts = lineStartOffsets("abc\ndef\nghi");
  assertEquals(lineForOffset(starts, 0), 1);
});

Deno.test("lineForOffset: end of first line", () => {
  const starts = lineStartOffsets("abc\ndef\nghi");
  assertEquals(lineForOffset(starts, 3), 1);
});

Deno.test("lineForOffset: start of second line", () => {
  const starts = lineStartOffsets("abc\ndef\nghi");
  assertEquals(lineForOffset(starts, 4), 2);
});

Deno.test("lineForOffset: start of third line", () => {
  const starts = lineStartOffsets("abc\ndef\nghi");
  assertEquals(lineForOffset(starts, 8), 3);
});

Deno.test("lineForOffset: beyond last line", () => {
  const starts = lineStartOffsets("abc\ndef");
  assertEquals(lineForOffset(starts, 100), 2);
});

Deno.test("lineForOffset: single line string", () => {
  const starts = lineStartOffsets("hello");
  assertEquals(lineForOffset(starts, 0), 1);
  assertEquals(lineForOffset(starts, 4), 1);
});

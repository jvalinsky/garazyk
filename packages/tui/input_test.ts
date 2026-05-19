/**
 * Tests for the key input parser.
 *
 * @module tui/input_test
 */

import { assertEquals } from "jsr:@std/assert";
import { parseKey, Keys, isKey, isCtrl, isQuit, type Key } from "./input.ts";

/** Parse a key from a byte array (wraps the internal parseKey). */
function parse(bytes: number[]): Key | null {
  const result = parseKey(bytes);
  if (result === null) return null;
  return result[0];
}

Deno.test("Key parser: Ctrl+C (byte 3)", () => {
  const key = parse([3])!;
  assertEquals(key.key, "c");
  assertEquals(key.ctrl, true);
  assertEquals(key.alt, false);
  assertEquals(key.shift, false);
});

Deno.test("Key parser: Ctrl+A (byte 1)", () => {
  const key = parse([1])!;
  assertEquals(key.key, "a");
  assertEquals(key.ctrl, true);
});

Deno.test("Key parser: Tab (byte 9)", () => {
  const key = parse([9])!;
  assertEquals(key.key, Keys.TAB);
  assertEquals(key.ctrl, false);
});

Deno.test("Key parser: Enter (byte 13)", () => {
  const key = parse([13])!;
  assertEquals(key.key, Keys.ENTER);
});

Deno.test("Key parser: Escape (byte 27)", () => {
  const key = parse([27])!;
  assertEquals(key.key, Keys.ESCAPE);
});

Deno.test("Key parser: Backspace (byte 127)", () => {
  const key = parse([127])!;
  assertEquals(key.key, Keys.BACKSPACE);
});

Deno.test("Key parser: lowercase letter", () => {
  const key = parse([97])!; // 'a'
  assertEquals(key.key, "a");
  assertEquals(key.shift, false);
  assertEquals(key.ctrl, false);
});

Deno.test("Key parser: uppercase letter", () => {
  const key = parse([65])!; // 'A'
  assertEquals(key.key, "a");
  assertEquals(key.shift, true);
});

Deno.test("Key parser: Space (byte 32)", () => {
  const key = parse([32])!;
  assertEquals(key.key, " ");
  assertEquals(key.shift, false);
});

Deno.test("Key parser: Arrow Up (ESC [ A)", () => {
  const key = parse([27, 91, 65])!;
  assertEquals(key.key, Keys.UP);
  assertEquals(key.ctrl, false);
  assertEquals(key.alt, false);
});

Deno.test("Key parser: Arrow Down (ESC [ B)", () => {
  const key = parse([27, 91, 66])!;
  assertEquals(key.key, Keys.DOWN);
});

Deno.test("Key parser: Arrow Right (ESC [ C)", () => {
  const key = parse([27, 91, 67])!;
  assertEquals(key.key, Keys.RIGHT);
});

Deno.test("Key parser: Arrow Left (ESC [ D)", () => {
  const key = parse([27, 91, 68])!;
  assertEquals(key.key, Keys.LEFT);
});

Deno.test("Key parser: Home (ESC [ H)", () => {
  const key = parse([27, 91, 72])!;
  assertEquals(key.key, Keys.HOME);
});

Deno.test("Key parser: End (ESC [ F)", () => {
  const key = parse([27, 91, 70])!;
  assertEquals(key.key, Keys.END);
});

Deno.test("Key parser: Delete (ESC [ 3 ~)", () => {
  const key = parse([27, 91, 51, 126])!;
  assertEquals(key.key, Keys.DELETE);
});

Deno.test("Key parser: Page Up (ESC [ 5 ~)", () => {
  const key = parse([27, 91, 53, 126])!;
  assertEquals(key.key, Keys.PAGE_UP);
});

Deno.test("Key parser: Page Down (ESC [ 6 ~)", () => {
  const key = parse([27, 91, 54, 126])!;
  assertEquals(key.key, Keys.PAGE_DOWN);
});

Deno.test("Key parser: Ctrl+Up (ESC [ 1 ; 5 A)", () => {
  const key = parse([27, 91, 49, 59, 53, 65])!;
  assertEquals(key.key, Keys.UP);
  assertEquals(key.ctrl, true);
  assertEquals(key.alt, false);
  assertEquals(key.shift, false);
});

Deno.test("Key parser: Shift+Up (ESC [ 1 ; 2 A)", () => {
  const key = parse([27, 91, 49, 59, 50, 65])!;
  assertEquals(key.key, Keys.UP);
  assertEquals(key.shift, true);
  assertEquals(key.ctrl, false);
});

Deno.test("Key parser: Alt+key (ESC + letter)", () => {
  const key = parse([27, 97])!; // ESC + 'a'
  assertEquals(key.key, "a");
  assertEquals(key.alt, true);
});

Deno.test("Key parser: F1 via SS3 (ESC O P)", () => {
  const key = parse([27, 79, 80])!;
  assertEquals(key.key, Keys.F1);
});

Deno.test("Key parser: F2 via SS3 (ESC O Q)", () => {
  const key = parse([27, 79, 81])!;
  assertEquals(key.key, Keys.F2);
});

Deno.test("isKey: matches simple key", () => {
  const key: Key = { key: "q", ctrl: false, alt: false, shift: false };
  assertEquals(isKey(key, "q"), true);
  assertEquals(isKey(key, "a"), false);
});

Deno.test("isCtrl: matches Ctrl+key", () => {
  const key: Key = { key: "c", ctrl: true, alt: false, shift: false };
  assertEquals(isCtrl(key, "c"), true);
  assertEquals(isCtrl(key, "a"), false);
});

Deno.test("isQuit: matches q or Ctrl+C", () => {
  const q: Key = { key: "q", ctrl: false, alt: false, shift: false };
  const ctrlC: Key = { key: "c", ctrl: true, alt: false, shift: false };
  const other: Key = { key: "a", ctrl: false, alt: false, shift: false };

  assertEquals(isQuit(q), true);
  assertEquals(isQuit(ctrlC), true);
  assertEquals(isQuit(other), false);
});

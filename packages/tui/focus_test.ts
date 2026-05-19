/**
 * Tests for the FocusRing.
 *
 * @module tui/focus_test
 */

import { assertEquals, assert } from "@std/assert";
import { FocusRing } from "./focus.ts";

Deno.test("FocusRing: starts on first panel", () => {
  const ring = new FocusRing();
  assertEquals(ring.current, "network");
  assertEquals(ring.currentIndex, 0);
});

Deno.test("FocusRing: next cycles forward", () => {
  const ring = new FocusRing();
  assertEquals(ring.next(), "scenarios");
  assertEquals(ring.next(), "run");
  assertEquals(ring.next(), "history");
  assertEquals(ring.next(), "network"); // wraps around
});

Deno.test("FocusRing: prev cycles backward", () => {
  const ring = new FocusRing();
  assertEquals(ring.prev(), "history"); // wraps to last
  assertEquals(ring.prev(), "run");
  assertEquals(ring.prev(), "scenarios");
  assertEquals(ring.prev(), "network");
});

Deno.test("FocusRing: jump to specific index", () => {
  const ring = new FocusRing();
  assert(ring.jump(2)); // changed
  assertEquals(ring.current, "run");

  assert(!ring.jump(2)); // same index, no change
  assertEquals(ring.current, "run");

  assert(!ring.jump(-1)); // invalid
  assert(!ring.jump(4)); // invalid
});

Deno.test("FocusRing: jumpTo by ID", () => {
  const ring = new FocusRing();
  assert(ring.jumpTo("history"));
  assertEquals(ring.current, "history");

  assert(!ring.jumpTo("history")); // same, no change
  assert(!ring.jumpTo("nonexistent" as never)); // invalid
});

Deno.test("FocusRing: isFocused checks current panel", () => {
  const ring = new FocusRing();
  assert(ring.isFocused("network"));
  assert(!ring.isFocused("scenarios"));

  ring.next();
  assert(!ring.isFocused("network"));
  assert(ring.isFocused("scenarios"));
});

Deno.test("FocusRing: reset goes back to first", () => {
  const ring = new FocusRing();
  ring.jump(3);
  assertEquals(ring.current, "history");
  ring.reset();
  assertEquals(ring.current, "network");
});

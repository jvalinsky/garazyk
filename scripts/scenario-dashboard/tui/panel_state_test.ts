/**
 * Tests for panel state and clipped writing.
 *
 * @module tui/panel_state_test
 */

import { assertEquals, assert } from "jsr:@std/assert";
import { ScreenBuffer, DEFAULT_STYLE, fg, ANSI } from "@garazyk/tui";
import {
  createPanelState,
  createPanelStates,
  moveCursorUp,
  moveCursorDown,
  clampPanelState,
} from "./panel_state.ts";
import { PANEL_IDS } from "@garazyk/tui";

// ---------------------------------------------------------------------------
// PanelState tests
// ---------------------------------------------------------------------------

Deno.test("createPanelState: defaults", () => {
  const state = createPanelState();
  assertEquals(state.cursor, 0);
  assertEquals(state.scrollOffset, 0);
  assertEquals(state.itemCount, 0);
});

Deno.test("createPanelState: with itemCount", () => {
  const state = createPanelState(10);
  assertEquals(state.itemCount, 10);
});

Deno.test("createPanelStates: all four panels", () => {
  const states = createPanelStates();
  for (const id of PANEL_IDS) {
    assert(id in states, `Panel ${id} should exist`);
    assertEquals(states[id].cursor, 0);
    assertEquals(states[id].scrollOffset, 0);
  }
});

Deno.test("moveCursorDown: moves cursor down", () => {
  const state = createPanelState(10);
  const next = moveCursorDown(state, 5);
  assertEquals(next.cursor, 1);
  assertEquals(next.scrollOffset, 0);
});

Deno.test("moveCursorDown: scrolls when cursor reaches bottom of visible area", () => {
  const state = { ...createPanelState(10), cursor: 4 };
  const next = moveCursorDown(state, 5);
  assertEquals(next.cursor, 5);
  assertEquals(next.scrollOffset, 1);
});

Deno.test("moveCursorDown: clamps at last item", () => {
  const state = { ...createPanelState(5), cursor: 4 };
  const next = moveCursorDown(state, 5);
  assertEquals(next.cursor, 4); // stays at last item
});

Deno.test("moveCursorUp: moves cursor up", () => {
  const state = { ...createPanelState(10), cursor: 3 };
  const next = moveCursorUp(state, 5);
  assertEquals(next.cursor, 2);
  assertEquals(next.scrollOffset, 0);
});

Deno.test("moveCursorUp: scrolls when cursor goes above visible area", () => {
  const state = { ...createPanelState(10), cursor: 3, scrollOffset: 3 };
  const next = moveCursorUp(state, 5);
  assertEquals(next.cursor, 2);
  assertEquals(next.scrollOffset, 2);
});

Deno.test("moveCursorUp: clamps at first item", () => {
  const state = createPanelState(10);
  const next = moveCursorUp(state, 5);
  assertEquals(next.cursor, 0);
});

Deno.test("clampPanelState: clamps cursor to itemCount", () => {
  const state = { cursor: 10, scrollOffset: 0, itemCount: 20 };
  const clamped = clampPanelState(state, 5, 10);
  assertEquals(clamped.cursor, 4);
  assertEquals(clamped.itemCount, 5);
});

Deno.test("clampPanelState: clamps scrollOffset", () => {
  const state = { cursor: 0, scrollOffset: 50, itemCount: 100 };
  const clamped = clampPanelState(state, 100, 10);
  // scrollOffset 50 is within valid range (0..90), so it stays
  assertEquals(clamped.scrollOffset, 50);
});

Deno.test("clampPanelState: clamps scrollOffset when too large", () => {
  const state = { cursor: 0, scrollOffset: 95, itemCount: 100 };
  const clamped = clampPanelState(state, 100, 10);
  assertEquals(clamped.scrollOffset, 90); // max offset = 100 - 10
});

// ---------------------------------------------------------------------------
// writeClipped tests
// ---------------------------------------------------------------------------

Deno.test("writeClipped: writes text within clip region", () => {
  const buf = new ScreenBuffer(20, 10);
  const clip = { x: 5, y: 2, width: 10, height: 3 };
  buf.writeClipped(5, 2, "Hello", fg(ANSI.GREEN), clip);
  assertEquals(buf.getCell(5, 2)?.char, "H");
  assertEquals(buf.getCell(6, 2)?.char, "e");
  assertEquals(buf.getCell(9, 2)?.char, "o");
});

Deno.test("writeClipped: drops text outside clip region (y)", () => {
  const buf = new ScreenBuffer(20, 10);
  const clip = { x: 0, y: 2, width: 20, height: 3 };
  buf.writeClipped(0, 0, "Above", DEFAULT_STYLE, clip);
  buf.writeClipped(0, 5, "Below", DEFAULT_STYLE, clip);
  // Should not write outside clip y range
  assertEquals(buf.getCell(0, 0)?.char, " ");
  assertEquals(buf.getCell(0, 5)?.char, " ");
});

Deno.test("writeClipped: drops characters outside clip region (x)", () => {
  const buf = new ScreenBuffer(20, 10);
  const clip = { x: 5, y: 0, width: 5, height: 10 };
  buf.writeClipped(3, 0, "ABCDEFGHIJ", DEFAULT_STYLE, clip);
  // A=3, B=4, C=5, D=6, E=7, F=8, G=9, H=10, I=11, J=12
  // Clip is x=5..9, so C,D,E,F,G are written
  assertEquals(buf.getCell(3, 0)?.char, " "); // A before clip
  assertEquals(buf.getCell(4, 0)?.char, " "); // B before clip
  assertEquals(buf.getCell(5, 0)?.char, "C"); // start of clip
  assertEquals(buf.getCell(9, 0)?.char, "G"); // end of clip
  assertEquals(buf.getCell(10, 0)?.char, " "); // H after clip
});

Deno.test("writeClipped: writes at edge of clip region", () => {
  const buf = new ScreenBuffer(20, 10);
  const clip = { x: 0, y: 0, width: 5, height: 1 };
  buf.writeClipped(0, 0, "ABCDE", DEFAULT_STYLE, clip);
  assertEquals(buf.getCell(4, 0)?.char, "E");
  // F would be outside
  buf.writeClipped(0, 0, "ABCDEF", DEFAULT_STYLE, clip);
  assertEquals(buf.getCell(5, 0)?.char, " "); // F not written
});

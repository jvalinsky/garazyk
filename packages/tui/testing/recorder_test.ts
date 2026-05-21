/**
 * TUI Session Recorder Unit Tests
 *
 * Verifies that TuiSessionRecorder hooks into the harness,
 * records visual frames sequentially, and generates valid asciicast v2 output.
 *
 * @module tui/testing/recorder_test
 */

import { assertEquals, assert } from "@std/assert";
import { VirtualTuiHarness } from "./harness.ts";
import { TuiSessionRecorder } from "./recorder.ts";
import { ScreenBuffer, DEFAULT_STYLE } from "../renderer.ts";

Deno.test("TuiSessionRecorder: initializes and records initial frame", () => {
  const render = (buf: ScreenBuffer) => {
    buf.fillRect(0, 0, buf.width, buf.height, " ", DEFAULT_STYLE);
    buf.write(0, 0, "Test Screen", DEFAULT_STYLE);
  };

  const harness = new VirtualTuiHarness(40, 5, render);
  const recorder = new TuiSessionRecorder(harness);

  const cast = recorder.exportAsciicast();
  const lines = cast.split("\n");

  assert(lines.length >= 2, "Should contain at least header and one frame line");

  // Parse header
  const header = JSON.parse(lines[0]);
  assertEquals(header.version, 2);
  assertEquals(header.width, 40);
  assertEquals(header.height, 5);
  assertEquals(header.title, "Garazyk TUI E2E Recording");

  // Parse first frame
  const firstFrame = JSON.parse(lines[1]);
  assertEquals(firstFrame[1], "o"); // output event
  assert(typeof firstFrame[0] === "number", "Timestamp should be a number");
  assert(firstFrame[2].includes("Test Screen"), "First frame should contain screen contents");
});

Deno.test("TuiSessionRecorder: captures subsequent visual updates dynamically", async () => {
  let counter = 0;
  const render = (buf: ScreenBuffer) => {
    buf.fillRect(0, 0, buf.width, buf.height, " ", DEFAULT_STYLE);
    buf.write(0, 0, `Count: ${counter}`, DEFAULT_STYLE);
  };

  const harness = new VirtualTuiHarness(20, 2, render);
  const recorder = new TuiSessionRecorder(harness);

  harness.onKey((key) => {
    if (key.key === "u") {
      counter += 1;
    }
  });

  // Verify initial frame count
  let cast = recorder.exportAsciicast();
  let lines = cast.split("\n");
  assertEquals(lines.length, 2, "Should have header + frame 1");

  // Simulate short delay and key press to trigger re-render
  await new Promise((resolve) => setTimeout(resolve, 20));
  await harness.emitKey("u");

  // Verify second frame recorded
  cast = recorder.exportAsciicast();
  lines = cast.split("\n");
  assertEquals(lines.length, 3, "Should have header + frame 1 + frame 2");

  const secondFrame = JSON.parse(lines[2]);
  assert(secondFrame[0] > 0, "Second frame should have a positive timestamp delay");
  assert(secondFrame[2].includes("Count: 1"), "Second frame should show updated counter state");
});

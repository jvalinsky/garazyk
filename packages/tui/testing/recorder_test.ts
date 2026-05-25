/**
 * TUI Session Recorder Unit Tests
 *
 * Verifies that TuiSessionRecorder hooks into the harness,
 * records visual frames sequentially, and generates valid asciicast v2 output.
 *
 * @module tui/testing/recorder_test
 */

import { assert, assertEquals } from "@std/assert";
import { VirtualTuiHarness } from "./harness.ts";
import { attachRecorder, TuiSessionRecorder } from "./recorder.ts";
import type { CastEvent } from "./cast.ts";
import { DEFAULT_STYLE } from "../renderer.ts";
import type { ScreenBuffer } from "../renderer.ts";

Deno.test("TuiSessionRecorder: initializes and records initial frame", () => {
  const render = (buf: ScreenBuffer) => {
    buf.fillRect(0, 0, buf.width, buf.height, " ", DEFAULT_STYLE);
    buf.write(0, 0, "Test Screen", DEFAULT_STYLE);
  };

  const harness = new VirtualTuiHarness(40, 5, render);
  const recorder = new TuiSessionRecorder(harness);
  harness.attachRecorder(recorder);

  const cast = recorder.exportAsciicast();
  const lines = cast.split("\n");

  assert(
    lines.length >= 2,
    "Should contain at least header and one frame line",
  );

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
  assert(
    firstFrame[2].includes("Test Screen"),
    "First frame should contain screen contents",
  );
});

Deno.test("TuiSessionRecorder: captures subsequent visual updates dynamically", async () => {
  let counter = 0;
  const render = (buf: ScreenBuffer) => {
    buf.fillRect(0, 0, buf.width, buf.height, " ", DEFAULT_STYLE);
    buf.write(0, 0, `Count: ${counter}`, DEFAULT_STYLE);
  };

  const harness = new VirtualTuiHarness(20, 2, render);
  const recorder = new TuiSessionRecorder(harness);
  attachRecorder(harness, recorder);

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
  assert(
    lines.length >= 3,
    `Should have header + frames (got ${lines.length} lines)`,
  );

  const outputFrames = lines.slice(1).map((l) => JSON.parse(l) as CastEvent)
    .filter(
      (e) => e[1] === "o",
    );
  assert(outputFrames.length >= 2, "Should have at least two output frames");
  const lastOutput = outputFrames[outputFrames.length - 1];
  assert(
    lastOutput[0] > 0,
    "Last output frame should have a positive timestamp delay",
  );
  assert(
    lastOutput[2].includes("Count: 1"),
    "Last output frame should show updated counter state",
  );
});

Deno.test("TuiSessionRecorder: basename path writes a file and captures initial output", async () => {
  const previousCwd = Deno.cwd();
  const tmpDir = await Deno.makeTempDir();

  try {
    Deno.chdir(tmpDir);

    const harness = new VirtualTuiHarness(20, 2, (buf) => {
      buf.fillRect(0, 0, buf.width, buf.height, " ", DEFAULT_STYLE);
      buf.write(0, 0, "File Frame", DEFAULT_STYLE);
    });
    const recorder = new TuiSessionRecorder(harness, {
      path: "session.cast",
    });
    attachRecorder(harness, recorder);

    await recorder.close();

    const castInfo = await Deno.stat("session.cast");
    assert(!castInfo.isDirectory, "basename cast path should be a file");

    const castLines = (await Deno.readTextFile("session.cast")).trimEnd().split(
      "\n",
    );
    assertEquals(JSON.parse(castLines[0]).version, 2);
    assert(
      castLines.slice(1).some((line) => line.includes("File Frame")),
      "initial output should be written after the file is opened",
    );

    const replayInfo = await Deno.stat("session.cast.replay.jsonl");
    assert(!replayInfo.isDirectory, "basename replay path should be a file");
  } finally {
    Deno.chdir(previousCwd);
    await Deno.remove(tmpDir, { recursive: true });
  }
});

Deno.test("TuiSessionRecorder: close detaches stale render listeners", async () => {
  let counter = 0;
  const harness = new VirtualTuiHarness(20, 2, (buf) => {
    buf.fillRect(0, 0, buf.width, buf.height, " ", DEFAULT_STYLE);
    buf.write(0, 0, `Frame ${counter}`, DEFAULT_STYLE);
  });
  const recorder = attachRecorder(harness, new TuiSessionRecorder(harness));

  const beforeClose = recorder.exportAsciicast();
  await recorder.close();

  counter += 1;
  harness.render();

  assertEquals(
    recorder.exportAsciicast(),
    beforeClose,
    "closed recorder should not receive later frames",
  );
});

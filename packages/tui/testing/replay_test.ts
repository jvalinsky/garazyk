/**
 * Replay script tests.
 *
 * @module tui/testing/replay_test
 */

import { assertEquals } from "@std/assert";
import { DEFAULT_STYLE, ScreenBuffer } from "../renderer.ts";
import { VirtualTuiHarness } from "./harness.ts";
import { CastRecorder, attachRecorder } from "./recorder.ts";
import { replayScript } from "./replay.ts";
import type { ReplayStep } from "./replay_types.ts";

Deno.test("replayScript: replays keys and updates screen", async () => {
  let counter = 0;
  const render = (buf: ScreenBuffer) => {
    buf.fillRect(0, 0, buf.width, buf.height, " ", DEFAULT_STYLE);
    buf.write(0, 0, `Count: ${counter}`, DEFAULT_STYLE);
  };

  const harness = new VirtualTuiHarness(20, 2, render);
  harness.onKey((key) => {
    if (key.key === "u") counter += 1;
  });

  const steps: ReplayStep[] = [
    { t: 0, kind: "key", key: "u" },
  ];

  await replayScript(harness, steps);
  harness.expectToContain("Count: 1");
});

Deno.test("attachRecorder: records key in replay script", async () => {
  let counter = 0;
  const render = (buf: ScreenBuffer) => {
    buf.fillRect(0, 0, buf.width, buf.height, " ", DEFAULT_STYLE);
    buf.write(0, 0, `N: ${counter}`, DEFAULT_STYLE);
  };

  const harness = new VirtualTuiHarness(10, 2, render);
  harness.onKey((key) => {
    if (key.key === "u") counter += 1;
  });

  const recorder = new CastRecorder(harness, { recordInput: true });
  attachRecorder(harness, recorder);
  await harness.emitKey("u");

  const steps = recorder.getReplaySteps();
  assertEquals(steps.length, 1);
  assertEquals(steps[0].kind, "key");
});

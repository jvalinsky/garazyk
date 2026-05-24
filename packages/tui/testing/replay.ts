/**
 * Deterministic replay of logical TUI scripts against VirtualTuiHarness.
 *
 * @module tui/testing/replay
 */

import type { VirtualTuiHarness } from "./harness.ts";
import type { ReplayStep } from "./replay_types.ts";

/** Options for {@link replayScript}. */
export interface ReplayScriptOptions {
  /** Playback speed multiplier (1 = real-time, Infinity = instant). */
  speed?: number;
  /** Invoke {@link CastRecorder.marker} via onMarker callback. */
  onMarker?: (label: string, t: number) => void;
}

/** Replay a script against a harness (keys and resizes only). */
export async function replayScript(
  harness: VirtualTuiHarness,
  steps: ReplayStep[],
  options: ReplayScriptOptions = {},
): Promise<void> {
  const speed = options.speed ?? Infinity;
  let lastT = 0;

  for (const step of steps) {
    const delayMs = speed === Infinity ? 0 : Math.max(0, (step.t - lastT) * 1000 / speed);
    lastT = step.t;
    if (delayMs > 0) {
      await new Promise((r) => setTimeout(r, delayMs));
    }

    switch (step.kind) {
      case "key":
        await harness.emitKey(step.key, {
          ctrl: step.ctrl,
          alt: step.alt,
          shift: step.shift,
        });
        break;
      case "resize":
        harness.emitResize(step.cols, step.rows);
        break;
      case "marker":
        options.onMarker?.(step.label, step.t);
        break;
    }
  }
}

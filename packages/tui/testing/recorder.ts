/**
 * TUI Session Recorder for E2E Automation Testing
 *
 * Implements a recorder that hooks into VirtualTuiHarness and
 * exports standard asciicast v2 format files for visual session playback.
 *
 * @module tui/testing/recorder
 */

import type { VirtualTuiHarness } from "./harness.ts";

/** Record event of terminal screen output frame. */
export type AsciicastFrame = [number, "o", string];

/** Session recorder wrapping VirtualTuiHarness. */
export class TuiSessionRecorder {
  private startTime = Date.now();
  private frames: AsciicastFrame[] = [];
  private harness: VirtualTuiHarness;

  constructor(harness: VirtualTuiHarness) {
    this.harness = harness;

    // Subscribes to rendering updates
    this.harness.onRender((frameAnsi: string) => {
      this.recordFrame(frameAnsi);
    });

    // Record the very first frame immediately upon initialization
    this.recordFrame(this.harness.buffer.fullRedraw());
  }

  /** Capture a frame state manually or automatically. */
  private recordFrame(ansiContent: string): void {
    const elapsedSeconds = (Date.now() - this.startTime) / 1000;
    this.frames.push([elapsedSeconds, "o", ansiContent]);
  }

  /** Export session history in standard line-delimited asciicast v2 JSON specification format. */
  exportAsciicast(): string {
    const header = {
      version: 2,
      width: this.harness.buffer.width,
      height: this.harness.buffer.height,
      timestamp: Math.floor(this.startTime / 1000),
      title: "Garazyk TUI E2E Recording",
      env: {
        TERM: "xterm-256color",
      },
    };

    const lines = [
      JSON.stringify(header),
      ...this.frames.map((frame) => JSON.stringify(frame)),
    ];

    return lines.join("\n");
  }
}

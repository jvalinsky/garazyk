/**
 * TUI session recorder — asciicast v2 + optional replay.jsonl.
 *
 * @module tui/testing/recorder
 */

import type { VirtualTuiHarness } from "./harness.ts";
import type { Key } from "../input.ts";
import {
  type AsciicastHeader,
  type CastEvent,
  encodeKeyInput,
  serializeAsciicast,
} from "./cast.ts";
import type { ReplayStep } from "./replay_types.ts";

/** @deprecated Use CastEvent */
export type AsciicastFrame = CastEvent;

/** Options for {@link CastRecorder}. */
export interface CastRecorderOptions {
  title?: string;
  /** Write NDJSON lines to this path as events occur. */
  path?: string;
  /** Also append logical replay steps to path + ".replay.jsonl" when path is set. */
  replayPath?: string;
  /** Record keyboard input as asciicast "i" events. */
  recordInput?: boolean;
  /** Minimum seconds between consecutive "o" frames (debounce). */
  minFrameInterval?: number;
}

/**
 * Records terminal output, input, resize, and markers for visual and logical replay.
 */
export class CastRecorder {
  private startTime = Date.now();
  private events: CastEvent[] = [];
  private replaySteps: ReplayStep[] = [];
  private harness: VirtualTuiHarness;
  private title: string;
  private recordInput: boolean;
  private minFrameInterval: number;
  private lastFrameTime = -Infinity;
  private file: Deno.FsFile | undefined;
  private replayFile: Deno.FsFile | undefined;
  private headerWritten = false;

  constructor(harness: VirtualTuiHarness, options: CastRecorderOptions = {}) {
    this.harness = harness;
    this.title = options.title ?? "Garazyk TUI E2E Recording";
    this.recordInput = options.recordInput ?? true;
    this.minFrameInterval = options.minFrameInterval ?? 0;

    this.harness.onRender((frameAnsi: string) => {
      this.recordOutput(frameAnsi);
    });
    this.recordOutput(this.harness.buffer.fullRedraw());

    if (options.path) {
      void this.#openFiles(options.path, options.replayPath);
    }
  }

  async #openFiles(castPath: string, replayPath?: string): Promise<void> {
    await Deno.mkdir(castPath.replace(/\/[^/]+$/, ""), { recursive: true }).catch(
      () => {},
    );
    this.file = await Deno.open(castPath, {
      write: true,
      create: true,
      truncate: true,
    });
    const header = this.#buildHeader();
    const line = JSON.stringify(header) + "\n";
    await this.file.write(new TextEncoder().encode(line));
    this.headerWritten = true;

    const rpath = replayPath ?? `${castPath}.replay.jsonl`;
    await Deno.mkdir(rpath.replace(/\/[^/]+$/, ""), { recursive: true }).catch(
      () => {},
    );
    this.replayFile = await Deno.open(rpath, {
      write: true,
      create: true,
      truncate: true,
    });
  }

  #elapsed(): number {
    return (Date.now() - this.startTime) / 1000;
  }

  #buildHeader(): AsciicastHeader {
    return {
      version: 2,
      width: this.harness.buffer.width,
      height: this.harness.buffer.height,
      timestamp: Math.floor(this.startTime / 1000),
      title: this.title,
      env: { TERM: "xterm-256color" },
    };
  }

  /** Record terminal output frame. */
  recordOutput(ansiContent: string): void {
    const t = this.#elapsed();
    if (t - this.lastFrameTime < this.minFrameInterval) return;
    this.lastFrameTime = t;
    const ev: CastEvent = [t, "o", ansiContent];
    this.events.push(ev);
    void this.#appendCastLine(JSON.stringify(ev));
  }

  /** Record a key event from the harness. */
  recordKey(key: Key): void {
    const t = this.#elapsed();
    const step: ReplayStep = {
      t,
      kind: "key",
      key: key.key,
      ctrl: key.ctrl || undefined,
      alt: key.alt || undefined,
      shift: key.shift || undefined,
    };
    this.replaySteps.push(step);
    void this.#appendReplayLine(JSON.stringify(step));

    if (this.recordInput) {
      const data = encodeKeyInput(key.key, key);
      if (data.length > 0) {
        const ev: CastEvent = [t, "i", data];
        this.events.push(ev);
        void this.#appendCastLine(JSON.stringify(ev));
      }
    }
  }

  /** Record terminal resize. */
  recordResize(cols: number, rows: number): void {
    const t = this.#elapsed();
    const step: ReplayStep = { t, kind: "resize", cols, rows };
    this.replaySteps.push(step);
    void this.#appendReplayLine(JSON.stringify(step));
    const ev: CastEvent = [t, "r", `${cols}x${rows}`];
    this.events.push(ev);
    void this.#appendCastLine(JSON.stringify(ev));
  }

  /** Insert a named marker for timeline navigation. */
  marker(label: string): void {
    const t = this.#elapsed();
    const step: ReplayStep = { t, kind: "marker", label };
    this.replaySteps.push(step);
    void this.#appendReplayLine(JSON.stringify(step));
    const ev: CastEvent = [t, "m", label];
    this.events.push(ev);
    void this.#appendCastLine(JSON.stringify(ev));
  }

  async #appendCastLine(line: string): Promise<void> {
    if (!this.file) return;
    await this.file.write(new TextEncoder().encode(line + "\n"));
  }

  async #appendReplayLine(line: string): Promise<void> {
    if (!this.replayFile) return;
    await this.replayFile.write(new TextEncoder().encode(line + "\n"));
  }

  /** Export session as asciicast v2 string. */
  exportAsciicast(): string {
    return serializeAsciicast(this.#buildHeader(), this.events);
  }

  /** Export logical replay script. */
  exportReplayScript(): string {
    return this.replaySteps.map((s) => JSON.stringify(s)).join("\n");
  }

  /** All recorded replay steps. */
  getReplaySteps(): readonly ReplayStep[] {
    return this.replaySteps;
  }

  /** Flush and close optional output files. */
  async close(): Promise<void> {
    if (this.file) {
      this.file.close();
      this.file = undefined;
    }
    if (this.replayFile) {
      this.replayFile.close();
      this.replayFile = undefined;
    }
  }
}

/** Back-compat alias for {@link CastRecorder}. */
export class TuiSessionRecorder extends CastRecorder {
  constructor(harness: VirtualTuiHarness, options?: CastRecorderOptions) {
    super(harness, options);
  }
}

/** Attach recorder to harness (records keys/resizes via harness hooks). */
export function attachRecorder(
  harness: VirtualTuiHarness,
  recorder: CastRecorder,
): CastRecorder {
  harness.attachRecorder(recorder);
  return recorder;
}

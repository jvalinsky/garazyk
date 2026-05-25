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
import { dirname } from "@std/path";

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
  private closed = false;
  private unsubscribeRender?: () => void;
  private encoder = new TextEncoder();

  constructor(harness: VirtualTuiHarness, options: CastRecorderOptions = {}) {
    this.harness = harness;
    this.title = options.title ?? "Garazyk TUI E2E Recording";
    this.recordInput = options.recordInput ?? true;
    this.minFrameInterval = options.minFrameInterval ?? 0;

    this.unsubscribeRender = this.harness.onRender((frameAnsi: string) => {
      this.recordOutput(frameAnsi);
    });

    if (options.path) {
      this.#openFiles(options.path, options.replayPath);
    }

    this.recordOutput(this.harness.buffer.fullRedraw());
  }

  #openFiles(castPath: string, replayPath?: string): void {
    Deno.mkdirSync(dirname(castPath), { recursive: true });
    this.file = Deno.openSync(castPath, {
      write: true,
      create: true,
      truncate: true,
    });
    this.#appendCastLine(JSON.stringify(this.#buildHeader()));

    const rpath = replayPath ?? `${castPath}.replay.jsonl`;
    Deno.mkdirSync(dirname(rpath), { recursive: true });
    this.replayFile = Deno.openSync(rpath, {
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
    if (this.closed) return;
    const t = this.#elapsed();
    if (t - this.lastFrameTime < this.minFrameInterval) return;
    this.lastFrameTime = t;
    const ev: CastEvent = [t, "o", ansiContent];
    this.events.push(ev);
    this.#appendCastLine(JSON.stringify(ev));
  }

  /** Record a key event from the harness. */
  recordKey(key: Key): void {
    if (this.closed) return;
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
    this.#appendReplayLine(JSON.stringify(step));

    if (this.recordInput) {
      const data = encodeKeyInput(key.key, key);
      if (data.length > 0) {
        const ev: CastEvent = [t, "i", data];
        this.events.push(ev);
        this.#appendCastLine(JSON.stringify(ev));
      }
    }
  }

  /** Record terminal resize. */
  recordResize(cols: number, rows: number): void {
    if (this.closed) return;
    const t = this.#elapsed();
    const step: ReplayStep = { t, kind: "resize", cols, rows };
    this.replaySteps.push(step);
    this.#appendReplayLine(JSON.stringify(step));
    const ev: CastEvent = [t, "r", `${cols}x${rows}`];
    this.events.push(ev);
    this.#appendCastLine(JSON.stringify(ev));
  }

  /** Insert a named marker for timeline navigation. */
  marker(label: string): void {
    if (this.closed) return;
    const t = this.#elapsed();
    const step: ReplayStep = { t, kind: "marker", label };
    this.replaySteps.push(step);
    this.#appendReplayLine(JSON.stringify(step));
    const ev: CastEvent = [t, "m", label];
    this.events.push(ev);
    this.#appendCastLine(JSON.stringify(ev));
  }

  #appendCastLine(line: string): void {
    if (!this.file) return;
    this.file.writeSync(this.encoder.encode(line + "\n"));
  }

  #appendReplayLine(line: string): void {
    if (!this.replayFile) return;
    this.replayFile.writeSync(this.encoder.encode(line + "\n"));
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
  close(): Promise<void> {
    if (this.closed) return Promise.resolve();
    this.closed = true;
    this.unsubscribeRender?.();
    this.unsubscribeRender = undefined;
    this.harness.detachRecorder(this);
    if (this.file) {
      this.file.close();
      this.file = undefined;
    }
    if (this.replayFile) {
      this.replayFile.close();
      this.replayFile = undefined;
    }
    return Promise.resolve();
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

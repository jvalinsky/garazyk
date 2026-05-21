/**
 * Virtual TUI Harness for Headless Testing
 *
 * Implements a pure in-memory virtual console environment where TUI components,
 * widgets, or TEA loops can be mounted, driven by mock keystrokes, and asserted on
 * without active standard I/O streams or platform TTY attachments.
 *
 * @module tui/testing/harness
 */

import { assert, assertEquals } from "@std/assert";
import { ScreenBuffer } from "../renderer.ts";
import type { CellStyle, Cell } from "../renderer.ts";
import type { Key } from "../input.ts";

/** Configuration options for VirtualTuiHarness. */
export interface HarnessOptions {
  /** Suppress styling and print as plain text in dumps. */
  noColor?: boolean;
}

/** Harness that wraps a ScreenBuffer and drives input/output mock states. */
export class VirtualTuiHarness {
  /** The internal virtual canvas grid. */
  buffer: ScreenBuffer;
  
  private renderCallback: (buf: ScreenBuffer) => void;
  private keyCallback?: (key: Key) => void;
  private resizeListeners: (() => void)[] = [];
  private renderListeners: ((ansi: string) => void)[] = [];

  constructor(
    width: number,
    height: number,
    render: (buf: ScreenBuffer) => void,
    options: HarnessOptions = {},
  ) {
    this.buffer = new ScreenBuffer(width, height, { noColor: options.noColor });
    this.renderCallback = render;
    this.render();
  }

  /** Trigger a fresh rendering frame on the component. */
  render(): void {
    this.buffer.clear();
    this.renderCallback(this.buffer);
    const frameAnsi = this.buffer.fullRedraw();
    for (const listener of this.renderListeners) {
      listener(frameAnsi);
    }
  }

  /** Register hooks to intercept every visual rendering frame. */
  onRender(listener: (ansi: string) => void): void {
    this.renderListeners.push(listener);
  }

  /** Register keyboard input callback hooks. */
  onKey(callback: (key: Key) => void): void {
    this.keyCallback = callback;
  }

  /** Add active resize listener hooks to intercept SIGWINCH resizes. */
  addResizeListener(listener: () => void): void {
    this.resizeListeners.push(listener);
  }

  /** Simulate a terminal size change. */
  emitResize(cols: number, rows: number): void {
    this.buffer.resize(cols, rows);
    for (const listener of this.resizeListeners) {
      listener();
    }
    this.render();
  }

  /** Inject simulated key inputs into the mounted component listeners. */
  async emitKey(keyName: string, modifiers: Partial<Omit<Key, "key">> = {}): Promise<void> {
    if (!this.keyCallback) {
      throw new Error("No key callback handler has been registered on the VirtualTuiHarness.");
    }
    const keyEvent: Key = {
      key: keyName.toLowerCase(),
      ctrl: modifiers.ctrl ?? false,
      alt: modifiers.alt ?? false,
      shift: modifiers.shift ?? false,
    };
    this.keyCallback(keyEvent);
    this.render();
  }

  /** Dump the screen buffer contents to a plain text string. */
  dumpScreen(): string {
    const lines: string[] = [];
    for (let y = 0; y < this.buffer.height; y++) {
      let line = "";
      for (let x = 0; x < this.buffer.width; x++) {
        const cell = this.buffer.getCell(x, y);
        line += cell ? (cell.char || " ") : " ";
      }
      lines.push(line.trimEnd());
    }
    return lines.join("\n");
  }

  /** Dump the screen grid highlighting styled blocks. */
  dumpScreenStyled(): string {
    const lines: string[] = [];
    for (let y = 0; y < this.buffer.height; y++) {
      let line = "";
      for (let x = 0; x < this.buffer.width; x++) {
        const cell = this.buffer.getCell(x, y);
        if (!cell) {
          line += " ";
          continue;
        }
        const hasStyle = cell.style.fg >= 0 || cell.style.bg >= 0 || cell.style.bold || cell.style.underline;
        if (hasStyle) {
          line += `[${cell.char}]`;
        } else {
          line += cell.char || " ";
        }
      }
      lines.push(line.trimEnd());
    }
    return lines.join("\n");
  }

  /** Assert that the current screen buffer contains the specified text segment. */
  expectToContain(text: string): void {
    const screen = this.dumpScreen();
    assert(
      screen.includes(text),
      `Expected screen buffer content to include text "${text}", but found:\n${screen}`,
    );
  }

  /** Assert style matches on a specific character coordinate cell. */
  expectStyleAt(x: number, y: number, expectedStyle: Partial<CellStyle>): void {
    const cell = this.buffer.getCell(x, y);
    assert(cell, `No terminal cell exists at coordinate location (${x}, ${y})`);
    if (expectedStyle.fg !== undefined) {
      assertEquals(cell.style.fg, expectedStyle.fg, `Cell fg color mismatch at (${x}, ${y})`);
    }
    if (expectedStyle.bg !== undefined) {
      assertEquals(cell.style.bg, expectedStyle.bg, `Cell bg color mismatch at (${x}, ${y})`);
    }
    if (expectedStyle.bold !== undefined) {
      assertEquals(cell.style.bold, expectedStyle.bold, `Cell bold mismatch at (${x}, ${y})`);
    }
    if (expectedStyle.underline !== undefined) {
      assertEquals(cell.style.underline, expectedStyle.underline, `Cell underline mismatch at (${x}, ${y})`);
    }
  }
}

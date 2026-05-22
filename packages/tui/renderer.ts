/**
 * Terminal Screen Buffer + Diff-Based Renderer
 *
 * Provides a virtual terminal canvas (ScreenBuffer) that renders to a 2D grid
 * of cells, then diffs against the previous frame to emit minimal ANSI escape
 * sequences. Handles alternate screen, cursor visibility, and color output.
 *
 * @module tui/renderer
 */

import { getCharWidth } from "./text.ts";
import { getCurrentTheme } from "./theme.ts";
import type { BoundingBox } from "./command.ts";

// ---------------------------------------------------------------------------
// Cell — single character position in the buffer
// ---------------------------------------------------------------------------

/** Style attributes for a single terminal cell. */
export interface CellStyle {
  /** ANSI foreground color code (0-255) or -1 for default. */
  fg: number;
  /** ANSI background color code (0-255) or -1 for default. */
  bg: number;
  /** Whether the text is rendered in bold. */
  bold: boolean;
  /** Whether the text is rendered dim. */
  dim: boolean;
  /** Whether the text and background colors are reversed. */
  reverse: boolean;
  /** Whether the text is rendered with an underline. */
  underline: boolean;
}

/** A single cell in the screen buffer. */
export interface Cell {
  /** The single character or CJK character to render. */
  char: string;
  /** The cell styling configuration. */
  style: CellStyle;
}

/** Create a default (empty) cell. */
function emptyCell(): Cell {
  return { char: " ", style: DEFAULT_STYLE };
}

/** Default cell style — no colors, no attributes. */
export const DEFAULT_STYLE: CellStyle = {
  fg: -1,
  bg: -1,
  bold: false,
  dim: false,
  reverse: false,
  underline: false,
};

/** ScreenBuffer configuration options. */
export interface ScreenBufferOptions {
  /** Suppress ANSI color codes (text attributes are preserved). */
  noColor?: boolean;
}

/** Virtual terminal canvas that renders to a 2D grid of cells. */
export class ScreenBuffer {
  private cells: Cell[];
  private prevCells: Cell[];
  /** The width of the screen buffer in character cells. */
  width: number;
  /** The height of the screen buffer in character cells. */
  height: number;
  private noColor: boolean;

  /**
   * Creates a new virtual screen buffer.
   *
   * @param width The width of the buffer.
   * @param height The height of the buffer.
   * @param options Configuration options.
   */
  constructor(
    width: number,
    height: number,
    options: ScreenBufferOptions = {},
  ) {
    this.width = width;
    this.height = height;
    this.noColor = options.noColor ?? false;
    this.cells = Array.from({ length: width * height }, emptyCell);
    this.prevCells = Array.from({ length: width * height }, emptyCell);
  }

  /** Resize the buffer, clearing all content. */
  resize(width: number, height: number): void {
    this.width = width;
    this.height = height;
    this.cells = Array.from({ length: width * height }, emptyCell);
    // Initialize prevCells with a unique state that will never match a real cell
    // to ensure the next diff() emits a full redraw.
    this.prevCells = Array.from({ length: width * height }, () => ({
      char: "",
      style: { ...DEFAULT_STYLE, fg: -1 }, // fg -1 is impossible
    }));
  }

  /** Clear all cells to spaces with default style. */
  clear(): void {
    for (let i = 0; i < this.cells.length; i++) {
      this.cells[i] = emptyCell();
    }
  }

  /** Get the cell at (x, y). Returns undefined if out of bounds. */
  getCell(x: number, y: number): Cell | undefined {
    if (x < 0 || x >= this.width || y < 0 || y >= this.height) return undefined;
    return this.cells[y * this.width + x];
  }

  /** Set the cell at (x, y). No-op if out of bounds. */
  setCell(x: number, y: number, cell: Cell): void {
    if (x < 0 || x >= this.width || y < 0 || y >= this.height) return;
    this.cells[y * this.width + x] = cell;
  }

  /**
   * Write a string starting at (x, y) with the given style.
   *
   * When the write style has no background (bg < 0), the existing cell's
   * background is preserved. This allows text to render on top of a filled
   * panel background without clobbering it with the terminal default.
   */
  write(
    x: number,
    y: number,
    text: string,
    style: CellStyle = DEFAULT_STYLE,
  ): void {
    let cx = x;
    for (const char of text) {
      if (cx >= this.width) break;
      const w = getCharWidth(char);
      if (w === 0) continue; // skip control characters
      const resolved = this.resolveStyle(cx, y, style);
      this.setCell(cx, y, { char, style: resolved });
      // Mark following cells as continuation of a wide character
      for (let i = 1; i < w; i++) {
        if (cx + i >= this.width) break;
        this.setCell(cx + i, y, { char: "", style: resolved });
      }
      cx += w;
    }
  }

  /**
   * Write a string clipped to a rectangular region.
   * Characters outside the clip region are silently dropped.
   *
   * When the write style has no background (bg < 0), the existing cell's
   * background is preserved so text renders on top of panel fills.
   */
  writeClipped(
    x: number,
    y: number,
    text: string,
    style: CellStyle = DEFAULT_STYLE,
    clip: { x: number; y: number; width: number; height: number },
  ): void {
    if (y < clip.y || y >= clip.y + clip.height) return;
    let cx = x;
    for (const char of text) {
      if (cx >= this.width) break;
      const w = getCharWidth(char);
      if (w === 0) continue;
      if (cx >= clip.x && cx < clip.x + clip.width) {
        const resolved = this.resolveStyle(cx, y, style);
        this.setCell(cx, y, { char, style: resolved });
        for (let i = 1; i < w; i++) {
          if (cx + i >= this.width) break;
          if (cx + i >= clip.x && cx + i < clip.x + clip.width) {
            this.setCell(cx + i, y, { char: "", style: resolved });
          }
        }
      }
      cx += w;
    }
  }

  /** Fill a rectangular region with a character and style. */
  fillRect(
    x: number,
    y: number,
    w: number,
    h: number,
    char: string = " ",
    style: CellStyle = DEFAULT_STYLE,
  ): void {
    for (let row = y; row < y + h; row++) {
      for (let col = x; col < x + w; col++) {
        this.setCell(col, row, { char, style });
      }
    }
  }

  /**
   * Fill a rectangular region clipped to a bounding box.
   * Cells outside the clip region are silently skipped.
   */
  fillRectClipped(
    x: number,
    y: number,
    w: number,
    h: number,
    char: string = " ",
    style: CellStyle = DEFAULT_STYLE,
    clip?: { x: number; y: number; width: number; height: number },
  ): void {
    if (!clip) {
      this.fillRect(x, y, w, h, char, style);
      return;
    }
    for (let row = y; row < y + h; row++) {
      if (row < clip.y || row >= clip.y + clip.height) continue;
      for (let col = x; col < x + w; col++) {
        if (col < clip.x || col >= clip.x + clip.width) continue;
        this.setCell(col, row, { char, style });
      }
    }
  }

  /** Draw a box border with the given style. */
  box(
    x: number,
    y: number,
    w: number,
    h: number,
    style: CellStyle = DEFAULT_STYLE,
    focused: boolean = false,
  ): void {
    const borderStyle = focused
      ? { ...style, bold: true, fg: getCurrentTheme().borderFocused }
      : style;

    // Corners
    this.setCell(x, y, { char: "┌", style: borderStyle });
    this.setCell(x + w - 1, y, { char: "┐", style: borderStyle });
    this.setCell(x, y + h - 1, { char: "└", style: borderStyle });
    this.setCell(x + w - 1, y + h - 1, { char: "┘", style: borderStyle });

    // Top and bottom edges
    for (let col = x + 1; col < x + w - 1; col++) {
      this.setCell(col, y, { char: "─", style: borderStyle });
      this.setCell(col, y + h - 1, { char: "─", style: borderStyle });
    }

    // Left and right edges
    for (let row = y + 1; row < y + h - 1; row++) {
      this.setCell(x, row, { char: "│", style: borderStyle });
      this.setCell(x + w - 1, row, { char: "│", style: borderStyle });
    }
  }

  /** Draw a title in the top border of a box. */
  boxTitle(
    x: number,
    y: number,
    w: number,
    title: string,
    style: CellStyle = DEFAULT_STYLE,
  ): void {
    const label = ` ${title} `;
    const startX = x + Math.max(1, Math.floor((w - label.length) / 2));
    this.write(startX, y, label, { ...style, bold: true });
  }

  /** Draw a box border, clipped to the given region. */
  boxClipped(
    x: number,
    y: number,
    w: number,
    h: number,
    style: CellStyle = DEFAULT_STYLE,
    focused: boolean = false,
    clip?: BoundingBox,
  ): void {
    if (!clip) {
      this.box(x, y, w, h, style, focused);
      return;
    }

    const borderStyle = focused
      ? { ...style, bold: true, fg: getCurrentTheme().borderFocused }
      : style;

    // Helper: only set cell if within clip
    const setIfClipped = (cx: number, cy: number, char: string) => {
      if (
        cx >= clip.x && cx < clip.x + clip.width &&
        cy >= clip.y && cy < clip.y + clip.height
      ) {
        this.setCell(cx, cy, { char, style: borderStyle });
      }
    };

    // Corners
    setIfClipped(x, y, "┌");
    setIfClipped(x + w - 1, y, "┐");
    setIfClipped(x, y + h - 1, "└");
    setIfClipped(x + w - 1, y + h - 1, "┘");

    // Top and bottom edges
    for (let col = x + 1; col < x + w - 1; col++) {
      setIfClipped(col, y, "─");
      setIfClipped(col, y + h - 1, "─");
    }

    // Left and right edges
    for (let row = y + 1; row < y + h - 1; row++) {
      setIfClipped(x, row, "│");
      setIfClipped(x + w - 1, row, "│");
    }
  }

  /**
   * When the requested style has no background (bg < 0), pull the
   * background from the existing cell so text doesn't clobber panel fills.
   */
  private resolveStyle(x: number, y: number, style: CellStyle): CellStyle {
    if (style.bg >= 0) return style;
    const existing = this.getCell(x, y);
    if (existing && existing.style.bg >= 0) {
      return { ...style, bg: existing.style.bg };
    }
    return style;
  }

  /**
   * Diff current buffer against previous frame and emit minimal ANSI output.
   * After rendering, call this to get the escape sequence string.
   */
  diff(): string {
    const parts: string[] = [];
    let lastStyle: CellStyle | null = null;
    let cursorX = -1;
    let cursorY = -1;

    for (let i = 0; i < this.cells.length; i++) {
      const curr = this.cells[i];
      const prev = this.prevCells[i];

      // Skip unchanged cells
      if (cellsEqual(curr, prev)) continue;

      const x = i % this.width;
      const y = Math.floor(i / this.width);

      // Move cursor if not contiguous
      if (x !== cursorX || y !== cursorY) {
        parts.push(moveCursor(x, y));
      }

      // Apply style if changed
      if (!stylesEqual(curr.style, lastStyle)) {
        parts.push(encodeStyle(curr.style, this.noColor));
        lastStyle = { ...curr.style };
      }
      parts.push(curr.char);
      cursorX = x + 1;
      cursorY = y;
    }

    // Reset style at end
    if (lastStyle && !stylesEqual(lastStyle, DEFAULT_STYLE)) {
      parts.push(RESET);
    }

    // Swap buffers
    this.prevCells = this.cells.map((c) => ({ ...c, style: { ...c.style } }));

    return parts.join("");
  }

  /** Full redraw — emit entire buffer as ANSI (used after resize). */
  fullRedraw(): string {
    const parts: string[] = [];
    let lastStyle: CellStyle | null = null;

    for (let i = 0; i < this.cells.length; i++) {
      const cell = this.cells[i];
      const x = i % this.width;
      const y = Math.floor(i / this.width);

      // Move cursor to start of each row
      if (x === 0) {
        parts.push(moveCursor(0, y));
      }

      // Apply style if changed
      if (!stylesEqual(cell.style, lastStyle)) {
        parts.push(encodeStyle(cell.style, this.noColor));
        lastStyle = { ...cell.style };
      }

      parts.push(cell.char);
    }

    // Reset style at end
    if (lastStyle && !stylesEqual(lastStyle, DEFAULT_STYLE)) {
      parts.push(RESET);
    }

    // Update prev buffer
    this.prevCells = this.cells.map((c) => ({ ...c, style: { ...c.style } }));

    return parts.join("");
  }
}

// ---------------------------------------------------------------------------
// ANSI escape sequences
// ---------------------------------------------------------------------------

/** Common ANSI escape sequences. */
export const ANSI = {
  BLACK: 0,
  RED: 1,
  GREEN: 2,
  YELLOW: 3,
  BLUE: 4,
  MAGENTA: 5,
  CYAN: 6,
  WHITE: 7,
  BRIGHT_BLACK: 8,
  BRIGHT_RED: 9,
  BRIGHT_GREEN: 10,
  BRIGHT_YELLOW: 11,
  BRIGHT_BLUE: 12,
  BRIGHT_MAGENTA: 13,
  BRIGHT_CYAN: 14,
  BRIGHT_WHITE: 15,
} as const;

/** Reset all attributes. */
export const RESET = "\x1b[0m";

/** Enter alternate screen buffer. */
export const ENTER_ALT_SCREEN = "\x1b[?1049h";

/** Exit alternate screen buffer. */
export const EXIT_ALT_SCREEN = "\x1b[?1049l";

/** Hide cursor. */
export const HIDE_CURSOR = "\x1b[?25l";

/** Show cursor. */
export const SHOW_CURSOR = "\x1b[?25h";

/** Clear screen. */
export const CLEAR_SCREEN = "\x1b[2J";

/** Move cursor to home position. */
export const CURSOR_HOME = "\x1b[H";

// ---------------------------------------------------------------------------
// Style helpers
// ---------------------------------------------------------------------------

/** Create a style with a foreground color. */
export function fg(color: number): CellStyle {
  return { ...DEFAULT_STYLE, fg: color };
}

/** Create a style with a background color. */
export function bg(color: number): CellStyle {
  return { ...DEFAULT_STYLE, bg: color };
}

/** Create a bold style. */
export function bold(style: CellStyle = DEFAULT_STYLE): CellStyle {
  return { ...style, bold: true };
}

/** Create a dim style. */
export function dim(style: CellStyle = DEFAULT_STYLE): CellStyle {
  return { ...style, dim: true };
}

/** Create a reverse-video style. */
export function reverse(style: CellStyle = DEFAULT_STYLE): CellStyle {
  return { ...style, reverse: true };
}

/** Create an underline style. */
export function underline(style: CellStyle = DEFAULT_STYLE): CellStyle {
  return { ...style, underline: true };
}

/** Combine two styles (right overrides left). */
export function mergeStyles(
  base: CellStyle,
  override: Partial<CellStyle>,
): CellStyle {
  return { ...base, ...override };
}

// ---------------------------------------------------------------------------
// Semantic color palette
// ---------------------------------------------------------------------------

/**
 * Semantic color tokens derived from the active theme (see `theme.ts`).
 * Exported via theme.ts → mod.ts; not re-exported here to avoid conflicts.
 */
export { COLORS, getCurrentTheme, setCurrentTheme } from "./theme.ts";

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

function moveCursor(x: number, y: number): string {
  return `\x1b[${y + 1};${x + 1}H`;
}

function encodeStyle(style: CellStyle, noColor: boolean): string {
  const parts: string[] = ["0"]; // reset

  if (style.bold) parts.push("1");
  if (style.dim) parts.push("2");
  if (style.underline) parts.push("4");
  if (style.reverse) parts.push("7");

  // Skip color codes when NO_COLOR is set (https://no-color.org/)
  // Text attributes (bold, dim, reverse, underline) are preserved.
  if (!noColor) {
    if (style.fg >= 0) {
      if (style.fg < 16) {
        parts.push(`${30 + style.fg % 8}`);
        if (style.fg >= 8) parts.push("1"); // bright = bold trick
      } else {
        parts.push(`38;5;${style.fg}`);
      }
    }

    if (style.bg >= 0) {
      // Use 256-color mode for all backgrounds to correctly support
      // bright colors (8-15) which have no standard 16-color bg codes
      parts.push(`48;5;${style.bg}`);
    }
  }

  return `\x1b[${parts.join(";")}m`;
}

function cellsEqual(a: Cell, b: Cell): boolean {
  return a.char === b.char && stylesEqual(a.style, b.style);
}

function stylesEqual(a: CellStyle | null, b: CellStyle | null): boolean {
  if (a === null && b === null) return true;
  if (a === null || b === null) return false;
  return a.fg === b.fg && a.bg === b.bg && a.bold === b.bold &&
    a.dim === b.dim && a.reverse === b.reverse && a.underline === b.underline;
}

// ---------------------------------------------------------------------------
// Terminal control — enter/exit alternate screen, cleanup
// ---------------------------------------------------------------------------

/** Saved original console methods, restored on exit. */
let savedConsoleLog: typeof console.log | null = null;
let savedConsoleError: typeof console.error | null = null;
let savedConsoleWarn: typeof console.warn | null = null;
let savedConsoleInfo: typeof console.info | null = null;

/**
 * Enter alternate screen, hide cursor, set raw mode.
 *
 * Also suppresses console.log/error/warn/info so that
 * service-layer logging (e.g. run-manager spawn messages) doesn't
 * corrupt the TUI's alternate screen buffer. In alternate screen mode,
 * both stdout and stderr write to the same terminal device, so
 * redirecting to stderr is not sufficient — output must be suppressed
 * entirely or written to a file.
 */
export async function enterTerminalMode(): Promise<void> {
  const encoder = new TextEncoder();
  await Deno.stdout.write(
    encoder.encode(ENTER_ALT_SCREEN + CLEAR_SCREEN + CURSOR_HOME + HIDE_CURSOR),
  );
  Deno.stdin.setRaw(true);

  // Suppress console output — both stdout and stderr go to the same
  // terminal in alternate screen mode, so any write corrupts the TUI.
  savedConsoleLog = console.log;
  savedConsoleError = console.error;
  savedConsoleWarn = console.warn;
  savedConsoleInfo = console.info;

  const noop = (..._args: unknown[]) => {};
  console.log = noop;
  console.error = noop;
  console.warn = noop;
  console.info = noop;
}

/**
 * Exit alternate screen, show cursor, restore raw mode.
 *
 * Restores original console methods so post-TUI output works normally.
 */
export async function exitTerminalMode(): Promise<void> {
  // Restore console before writing to stdout
  if (savedConsoleLog !== null) console.log = savedConsoleLog;
  if (savedConsoleError !== null) console.error = savedConsoleError;
  if (savedConsoleWarn !== null) console.warn = savedConsoleWarn;
  if (savedConsoleInfo !== null) console.info = savedConsoleInfo;
  savedConsoleLog = null;
  savedConsoleError = null;
  savedConsoleWarn = null;
  savedConsoleInfo = null;

  Deno.stdin.setRaw(false);
  const encoder = new TextEncoder();
  await Deno.stdout.write(
    encoder.encode(SHOW_CURSOR + RESET + EXIT_ALT_SCREEN),
  );
}

/** Write a string to stdout. */
export async function writeToTerminal(text: string): Promise<void> {
  await Deno.stdout.write(new TextEncoder().encode(text));
}

/** Check if stdin is a terminal. */
export function isTerminal(): boolean {
  try {
    return Deno.stdin.isTerminal();
  } catch {
    return false;
  }
}

/** Get current terminal size. Returns null if not a terminal. */
export function getTerminalSize(): { cols: number; rows: number } | null {
  try {
    const size = Deno.consoleSize();
    return { cols: size.columns, rows: size.rows };
  } catch {
    return null;
  }
}

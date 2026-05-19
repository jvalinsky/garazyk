/**
 * Text Layout & Measuring Primitives
 *
 * Implements terminal-aware string measuring and wrapping. Decouples the logic
 * of fitting text into grids from the actual rendering commands.
 *
 * Handles CJK double-width characters, ANSI escape sequence stripping,
 * word and character wrapping, and truncation with ellipsis.
 *
 * @module tui/text
 */

// ---------------------------------------------------------------------------
// ANSI escape sequence handling
// ---------------------------------------------------------------------------

/** Regex matching any ANSI escape (CSI, OSC, etc.). */
// deno-lint-ignore no-control-regex
const ANSI_ANY_RE = /\x1b\[[0-9;]*[a-zA-Z]|\x1b\].*?(?:\x1b\\|\x07)/g;

/**
 * Strip ANSI escape sequences from a string.
 *
 * Removes CSI sequences (e.g. `\x1b[31m`) and OSC sequences.
 * Useful before measuring visual width or writing to a buffer.
 *
 * @param text - String that may contain ANSI escape sequences
 * @returns String with all ANSI sequences removed
 *
 * @example
 * ```typescript
 * stripAnsi("\x1b[31mHello\x1b[0m"); // "Hello"
 * ```
 */
export function stripAnsi(text: string): string {
  return text.replace(ANSI_ANY_RE, "");
}

// ---------------------------------------------------------------------------
// Character width
// ---------------------------------------------------------------------------

/**
 * Get the visual column width of a single character.
 *
 * Returns 2 for CJK ideographs and other double-width characters,
 * 1 for all other printable characters.
 *
 * @param char - A single character (may be a multi-codepoint grapheme)
 * @returns Visual column width (1 or 2)
 */
export function getCharWidth(char: string): number {
  const code = char.codePointAt(0);
  if (!code) return 0;

  // Control characters and null
  if (code < 0x20) return 0;

  // CJK Unified Ideographs and other double-width blocks
  if (
    (code >= 0x2E80 && code <= 0x9FFF) || // CJK blocks
    (code >= 0xA000 && code <= 0xA4CF) || // Yi, Hangul Jamo
    (code >= 0xAC00 && code <= 0xD7AF) || // Hangul Syllables
    (code >= 0xF900 && code <= 0xFAFF) || // CJK Compatibility Ideographs
    (code >= 0xFE30 && code <= 0xFE6F) || // CJK Compatibility Forms
    (code >= 0xFF00 && code <= 0xFF60) || // Fullwidth Forms
    (code >= 0xFFE0 && code <= 0xFFE6) || // Fullwidth signs
    (code >= 0x20000 && code <= 0x2FFFD) // CJK Extension B–I
  ) {
    return 2;
  }

  return 1;
}

// ---------------------------------------------------------------------------
// Text measurement
// ---------------------------------------------------------------------------

/**
 * Calculate the visual column width of a string in a terminal grid.
 *
 * Handles CJK double-width characters (2 cells each) and strips
 * ANSI escape sequences before measuring.
 *
 * @param text - String to measure
 * @returns Visual column width (number of terminal cells)
 *
 * @example
 * ```typescript
 * measureText("Hello");   // 5
 * measureText("你好");     // 4 (2 CJK chars × 2 cells)
 * ```
 */
export function measureText(text: string): number {
  let width = 0;
  for (const char of text) {
    width += getCharWidth(char);
  }
  return width;
}

/**
 * Measure text with awareness of ANSI escape sequences.
 *
 * Returns both the visual width (excluding ANSI codes) and the raw
 * string length (including ANSI codes).
 *
 * @param text - String that may contain ANSI escape sequences
 * @returns Object with `visual` (terminal cells) and `raw` (byte length) widths
 *
 * @example
 * ```typescript
 * const result = measureTextWithAnsi("\x1b[31mHello\x1b[0m");
 * // result.visual === 5  (only "Hello" occupies cells)
 * // result.raw === 12    (includes escape sequences)
 * ```
 */
export function measureTextWithAnsi(
  text: string,
): { visual: number; raw: number } {
  return {
    visual: measureText(stripAnsi(text)),
    raw: text.length,
  };
}

// ---------------------------------------------------------------------------
// Text wrapping
// ---------------------------------------------------------------------------

/** Text wrapping mode. */
export type WrapMode = "none" | "word" | "char";

/** Configuration for text wrapping. */
export interface TextLayoutConfig {
  /** Maximum visual width per line */
  maxWidth: number;
  /** Wrapping mode: none, word-break, or char-break */
  wrapMode?: WrapMode;
  /** Whether to preserve ANSI sequences in output (default: false) */
  preserveAnsi?: boolean;
}

/**
 * Wrap a string into multiple lines based on a maximum visual width.
 *
 * Supports two modes:
 * - **word**: Wraps at word boundaries. Words exceeding `maxWidth` are
 *   character-wrapped as a fallback.
 * - **char**: Wraps at character boundaries unconditionally.
 *
 * Content is preserved: no characters are lost during wrapping.
 *
 * @param text - String to wrap
 * @param config - Layout configuration with maxWidth and wrapMode
 * @returns Array of lines, each with visual width <= maxWidth
 *
 * @example
 * ```typescript
 * wrapText("Hello world foo", { maxWidth: 8, wrapMode: "word" });
 * // ["Hello", "world foo"]
 * ```
 */
export function wrapText(text: string, config: TextLayoutConfig): string[] {
  if (config.wrapMode === "none" || config.maxWidth <= 0) {
    return [text];
  }

  // Strip ANSI for measurement if not preserving
  const measureStr = config.preserveAnsi ? text : stripAnsi(text);

  if (config.wrapMode === "char") {
    return wrapChar(measureStr, config.maxWidth);
  }

  // Word wrap (default)
  return wrapWord(measureStr, config.maxWidth);
}

/**
 * Word-wrap a string at word boundaries.
 * Words longer than maxWidth are character-wrapped as fallback.
 */
function wrapWord(text: string, maxWidth: number): string[] {
  const lines: string[] = [];
  const words = text.split(" ");

  let currentLine = "";
  let currentWidth = 0;

  for (const word of words) {
    const wordWidth = measureText(word);

    // Word alone exceeds maxWidth — character-wrap it
    if (wordWidth > maxWidth) {
      if (currentLine.length > 0) {
        lines.push(currentLine);
        currentLine = "";
        currentWidth = 0;
      }

      let chunk = "";
      let chunkW = 0;
      for (const char of word) {
        const cw = getCharWidth(char);
        if (chunkW + cw > maxWidth) {
          lines.push(chunk);
          chunk = char;
          chunkW = cw;
        } else {
          chunk += char;
          chunkW += cw;
        }
      }
      currentLine = chunk;
      currentWidth = chunkW;
      continue;
    }

    // Normal word wrapping
    const spaceW = currentLine.length > 0 ? 1 : 0;
    if (currentWidth + spaceW + wordWidth > maxWidth) {
      lines.push(currentLine);
      currentLine = word;
      currentWidth = wordWidth;
    } else {
      currentLine += (currentLine.length > 0 ? " " : "") + word;
      currentWidth += spaceW + wordWidth;
    }
  }

  if (currentLine.length > 0) {
    lines.push(currentLine);
  }

  return lines;
}

/**
 * Character-wrap a string at character boundaries.
 */
function wrapChar(text: string, maxWidth: number): string[] {
  const lines: string[] = [];
  let currentLine = "";
  let currentWidth = 0;

  for (const char of text) {
    const cw = getCharWidth(char);
    if (currentWidth + cw > maxWidth && currentLine.length > 0) {
      lines.push(currentLine);
      currentLine = char;
      currentWidth = cw;
    } else {
      currentLine += char;
      currentWidth += cw;
    }
  }

  if (currentLine.length > 0) {
    lines.push(currentLine);
  }

  return lines;
}

// ---------------------------------------------------------------------------
// Truncation
// ---------------------------------------------------------------------------

/**
 * Truncate a string to fit within a maximum visual width.
 *
 * If the string exceeds `maxWidth`, it is truncated and an ellipsis
 * character is appended. The result always fits within `maxWidth` cells.
 *
 * @param text - String to truncate
 * @param maxWidth - Maximum visual width in terminal cells
 * @param ellipsis - Ellipsis string to append (default: "…")
 * @returns Truncated string with visual width <= maxWidth
 *
 * @example
 * ```typescript
 * truncate("Hello, world!", 8);    // "Hello, w…"
 * truncate("Hi", 8);              // "Hi"
 * truncate("你好世界", 5);          // "你好…" (4 + 1 = 5 cells)
 * ```
 */
export function truncate(
  text: string,
  maxWidth: number,
  ellipsis = "…",
): string {
  const textWidth = measureText(text);
  if (textWidth <= maxWidth) return text;

  const ellipsisWidth = measureText(ellipsis);
  const targetWidth = maxWidth - ellipsisWidth;

  if (targetWidth <= 0) {
    // maxWidth is too small even for ellipsis alone
    return ellipsis.slice(0, maxWidth);
  }

  let result = "";
  let width = 0;
  for (const char of text) {
    const cw = getCharWidth(char);
    if (width + cw > targetWidth) break;
    result += char;
    width += cw;
  }

  return result + ellipsis;
}

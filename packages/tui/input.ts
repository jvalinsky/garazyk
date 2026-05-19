/**
 * Key Input Parser for Terminal UI
 *
 * Reads raw bytes from stdin and parses them into structured Key events.
 * Handles escape sequences (arrow keys, function keys, modified keys),
 * Ctrl combinations, and Unicode characters.
 *
 * @module tui/input
 */

// ---------------------------------------------------------------------------
// Key type
// ---------------------------------------------------------------------------

/** A parsed key event from the terminal. */
export interface Key {
  /** The base key name (e.g., "a", "enter", "up", "escape") */
  key: string;
  /** Whether Ctrl is held */
  ctrl: boolean;
  /** Whether Alt is held */
  alt: boolean;
  /** Whether Shift is held */
  shift: boolean;
}

// ---------------------------------------------------------------------------
// Key name constants
// ---------------------------------------------------------------------------

/** Special key names used in Key.key. */
export const Keys = {
  ENTER: "enter",
  ESCAPE: "escape",
  TAB: "tab",
  BACKSPACE: "backspace",
  DELETE: "delete",
  UP: "up",
  DOWN: "down",
  RIGHT: "right",
  LEFT: "left",
  HOME: "home",
  END: "end",
  PAGE_UP: "pageup",
  PAGE_DOWN: "pagedown",
  INSERT: "insert",
  F1: "f1",
  F2: "f2",
  F3: "f3",
  F4: "f4",
  F5: "f5",
  F6: "f6",
  F7: "f7",
  F8: "f8",
  F9: "f9",
  F10: "f10",
  F11: "f11",
  F12: "f12",
  SPACE: "space",
  UNKNOWN: "unknown",
} as const;

// ---------------------------------------------------------------------------
// Key reader
// ---------------------------------------------------------------------------

/** Async iterator that reads and parses key events from stdin. */
export async function* readKeys(): AsyncGenerator<Key> {
  const buffer = new Uint8Array(64);
  let pending: number[] = [];

  while (true) {
    const read = await Deno.stdin.read(buffer);
    if (read === null) return;

    // Add bytes to pending buffer
    for (let i = 0; i < read; i++) {
      pending.push(buffer[i]!);
    }

    // Try to parse keys from pending bytes
    while (pending.length > 0) {
      const result = parseKey(pending);
      if (result === null) {
        // Need more bytes — wait for next read
        break;
      }
      const [key, consumed] = result;
      pending = pending.slice(consumed);
      yield key;
    }
  }
}

// ---------------------------------------------------------------------------
// Key parser
// ---------------------------------------------------------------------------

/**
 * Parse a key from the start of a byte sequence.
 * Returns [Key, bytesConsumed] or null if more bytes are needed.
 * Exported for testing.
 */
export function parseKey(bytes: number[]): [Key, number] | null {
  if (bytes.length === 0) return null;

  const b0 = bytes[0]!;

  // Ctrl+A through Ctrl+Z (1-26)
  if (b0 >= 1 && b0 <= 26) {
    const char = String.fromCharCode(b0 + 96); // 1→a, 2→b, ...
    // Special cases
    if (b0 === 9) return [{ key: Keys.TAB, ctrl: false, alt: false, shift: false }, 1];
    if (b0 === 13) return [{ key: Keys.ENTER, ctrl: false, alt: false, shift: false }, 1];
    if (b0 === 10) return [{ key: Keys.ENTER, ctrl: false, alt: false, shift: false }, 1]; // LF
    if (b0 === 27) return [{ key: Keys.ESCAPE, ctrl: false, alt: false, shift: false }, 1]; // won't reach, escape handled below
    return [{ key: char, ctrl: true, alt: false, shift: false }, 1];
  }

  // Escape sequences
  if (b0 === 27) {
    return parseEscapeSequence(bytes);
  }

  // DEL (127) = backspace
  if (b0 === 127) {
    return [{ key: Keys.BACKSPACE, ctrl: false, alt: false, shift: false }, 1];
  }

  // Printable ASCII (32-126)
  if (b0 >= 32 && b0 <= 126) {
    const char = String.fromCharCode(b0);
    const shift = b0 >= 65 && b0 <= 90; // A-Z
    return [{ key: char.toLowerCase(), ctrl: false, alt: false, shift }, 1];
  }

  // UTF-8 multi-byte sequences
  if (b0 >= 0xC0 && b0 <= 0xDF && bytes.length >= 2) {
    const char = decodeUtf8(bytes.slice(0, 2));
    return [{ key: char, ctrl: false, alt: false, shift: false }, 2];
  }
  if (b0 >= 0xE0 && b0 <= 0xEF && bytes.length >= 3) {
    const char = decodeUtf8(bytes.slice(0, 3));
    return [{ key: char, ctrl: false, alt: false, shift: false }, 3];
  }
  if (b0 >= 0xF0 && b0 <= 0xF7 && bytes.length >= 4) {
    const char = decodeUtf8(bytes.slice(0, 4));
    return [{ key: char, ctrl: false, alt: false, shift: false }, 4];
  }

  // Need more bytes for UTF-8
  if (b0 >= 0xC0) return null;

  // Unknown byte — skip it
  return [{ key: Keys.UNKNOWN, ctrl: false, alt: false, shift: false }, 1];
}

/**
 * Parse an escape sequence starting with ESC (0x1b).
 * Returns [Key, bytesConsumed] or null if more bytes are needed.
 */
function parseEscapeSequence(bytes: number[]): [Key, number] | null {
  if (bytes.length < 2) {
    // Bare ESC — might be Alt+something, wait briefly
    // For now, return ESC if we only have 1 byte
    return [{ key: Keys.ESCAPE, ctrl: false, alt: false, shift: false }, 1];
  }

  const b1 = bytes[1]!;

  // Alt + key (ESC followed by printable char)
  if (b1 >= 32 && b1 <= 126 && b1 !== 91 && b1 !== 79) {
    const char = String.fromCharCode(b1).toLowerCase();
    return [{ key: char, ctrl: false, alt: true, shift: b1 >= 65 && b1 <= 90 }, 2];
  }

  // CSI sequences: ESC [ ...
  if (b1 === 91) { // '['
    return parseCsiSequence(bytes);
  }

  // SS3 sequences: ESC O ...
  if (b1 === 79) { // 'O'
    return parseSs3Sequence(bytes);
  }

  // Unknown ESC sequence
  return [{ key: Keys.ESCAPE, ctrl: false, alt: false, shift: false }, 1];
}

/**
 * Parse a CSI (Control Sequence Introducer) sequence: ESC [ ...
 * Handles arrow keys, modified arrow keys, home/end, etc.
 */
function parseCsiSequence(bytes: number[]): [Key, number] | null {
  if (bytes.length < 3) return null;

  const b2 = bytes[2]!;

  // Simple 2-byte CSI: ESC [ <final>
  // A=up, B=down, C=right, D=left, H=home, F=end
  if (b2 >= 65 && b2 <= 90) {
    const key = csiFinalToKey(b2, 1, false);
    if (key) return [key, 3];
  }

  // ESC [ 1 ~ (home on some terminals)
  if (b2 === 49 && bytes.length >= 4 && bytes[3] === 126) {
    return [{ key: Keys.HOME, ctrl: false, alt: false, shift: false }, 4];
  }

  // ESC [ 2 ~ (insert)
  if (b2 === 50 && bytes.length >= 4 && bytes[3] === 126) {
    return [{ key: Keys.INSERT, ctrl: false, alt: false, shift: false }, 4];
  }

  // ESC [ 3 ~ (delete)
  if (b2 === 51 && bytes.length >= 4 && bytes[3] === 126) {
    return [{ key: Keys.DELETE, ctrl: false, alt: false, shift: false }, 4];
  }

  // ESC [ 4 ~ (end on some terminals)
  if (b2 === 52 && bytes.length >= 4 && bytes[3] === 126) {
    return [{ key: Keys.END, ctrl: false, alt: false, shift: false }, 4];
  }

  // ESC [ 5 ~ (page up)
  if (b2 === 53 && bytes.length >= 4 && bytes[3] === 126) {
    return [{ key: Keys.PAGE_UP, ctrl: false, alt: false, shift: false }, 4];
  }

  // ESC [ 6 ~ (page down)
  if (b2 === 54 && bytes.length >= 4 && bytes[3] === 126) {
    return [{ key: Keys.PAGE_DOWN, ctrl: false, alt: false, shift: false }, 4];
  }

  // Extended CSI: ESC [ <params> ; <params> <final>
  // e.g., ESC [ 1 ; 5 A = Ctrl+Up
  if (b2 >= 49 && b2 <= 57) {
    // Scan for ';' and final byte
    let semicolonIdx = -1;
    let finalIdx = -1;
    for (let i = 3; i < Math.min(bytes.length, 12); i++) {
      if (bytes[i] === 59 && semicolonIdx === -1) semicolonIdx = i; // ';'
      if (bytes[i]! >= 65 && bytes[i]! <= 90 && finalIdx === -1) finalIdx = i; // A-Z
      if (bytes[i] === 126) { finalIdx = i; break; } // '~'
    }

    if (finalIdx === -1) {
      // Need more bytes
      if (bytes.length < 12) return null;
      // Give up — consume what we have
      return [{ key: Keys.UNKNOWN, ctrl: false, alt: false, shift: false }, 3];
    }

    const param1 = parseCsiParam(bytes, 2, semicolonIdx);
    const param2 = semicolonIdx !== -1
      ? parseCsiParam(bytes, semicolonIdx + 1, finalIdx)
      : 1;
    const finalByte = bytes[finalIdx]!;
    const consumed = finalIdx + 1;

    // Modified keys: param2 encodes modifiers
    // 1=none, 2=shift, 3=alt, 4=ctrl+alt, 5=ctrl, 6=ctrl+shift, 7=ctrl+alt+shift
    const shift = param2 === 2 || param2 === 6 || param2 === 7;
    const alt = param2 === 3 || param2 === 4 || param2 === 7;
    const ctrl = param2 >= 4 && param2 <= 7;

    if (finalByte >= 65 && finalByte <= 90) {
      const key = csiFinalToKey(finalByte, param1, false);
      if (key) return [{ ...key, ctrl, alt, shift }, consumed];
    }

    if (finalByte === 126) {
      // Function keys with tilde
      const key = tildeParamToKey(param1);
      if (key) return [{ ...key, ctrl, alt, shift }, consumed];
    }

    return [{ key: Keys.UNKNOWN, ctrl, alt, shift }, consumed];
  }

  // Fallback
  return [{ key: Keys.ESCAPE, ctrl: false, alt: false, shift: false }, 1];
}

/** Parse an SS3 sequence: ESC O <final> */
function parseSs3Sequence(bytes: number[]): [Key, number] | null {
  if (bytes.length < 3) return null;

  const b2 = bytes[2]!;
  const mapping: Record<number, string> = {
    65: Keys.UP,    // A
    66: Keys.DOWN,  // B
    67: Keys.RIGHT, // C
    68: Keys.LEFT,  // D
    72: Keys.HOME,  // H
    70: Keys.END,   // F
    80: Keys.F1,    // P
    81: Keys.F2,    // Q
    82: Keys.F3,    // R
    83: Keys.F4,    // S
  };

  const key = mapping[b2];
  if (key) return [{ key, ctrl: false, alt: false, shift: false }, 3];

  return [{ key: Keys.UNKNOWN, ctrl: false, alt: false, shift: false }, 3];
}

/** Map CSI final byte (A-Z) to key name. */
function csiFinalToKey(final: number, _param: number, _isTilde: boolean): Key | null {
  const mapping: Record<number, string> = {
    65: Keys.UP,    // A
    66: Keys.DOWN,  // B
    67: Keys.RIGHT, // C
    68: Keys.LEFT,  // D
    69: Keys.END,   // E
    72: Keys.HOME,  // H
    70: Keys.END,   // F
  };
  const key = mapping[final];
  if (key) return { key, ctrl: false, alt: false, shift: false };
  return null;
}

/** Map tilde parameter to key name. */
function tildeParamToKey(param: number): Key | null {
  const mapping: Record<number, string> = {
    1: Keys.HOME,
    2: Keys.INSERT,
    3: Keys.DELETE,
    4: Keys.END,
    5: Keys.PAGE_UP,
    6: Keys.PAGE_DOWN,
    11: Keys.F1,
    12: Keys.F2,
    13: Keys.F3,
    14: Keys.F4,
    15: Keys.F5,
    17: Keys.F6,
    18: Keys.F7,
    19: Keys.F8,
    20: Keys.F9,
    21: Keys.F10,
    23: Keys.F11,
    24: Keys.F12,
  };
  const key = mapping[param];
  if (key) return { key, ctrl: false, alt: false, shift: false };
  return null;
}

/** Parse a numeric parameter from a CSI sequence between start and end. */
function parseCsiParam(bytes: number[], start: number, end: number): number {
  let value = 0;
  for (let i = start; i < end && i < bytes.length; i++) {
    const b = bytes[i]!;
    if (b >= 48 && b <= 57) { // '0'-'9'
      value = value * 10 + (b - 48);
    } else {
      break;
    }
  }
  return value || 1; // default to 1 if empty
}

/** Decode a UTF-8 byte sequence to a string. */
function decodeUtf8(bytes: number[]): string {
  return new TextDecoder().decode(new Uint8Array(bytes));
}

// ---------------------------------------------------------------------------
// Key matching helpers
// ---------------------------------------------------------------------------

/** Check if a key matches a simple key name. */
export function isKey(key: Key, name: string): boolean {
  return key.key === name && !key.ctrl && !key.alt && !key.shift;
}

/** Check if a key is Ctrl+key. */
export function isCtrl(key: Key, name: string): boolean {
  return key.key === name && key.ctrl && !key.alt && !key.shift;
}

/** Check if a key is a quit key (q or Ctrl+C). */
export function isQuit(key: Key): boolean {
  return isKey(key, "q") || isCtrl(key, "c");
}

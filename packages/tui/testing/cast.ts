/**
 * Asciicast v2 types and parse/serialize helpers.
 *
 * @see https://docs.asciinema.org/manual/asciicast/v2/
 * @module tui/testing/cast
 */

/** Supported asciicast v2 event type codes. */
export type CastEventCode = "o" | "i" | "m" | "r";

/** Asciicast v2 event tuple: [timeSeconds, code, data]. */
export type CastEvent = [number, CastEventCode, string];

/** Parsed asciicast v2 file. */
export interface AsciicastFile {
  header: AsciicastHeader;
  events: CastEvent[];
}

/** Asciicast v2 header object (first line of .cast file). */
export interface AsciicastHeader {
  version: 2;
  width: number;
  height: number;
  timestamp?: number;
  duration?: number;
  title?: string;
  env?: Record<string, string>;
  theme?: Record<string, string>;
}

/** Parse a full asciicast v2 document from a string. */
export function parseAsciicast(content: string): AsciicastFile {
  const lines = content.trim().split("\n").filter((l) => l.length > 0);
  if (lines.length === 0) {
    throw new Error("Empty asciicast content");
  }
  const header = JSON.parse(lines[0]) as AsciicastHeader;
  if (header.version !== 2) {
    throw new Error(`Unsupported asciicast version: ${header.version}`);
  }
  const events: CastEvent[] = [];
  for (let i = 1; i < lines.length; i++) {
    const tuple = JSON.parse(lines[i]) as CastEvent;
    if (!Array.isArray(tuple) || tuple.length !== 3) {
      throw new Error(`Invalid cast event at line ${i + 1}`);
    }
    events.push(tuple);
  }
  return { header, events };
}

/** Serialize header + events to asciicast v2 NDJSON. */
export function serializeAsciicast(
  header: AsciicastHeader,
  events: CastEvent[],
): string {
  const lines = [JSON.stringify(header), ...events.map((e) => JSON.stringify(e))];
  return lines.join("\n");
}

/** Extract marker labels and timestamps from a cast. */
export function extractMarkers(events: CastEvent[]): Array<{ t: number; label: string }> {
  const markers: Array<{ t: number; label: string }> = [];
  for (const [t, code, data] of events) {
    if (code === "m") markers.push({ t, label: data });
  }
  return markers;
}

/** Encode a Key-like input for asciicast "i" events (single char or control). */
export function encodeKeyInput(
  keyName: string,
  modifiers: { ctrl?: boolean; alt?: boolean; shift?: boolean } = {},
): string {
  const k = keyName.toLowerCase();
  if (k === "enter" || k === "return") return "\r";
  if (k === "tab") return "\t";
  if (k === "backspace") return "\u007f";
  if (k === "escape" || k === "esc") return "\u001b";
  if (k === "space") return " ";
  if (k.length === 1) {
    let ch = k;
    if (modifiers.shift) ch = ch.toUpperCase();
    if (modifiers.ctrl && ch >= "a" && ch <= "z") {
      return String.fromCharCode(ch.charCodeAt(0) - 96);
    }
    return ch;
  }
  return "";
}

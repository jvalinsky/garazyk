/**
 * Timeline ↔ log sync helpers for run replay UI.
 *
 * @module lib/timeline
 */

/** Minimal event row shape from the events API or DB. */
export interface TimelineEventRow {
  eventType: string;
  timestamp: number;
}

/**
 * Map a timeline offset (ms from run start) to a log line index for scrolling.
 * Uses persisted log_line event timestamps when available.
 */
export function offsetMsToLogLineIndex(
  events: TimelineEventRow[],
  startedAt: number,
  offsetMs: number,
): number | undefined {
  const logOffsets: number[] = [];
  for (const e of events) {
    if (e.eventType === "log_line") {
      logOffsets.push(Math.max(0, e.timestamp - startedAt));
    }
  }
  if (logOffsets.length === 0) return undefined;

  let idx = 0;
  for (let i = 0; i < logOffsets.length; i++) {
    if (logOffsets[i] <= offsetMs) idx = i;
    else break;
  }
  return idx;
}

/** Fallback scroll ratio when line index is unavailable. */
export function offsetMsToLogScrollRatio(
  events: TimelineEventRow[],
  startedAt: number,
  offsetMs: number,
): number {
  const lineIdx = offsetMsToLogLineIndex(events, startedAt, offsetMs);
  if (lineIdx === undefined) {
    const end = events.length > 0
      ? Math.max(...events.map((e) => e.timestamp - startedAt), 1)
      : 1;
    return Math.min(1, Math.max(0, offsetMs / end));
  }
  const logCount = events.filter((e) => e.eventType === "log_line").length;
  if (logCount <= 1) return 0;
  return lineIdx / (logCount - 1);
}

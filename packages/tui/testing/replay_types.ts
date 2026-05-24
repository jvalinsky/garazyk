/**
 * Logical replay script types (Garazyk replay.jsonl).
 *
 * @module tui/testing/replay_types
 */

/** Single step in a harness replay script. */
export type ReplayStep =
  | {
    t: number;
    kind: "key";
    key: string;
    ctrl?: boolean;
    alt?: boolean;
    shift?: boolean;
  }
  | { t: number; kind: "resize"; cols: number; rows: number }
  | { t: number; kind: "marker"; label: string };

/** Parse replay.jsonl content into steps. */
export function parseReplayScript(content: string): ReplayStep[] {
  const steps: ReplayStep[] = [];
  for (const line of content.trim().split("\n")) {
    if (!line.trim()) continue;
    steps.push(JSON.parse(line) as ReplayStep);
  }
  return steps;
}

/** Serialize steps to replay.jsonl. */
export function serializeReplayScript(steps: ReplayStep[]): string {
  return steps.map((s) => JSON.stringify(s)).join("\n");
}

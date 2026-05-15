/**
 * Shared utility functions for the scenario dashboard.
 */

/**
 * Categorize a scenario ID into a category name.
 * IDs 1-10: core, 11-20: identity, 21-30: scale, 30+: edge
 */
export function categorize(id: string): string {
  const num = parseInt(id);
  if (num <= 10) return "core";
  if (num <= 20) return "identity";
  if (num <= 30) return "scale";
  return "edge";
}

/**
 * Status icon map for scenario and step results.
 */
export const STATUS_ICONS: Record<string, string> = {
  passed: "✓",
  failed: "✗",
  skipped: "–",
  running: "⟳",
};

/**
 * Format duration in milliseconds as a human-readable string.
 * E.g., 500ms, 1.2s
 */
export function formatDurationMs(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}

/**
 * Format duration in seconds as a human-readable string.
 * E.g., 5s, 2m 30s
 */
export function formatDurationSec(s: number): string {
  if (s < 60) return `${s.toFixed(1)}s`;
  const m = Math.floor(s / 60);
  const sec = Math.round(s % 60);
  return `${m}m ${sec}s`;
}

/**
 * Format Unix timestamp as a localized date/time string.
 */
export function formatDate(ts: number): string {
  return new Date(ts * 1000).toLocaleString();
}

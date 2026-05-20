/** Shared formatting utilities. @module format */

/**
 * Format a byte count with binary units (KiB, MiB, GiB, TiB).
 *
 * Uses binary prefixes for consistency with Docker and OS reporting.
 * Values below 1 KiB are shown as whole bytes with no decimal.
 */
export function formatBytes(bytes: number): string {
  const units = ["B", "KiB", "MiB", "GiB", "TiB"];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`;
}

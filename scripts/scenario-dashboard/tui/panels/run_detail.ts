/**
 * Run Detail Overlay — full-screen overlay showing scenario results for a run
 *
 * Renders a scrollable list of scenario results with inline failure messages.
 * Uses the same ScreenBuffer direct-write pattern as the help overlay.
 *
 * @module tui/panels/run_detail
 */

import type { CellStyle, ScreenBuffer } from "@garazyk/tui";
import {
  ANSI,
  bg,
  bold,
  COLORS,
  DEFAULT_STYLE,
  dim,
  fg,
  truncate,
} from "@garazyk/tui";
import type { Run, ScenarioResultView, ScenarioStep } from "../../services/types.ts";

// ---------------------------------------------------------------------------
// Status indicators
// ---------------------------------------------------------------------------

const STATUS_PASSED = "\u25CF";  // ●
const STATUS_FAILED = "\u2716";  // ✖
const STATUS_SKIPPED = "\u25CB"; // ○

function scenarioIndicator(status: ScenarioResultView["status"]): string {
  switch (status) {
    case "passed":
      return STATUS_PASSED;
    case "failed":
      return STATUS_FAILED;
    case "skipped":
      return STATUS_SKIPPED;
    case "running":
      return STATUS_PASSED; // shouldn't appear in detail, but fallback
  }
}

function scenarioColor(status: ScenarioResultView["status"]): number {
  switch (status) {
    case "passed":
      return COLORS.statusOk;
    case "failed":
      return COLORS.statusErr;
    case "skipped":
      return COLORS.textMuted;
    case "running":
      return COLORS.statusWarn;
  }
}

function statusBadge(status: Run["status"]): string {
  switch (status) {
    case "completed":
      return "[done]";
    case "running":
      return "[run ]";
    case "starting":
    case "stopping":
      return "[wait]";
    case "error":
      return "[fail]";
  }
}

function statusBadgeColor(status: Run["status"]): number {
  switch (status) {
    case "completed":
      return COLORS.statusOk;
    case "running":
      return COLORS.badgeRunning;
    case "starting":
    case "stopping":
      return COLORS.statusWarn;
    case "error":
      return COLORS.statusErr;
  }
}

function formatDurationMs(ms: number | null): string {
  if (ms == null) return "-";
  if (ms < 1000) return `${ms}ms`;
  const s = ms / 1000;
  if (s < 60) return `${s.toFixed(1)}s`;
  const m = Math.floor(s / 60);
  const sec = Math.round(s % 60);
  return `${m}m ${sec}s`;
}

function formatDurationSec(s: number | undefined): string {
  if (s == null) return "-";
  if (s < 60) return `${s.toFixed(1)}s`;
  const m = Math.floor(s / 60);
  const sec = Math.round(s % 60);
  return `${m}m ${sec}s`;
}

// ---------------------------------------------------------------------------
// Overlay renderer
// ---------------------------------------------------------------------------

/** Render a full-screen run detail overlay on top of the current buffer content. */
export function renderRunDetailOverlay(
  buf: ScreenBuffer,
  run: Run,
  results: ScenarioResultView[],
  cursor: number,
  scrollOffset: number,
): void {
  const overlayStyle = bg(ANSI.BLACK);
  const titleStyle = bold(fg(COLORS.accent));
  const labelStyle = dim(fg(COLORS.textPrimary));

  // Fill the entire screen with dark background
  buf.fillRect(0, 0, buf.width, buf.height, " ", overlayStyle);

  // Calculate box dimensions
  const boxWidth = Math.min(80, buf.width - 2);
  const boxHeight = Math.min(buf.height - 2, 30);
  const boxX = Math.floor((buf.width - boxWidth) / 2);
  const boxY = Math.max(1, Math.floor((buf.height - boxHeight) / 2));

  // Draw the box border
  buf.box(boxX, boxY, boxWidth, boxHeight, overlayStyle, false);

  // Clip region for content inside the box
  const clip = { x: boxX + 1, y: boxY + 1, width: boxWidth - 2, height: boxHeight - 2 };
  const contentX = boxX + 2;
  const contentWidth = boxWidth - 4;
  let row = boxY + 1;
  const maxRow = boxY + boxHeight - 2;

  // ── Title line: Run ID + status badge ──────────────────────────────
  const badge = statusBadge(run.status);
  const badgeColor = statusBadgeColor(run.status);
  const titleText = `Run ${truncate(run.id, 30)}`;
  buf.writeClipped(contentX, row, titleText, titleStyle, clip);
  buf.writeClipped(contentX + titleText.length + 1, row, badge, fg(badgeColor), clip);
  row++;

  // ── Metadata line: topology, runner, pds2, binary ──────────────────
  if (row <= maxRow) {
    const parts: string[] = [];
    if (run.topology) parts.push(`topology: ${run.topology}`);
    if (run.runner) parts.push(`runner: ${run.runner}`);
    parts.push(`pds2: ${run.pds2 ? "yes" : "no"}`);
    parts.push(`binary: ${run.binaryMode ? "yes" : "no"}`);
    const metaText = parts.join("  ");
    buf.writeClipped(contentX, row, metaText, labelStyle, clip);
    row++;
  }

  // ── Summary line: passed/failed/skipped + duration ────────────────
  if (row <= maxRow) {
    const passed = run.passed;
    const failed = run.failed;
    const skipped = run.skipped;
    const dur = formatDurationSec(run.durationS);
    let summaryText = `${passed} passed  ${failed} failed  ${skipped} skipped  duration: ${dur}`;
    buf.writeClipped(contentX, row, summaryText, fg(COLORS.textPrimary), clip);
    row++;
  }

  // ── Blank line ─────────────────────────────────────────────────────
  row++;

  // ── Scenario list ─────────────────────────────────────────────────
  const listStartRow = row;
  const listHeight = maxRow - row + 1 - 1; // -1 for footer
  const visibleCount = Math.max(0, listHeight);

  // Compute how many rows each scenario takes (failed ones get an extra line for the error)
  function scenarioRows(result: ScenarioResultView): number {
    if (result.status === "failed" && result.steps.length > 0) {
      const failedStep = result.steps.find((s) => s.status === "failed");
      if (failedStep?.detail) return 2; // scenario line + error detail line
    }
    return 1;
  }

  // Build a flat list of display rows for virtual scrolling
  // Each entry is either a scenario row or a detail row
  interface DisplayRow {
    type: "scenario" | "detail";
    resultIndex: number;
    text: string;
    isCursor: boolean;
    style: CellStyle;
  }

  const displayRows: DisplayRow[] = [];
  for (let i = 0; i < results.length; i++) {
    const r = results[i]!;
    const isCursor = i === cursor;
    const indicator = scenarioIndicator(r.status);
    const color = scenarioColor(r.status);
    const name = truncate(r.scenarioName, contentWidth - 16);
    const dur = formatDurationMs(r.durationMs);

    // Right-aligned duration
    const namePart = ` ${indicator} ${name}`;
    const durPart = ` ${r.status} ${dur}`;
    const padding = Math.max(0, contentWidth - namePart.length - durPart.length);

    const rowStyle = isCursor
      ? bold(fg(COLORS.accent))
      : fg(COLORS.textPrimary);
    const indicatorStyle = isCursor
      ? bold(fg(COLORS.accent))
      : fg(color);

    displayRows.push({
      type: "scenario",
      resultIndex: i,
      text: namePart + " ".repeat(padding) + durPart,
      isCursor,
      style: rowStyle,
    });

    // Failed step detail line
    if (r.status === "failed" && r.steps.length > 0) {
      const failedStep = r.steps.find((s) => s.status === "failed");
      if (failedStep?.detail) {
        const detailText = `   \u2514 ${truncate(failedStep.detail, contentWidth - 4)}`;
        const detailStyle = isCursor
          ? bold(fg(COLORS.accent))
          : fg(COLORS.statusErr);
        displayRows.push({
          type: "detail",
          resultIndex: i,
          text: detailText,
          isCursor,
          style: detailStyle,
        });
      }
    }
  }

  // Render visible rows with scroll offset
  let renderRow = listStartRow;
  for (let i = scrollOffset; i < displayRows.length && renderRow <= maxRow - 1; i++) {
    const dr = displayRows[i]!;
    // Cursor highlight: fill the row background
    if (dr.isCursor && dr.type === "scenario") {
      buf.fillRect(contentX, renderRow, contentWidth, 1, " ", bg(ANSI.BRIGHT_BLACK));
    }
    buf.writeClipped(contentX, renderRow, dr.text, dr.style, clip);
    renderRow++;
  }

  // ── Footer: keybinding hints ───────────────────────────────────────
  const footerRow = boxY + boxHeight - 2;
  const footerText = "\u2191\u2193 navigate  Esc close";
  buf.writeClipped(contentX, footerRow, footerText, dim(fg(COLORS.textPrimary)), clip);

  // ── Box title ───────────────────────────────────────────────────────
  buf.boxTitle(boxX, boxY, boxWidth, "Run Detail", overlayStyle);
}

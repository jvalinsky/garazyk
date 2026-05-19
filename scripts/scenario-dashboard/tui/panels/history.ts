/**
 * History Panel — displays recent run history and container metrics
 *
 * Supports cursor navigation for selecting past runs.
 * All writes are clipped to the panel content area.
 *
 * @module tui/panels/history
 */

import type { ScreenBuffer, CellStyle } from "@garazyk/tui";
import { DEFAULT_STYLE, COLORS, ANSI, bold, dim, fg, reverse } from "@garazyk/tui";
import type { PanelLayout } from "@garazyk/tui";
import { panelContentArea } from "@garazyk/tui";
import type { PanelState } from "../panel_state.ts";
import type { Run } from "../../services/types.ts";

/** Render the run history panel. */
export function renderHistoryPanel(
  buf: ScreenBuffer,
  panel: PanelLayout,
  recentRuns: Run[],
  metrics: Record<string, { cpu: string; mem: string }>,
  panelState: PanelState,
  focused: boolean,
): void {
  const area = panelContentArea(panel);

  if (area.height < 1 || area.width < 10) return;

  let row = 0;
  const cursor = panelState.cursor;
  const scrollOffset = panelState.scrollOffset;
  const metricsRows = hasMetrics(metrics) ? Object.keys(metrics).length + 2 : 0; // header + blank + items
  const maxRunRows = Math.max(1, area.height - metricsRows - 1); // -1 for actions

  // Recent runs
  if (recentRuns.length === 0) {
    buf.writeClipped(area.x, area.y + row, "No recorded runs", dim(fg(COLORS.textMuted)), area);
  } else {
    for (let i = scrollOffset; i < recentRuns.length && row < maxRunRows; i++) {
      const run = recentRuns[i]!;
      const isCursorRow = focused && i === cursor;

      const statusBadge = runStatusBadge(run.status);
      const statusStyle = isCursorRow ? reverse(fg(COLORS.accent)) : runStatusStyle(run.status);
      const runId = run.id.length > 20 ? run.id.slice(0, 20) : run.id;

      // Clear row for cursor highlight
      if (isCursorRow) {
        buf.fillRect(area.x, area.y + row, area.width, 1, " ", reverse(fg(COLORS.accent)));
      }

      let col = area.x;
      buf.writeClipped(col, area.y + row, statusBadge, statusStyle, area);
      col += statusBadge.length + 1;

      buf.writeClipped(col, area.y + row, runId, isCursorRow ? reverse(fg(COLORS.accent)) : fg(COLORS.textPrimary), area);
      col += 21;

      // Results
      const completed = run.passed + run.failed + run.skipped;
      const results = run.failed > 0
        ? `${completed}/${run.totalScenarios}  ${run.failed} fail`
        : `${completed}/${run.totalScenarios} pass`;
      buf.writeClipped(col, area.y + row, results, isCursorRow ? reverse(fg(COLORS.accent)) : (run.failed > 0 ? fg(COLORS.statusErr) : fg(COLORS.statusOk)), area);
      col += 14;

      // Duration
      if (run.durationS != null) {
        const dur = formatDurationSec(run.durationS);
        if (col + dur.length <= area.x + area.width) {
          buf.writeClipped(col, area.y + row, dur, isCursorRow ? reverse(fg(COLORS.accent)) : dim(fg(COLORS.textSecondary)), area);
        }
      }

      row++;
    }
  }

  // Metrics section
  if (hasMetrics(metrics) && row + 2 < area.height) {
    row++; // blank line
    buf.writeClipped(area.x, area.y + row, "Metrics", bold(fg(COLORS.textPrimary)), area);
    row++;

    for (const [name, stats] of Object.entries(metrics)) {
      if (row >= area.height - (focused ? 1 : 0)) break;

      const label = name.padEnd(10);
      const cpu = `cpu: ${stats.cpu}`.padEnd(12);
      const mem = `mem: ${stats.mem}`;

      buf.writeClipped(area.x, area.y + row, label, fg(COLORS.textPrimary), area);
      buf.writeClipped(area.x + 11, area.y + row, cpu, dim(fg(COLORS.textSecondary)), area);
      if (area.x + 11 + cpu.length + mem.length <= area.x + area.width) {
        buf.writeClipped(area.x + 11 + cpu.length, area.y + row, mem, dim(fg(COLORS.textSecondary)), area);
      }
      row++;
    }
  }

  // Panel-local actions hint
  if (focused) {
    const actionsRow = area.y + area.height - 1;
    const actions = "[Enter] view  [R]estart  ↑↓ scroll";
    buf.writeClipped(area.x, actionsRow, actions, dim(fg(COLORS.accent)), area);
  }
}

/** Get the selected run, or null. */
export function getSelectedRun(
  recentRuns: Run[],
  panelState: PanelState,
): Run | null {
  return recentRuns[panelState.cursor] ?? null;
}

function runStatusBadge(status: Run["status"]): string {
  switch (status) {
    case "completed": return "[done]";
    case "running": return "[run ]";
    case "starting":
    case "stopping": return "[wait]";
    case "error": return "[fail]";
  }
}

function runStatusStyle(status: Run["status"]): CellStyle {
  switch (status) {
    case "completed": return fg(COLORS.statusOk);
    case "running": return fg(COLORS.badgeRunning);
    case "starting":
    case "stopping": return fg(COLORS.statusWarn);
    case "error": return fg(COLORS.statusErr);
  }
}

function formatDurationSec(s: number): string {
  if (s < 60) return `${s.toFixed(1)}s`;
  const m = Math.floor(s / 60);
  const sec = Math.round(s % 60);
  return `${m}m ${sec}s`;
}

function hasMetrics(metrics: Record<string, { cpu: string; mem: string }>): boolean {
  return Object.keys(metrics).length > 0;
}

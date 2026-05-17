/**
 * Run Panel — displays active run progress, elapsed time, and activity
 *
 * @module tui/panels/run
 */

import type { ScreenBuffer } from "../renderer.ts";
import { DEFAULT_STYLE, COLORS, ANSI, bold, dim, fg, reverse } from "../renderer.ts";
import type { PanelLayout } from "../layout.ts";
import { panelContentArea } from "../layout.ts";
import type { Run } from "../../services/types.ts";
import type { RunProgress } from "../../dashboard_state.ts";

/** Render the active run panel. */
export function renderRunPanel(
  buf: ScreenBuffer,
  panel: PanelLayout,
  activeRun: Run | null,
  progressByRunId: Record<string, RunProgress>,
  focused: boolean,
): void {
  const area = panelContentArea(panel);

  if (area.height < 1 || area.width < 10) return;

  if (!activeRun) {
    renderNoActiveRun(buf, area);
    return;
  }

  const progress = progressByRunId[activeRun.id];
  const isLive = activeRun.status === "running" || activeRun.status === "starting";

  let row = 0;

  // Run ID + status
  const statusBadge = runStatusBadge(activeRun.status);
  const statusStyle = runStatusStyle(activeRun.status);
  const runId = activeRun.id.length > 23
    ? activeRun.id.slice(0, 23)
    : activeRun.id;

  buf.write(area.x, area.y + row, statusBadge, statusStyle);
  buf.write(area.x + statusBadge.length + 1, area.y + row, runId, bold(fg(COLORS.textPrimary)));
  row++;

  // Progress bar
  if (row < area.height) {
    const completed = activeRun.passed + activeRun.failed + activeRun.skipped;
    const total = activeRun.totalScenarios;
    const barWidth = Math.min(area.width - 12, 30);
    const bar = progressBar(completed, total, barWidth);
    buf.write(area.x, area.y + row, bar, fg(COLORS.textPrimary));
    row++;
  }

  // Pass/fail counts
  if (row < area.height) {
    const passed = activeRun.passed;
    const failed = activeRun.failed;
    const skipped = activeRun.skipped;

    let col = area.x;
    if (passed > 0 || failed === 0) {
      buf.write(col, area.y + row, `${passed} passed`, fg(COLORS.statusOk));
      col += 10;
    }
    if (failed > 0) {
      buf.write(col, area.y + row, `${failed} failed`, fg(COLORS.statusErr));
      col += 10;
    }
    if (skipped > 0) {
      buf.write(col, area.y + row, `${skipped} skipped`, fg(COLORS.statusWarn));
    }
    row++;
  }

  // Current scenario (from progress)
  if (row < area.height && progress && progress.total > 0) {
    const current = `Scenario ${Math.min(progress.completed + 1, progress.total)}/${progress.total}: ${progress.currentScenario ?? "..."}`;
    const truncated = current.length > area.width
      ? current.slice(0, area.width - 1) + "…"
      : current;
    buf.write(area.x, area.y + row, truncated, fg(COLORS.textPrimary));
    row++;
  }

  // Elapsed time
  if (row < area.height && isLive) {
    const elapsed = formatElapsed(Date.now() - activeRun.startedAt);
    buf.write(area.x, area.y + row, `Elapsed: ${elapsed}`, dim(fg(COLORS.textSecondary)));
    row++;
  }

  // Duration (for completed runs)
  if (row < area.height && !isLive && activeRun.durationS != null) {
    buf.write(area.x, area.y + row, `Duration: ${formatDurationSec(activeRun.durationS)}`, dim(fg(COLORS.textSecondary)));
    row++;
  }

  // Activity indicator (from progress)
  if (row < area.height && isLive && progress) {
    const secondsSinceUpdate = progress.updatedAt > 0
      ? Math.floor((Date.now() - progress.updatedAt) / 1000)
      : 0;
    const level = staleLevel(secondsSinceUpdate);
    const dot = level === "active" ? "●" : level === "slow" ? "◐" : "○";
    const dotStyle = level === "active" ? fg(COLORS.statusOk) : level === "slow" ? fg(COLORS.statusWarn) : fg(COLORS.statusMuted);
    const label = secondsSinceUpdate > 0
      ? `Last activity: ${formatElapsed(secondsSinceUpdate * 1000)} ago`
      : "Waiting for activity...";

    buf.setCell(area.x, area.y + row, { char: dot, style: dotStyle });
    buf.write(area.x + 2, area.y + row, label, dim(fg(COLORS.textSecondary)));
    row++;
  }

  // Panel-local actions hint (if focused)
  if (focused && area.height > 2) {
    const actionsRow = area.y + area.height - 1;
    const actions = isLive ? "[S]top  [R]estart" : "[R]estart";
    buf.write(area.x, actionsRow, actions, dim(fg(COLORS.accent)));
  }
}

function renderNoActiveRun(buf: ScreenBuffer, area: { x: number; y: number; width: number; height: number }): void {
  buf.write(area.x, area.y, "No active run", dim(fg(COLORS.textMuted)));
  if (area.height > 2) {
    buf.write(area.x, area.y + 2, "Select scenarios and press Enter to start", dim(fg(COLORS.textSecondary)));
  }
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

function runStatusStyle(status: Run["status"]): import("../renderer.ts").CellStyle {
  switch (status) {
    case "completed": return fg(COLORS.statusOk);
    case "running": return fg(COLORS.statusWarn);
    case "starting":
    case "stopping": return fg(COLORS.statusWarn);
    case "error": return fg(COLORS.statusErr);
  }
}

function progressBar(completed: number, total: number, width: number): string {
  if (total <= 0) return `[${"─".repeat(width)}]`;
  const filled = Math.max(0, Math.min(width, Math.round((completed / total) * width)));
  const bar = "█".repeat(filled) + "░".repeat(width - filled);
  return `[${bar}] ${completed}/${total}`;
}

function formatElapsed(ms: number): string {
  const totalSec = Math.floor(ms / 1000);
  if (totalSec < 60) return `${totalSec}s`;
  const m = Math.floor(totalSec / 60);
  const s = totalSec % 60;
  return `${m}m ${s}s`;
}

function formatDurationSec(s: number): string {
  if (s < 60) return `${s.toFixed(1)}s`;
  const m = Math.floor(s / 60);
  const sec = Math.round(s % 60);
  return `${m}m ${sec}s`;
}

function staleLevel(secondsSinceUpdate: number): "active" | "slow" | "stale" {
  if (secondsSinceUpdate < 30) return "active";
  if (secondsSinceUpdate < 90) return "slow";
  return "stale";
}

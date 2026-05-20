/**
 * Run Panel — displays active run progress, elapsed time, and activity
 *
 * @module tui/panels/run
 */

import type { RenderCommand } from "@garazyk/tui";
import {
  bold,
  COLORS,
  dim,
  fg,
  truncate,
} from "@garazyk/tui";
import type { ResolvedNode } from "@garazyk/tui";
import { panelContentArea } from "@garazyk/tui";
import type { Run } from "../../services/types.ts";
import type { RunProgress } from "../../dashboard_state.ts";

/** Render the active run panel. */
export function renderRunPanel(
  panel: ResolvedNode,
  activeRun: Run | null,
  progressByRunId: Record<string, RunProgress>,
  focused: boolean,
  logText: string | null,
): RenderCommand[] {
  const area = panelContentArea(panel);
  const clip = { x: area.x, y: area.y, width: area.width, height: area.height };
  const cmds: RenderCommand[] = [];

  if (area.height < 1 || area.width < 10) return cmds;

  if (!activeRun) {
    return renderNoActiveRun(area, focused);
  }

  const progress = progressByRunId[activeRun.id];
  const isLive = activeRun.status === "running" ||
    activeRun.status === "starting";

  let row = 0;

  // Run ID + status
  const statusBadge = runStatusBadge(activeRun.status);
  const statusStyle = runStatusStyle(activeRun.status);
  const runId = truncate(activeRun.id, 23);

  cmds.push({
    type: "text",
    x: area.x,
    y: area.y + row,
    text: statusBadge,
    style: statusStyle,
    clip,
  });
  cmds.push({
    type: "text",
    x: area.x + statusBadge.length + 1,
    y: area.y + row,
    text: runId,
    style: bold(fg(COLORS.textPrimary)),
    clip,
  });
  row++;

  // Progress bar
  if (row < area.height) {
    // Use progress.completed (from live report scanning) when available,
    // fall back to the Run object's counts (only updated on completion)
    const completed = progress?.completed ?? (activeRun.passed + activeRun.failed + activeRun.skipped);
    const total = progress?.total ?? activeRun.totalScenarios;
    const barWidth = Math.min(area.width - 12, 30);
    const bar = progressBar(completed, total, barWidth);
    cmds.push({
      type: "text",
      x: area.x,
      y: area.y + row,
      text: bar,
      style: fg(COLORS.textPrimary),
      clip,
    });
    row++;
  }

  // Pass/fail counts
  if (row < area.height) {
    const passed = activeRun.passed;
    const failed = activeRun.failed;
    const skipped = activeRun.skipped;

    let col = area.x;
    if (passed > 0 || failed === 0) {
      cmds.push({
        type: "text",
        x: col,
        y: area.y + row,
        text: `${passed} passed`,
        style: fg(COLORS.statusOk),
        clip,
      });
      col += 10;
    }
    if (failed > 0) {
      cmds.push({
        type: "text",
        x: col,
        y: area.y + row,
        text: `${failed} failed`,
        style: fg(COLORS.statusErr),
        clip,
      });
      col += 10;
    }
    if (skipped > 0) {
      cmds.push({
        type: "text",
        x: col,
        y: area.y + row,
        text: `${skipped} skipped`,
        style: fg(COLORS.statusWarn),
        clip,
      });
    }
    row++;
  }

  // Current scenario (from progress)
  if (row < area.height && progress && progress.total > 0) {
    const current = `Scenario ${
      Math.min(progress.completed + 1, progress.total)
    }/${progress.total}: ${progress.currentScenario ?? "..."}`;
    const truncated = truncate(current, area.width);
    cmds.push({
      type: "text",
      x: area.x,
      y: area.y + row,
      text: truncated,
      style: fg(COLORS.textPrimary),
      clip,
    });
    row++;
  }

  // Elapsed time
  if (row < area.height && isLive) {
    const elapsed = formatElapsed(Date.now() - activeRun.startedAt);
    cmds.push({
      type: "text",
      x: area.x,
      y: area.y + row,
      text: `Elapsed: ${elapsed}`,
      style: dim(fg(COLORS.textPrimary)),
      clip,
    });
    row++;
  }

  // Duration (for completed runs)
  if (row < area.height && !isLive && activeRun.durationS != null) {
    cmds.push({
      type: "text",
      x: area.x,
      y: area.y + row,
      text: `Duration: ${formatDurationSec(activeRun.durationS)}`,
      style: dim(fg(COLORS.textPrimary)),
      clip,
    });
    row++;
  }

  // Log tail (last few lines of log output when viewing a past run)
  if (row < area.height && logText) {
    const lines = logText.split("\n").filter((l) => l.length > 0);
    const maxLogRows = Math.max(0, area.height - row - (focused ? 1 : 0));
    const tailLines = lines.slice(-maxLogRows);
    for (const line of tailLines) {
      if (row >= area.height - (focused ? 1 : 0)) break;
      cmds.push({
        type: "text",
        x: area.x,
        y: area.y + row,
        text: truncate(line, area.width),
        style: dim(fg(COLORS.textPrimary)),
        clip,
      });
      row++;
    }
  }

  // Actions
  if (focused && row < area.height) {
    const actionsRow = area.y + area.height - 1;
    if (isLive) {
      cmds.push({
        type: "text",
        x: area.x,
        y: actionsRow,
        text: "[S]top  [R]estart",
        style: dim(fg(COLORS.accent)),
        clip,
      });
    } else {
      cmds.push({
        type: "text",
        x: area.x,
        y: actionsRow,
        text: "[R]estart",
        style: dim(fg(COLORS.accent)),
        clip,
      });
    }
  }

  return cmds;
}

function renderNoActiveRun(
  area: { x: number; y: number; width: number; height: number },
  focused: boolean,
): RenderCommand[] {
  const cmds: RenderCommand[] = [];
  const clip = { x: area.x, y: area.y, width: area.width, height: area.height };
  cmds.push({
    type: "text",
    x: area.x,
    y: area.y,
    text: "No active run",
    style: dim(fg(COLORS.textPrimary)),
    clip,
  });

  if (focused && area.height >= 2) {
    const actionsRow = area.y + area.height - 1;
    cmds.push({
      type: "text",
      x: area.x,
      y: actionsRow,
      text: "[S]tart suite  [R]estart full",
      style: dim(fg(COLORS.accent)),
      clip,
    });
  }
  return cmds;
}
function runStatusBadge(status: Run["status"]): string {
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

function runStatusStyle(
  status: Run["status"],
): import("@garazyk/tui").CellStyle {
  switch (status) {
    case "completed":
      return fg(COLORS.statusOk);
    case "running":
      return fg(COLORS.statusWarn);
    case "starting":
    case "stopping":
      return fg(COLORS.statusWarn);
    case "error":
      return fg(COLORS.statusErr);
  }
}

function progressBar(completed: number, total: number, width: number): string {
  if (total <= 0) return `[${"─".repeat(width)}]`;
  const filled = Math.max(
    0,
    Math.min(width, Math.round((completed / total) * width)),
  );
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


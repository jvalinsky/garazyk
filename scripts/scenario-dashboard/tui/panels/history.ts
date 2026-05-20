/**
 * History Panel — displays recent run history and container metrics
 *
 * Supports cursor navigation for selecting past runs.
 * All writes are clipped to the panel content area.
 *
 * @module tui/panels/history
 */

import type { CellStyle, RenderCommand } from "@garazyk/tui";
import {
  ANSI,
  bg,
  bold,
  COLORS,
  dim,
  fg,
  truncate,
} from "@garazyk/tui";
import type { ResolvedNode } from "@garazyk/tui";
import { panelContentArea } from "@garazyk/tui";
import type { PanelState } from "../panel_state.ts";
import type { Run } from "../../services/types.ts";

/** Style for the cursor highlight row — elevated surface (blue bg), default fg. */
const CURSOR_STYLE: CellStyle = { ...bg(COLORS.surfaceElevated), fg: -1 };

/** Style for the cursor highlight row text — bold default foreground on blue. */
const CURSOR_TEXT_STYLE: CellStyle = { ...bg(COLORS.surfaceElevated), fg: -1, bold: true };

/** Render the run history panel. */
export function renderHistoryPanel(
  panel: ResolvedNode,
  recentRuns: Run[],
  metrics: Record<string, { cpu: string; mem: string }>,
  panelState: PanelState,
  focused: boolean,
): RenderCommand[] {
  const area = panelContentArea(panel);
  const clip = { x: area.x, y: area.y, width: area.width, height: area.height };
  const cmds: RenderCommand[] = [];

  if (area.height < 1 || area.width < 10) return cmds;

  // Fill panel interior with surface background (subtle dark gray)
  cmds.push({
    type: "rect",
    box: { x: area.x, y: area.y, width: area.width, height: area.height },
    char: " ",
    style: bg(COLORS.surfacePanel),
    clip,
  });

  let row = 0;
  const cursor = panelState.cursor;
  const scrollOffset = panelState.scrollOffset;
  const metricsRows = hasMetrics(metrics) ? Object.keys(metrics).length + 2 : 0; // header + blank + items
  const maxRunRows = Math.max(1, area.height - metricsRows - 1); // -1 for actions

  // Recent runs
  if (recentRuns.length === 0) {
    cmds.push({
      type: "text",
      x: area.x,
      y: area.y + row,
      text: "No recorded runs",
      style: dim(fg(COLORS.textPrimary)),
      clip,
    });
  } else {
    for (let i = scrollOffset; i < recentRuns.length && row < maxRunRows; i++) {
      const run = recentRuns[i]!;
      const isCursorRow = focused && i === cursor;

      const statusBadge = runStatusBadge(run.status);
      const statusStyle = isCursorRow
        ? CURSOR_TEXT_STYLE
        : runStatusStyle(run.status);
      const runId = truncate(run.id, 20);

      // Fill cursor row with blue background
      if (isCursorRow) {
        cmds.push({
          type: "rect",
          box: { x: area.x, y: area.y + row, width: area.width, height: 1 },
          char: " ",
          style: CURSOR_STYLE,
          clip,
        });
      }

      let col = area.x;
      cmds.push({
        type: "text",
        x: col,
        y: area.y + row,
        text: statusBadge,
        style: statusStyle,
        clip,
      });
      col += statusBadge.length + 1;

      cmds.push({
        type: "text",
        x: col,
        y: area.y + row,
        text: runId,
        style: isCursorRow
          ? CURSOR_TEXT_STYLE
          : fg(COLORS.textPrimary),
        clip,
      });
      col += 21;

      // Results
      const completed = run.passed + run.failed + run.skipped;
      const results = run.failed > 0
        ? `${completed}/${run.totalScenarios}  ${run.failed} fail`
        : `${completed}/${run.totalScenarios} pass`;
      cmds.push({
        type: "text",
        x: col,
        y: area.y + row,
        text: results,
        style: isCursorRow
          ? CURSOR_TEXT_STYLE
          : (run.failed > 0 ? fg(COLORS.statusErr) : fg(COLORS.statusOk)),
        clip,
      });
      col += 14;

      // Duration
      if (run.durationS != null) {
        const dur = formatDurationSec(run.durationS);
        if (col + dur.length <= area.x + area.width) {
          cmds.push({
            type: "text",
            x: col,
            y: area.y + row,
            text: dur,
            style: isCursorRow
              ? CURSOR_TEXT_STYLE
              : dim(fg(COLORS.textPrimary)),
            clip,
          });
        }
      }

      row++;
    }
  }

  // Metrics section
  if (hasMetrics(metrics) && row + 2 < area.height) {
    row++; // blank line
    cmds.push({
      type: "text",
      x: area.x,
      y: area.y + row,
      text: "Metrics",
      style: bold(fg(COLORS.textPrimary)),
      clip,
    });
    row++;

    for (const [name, stats] of Object.entries(metrics)) {
      if (row >= area.height - (focused ? 1 : 0)) break;

      const label = name.padEnd(10);
      const cpu = `cpu: ${stats.cpu}`.padEnd(12);
      const mem = `mem: ${stats.mem}`;

      cmds.push({
        type: "text",
        x: area.x,
        y: area.y + row,
        text: label,
        style: fg(COLORS.textPrimary),
        clip,
      });
      cmds.push({
        type: "text",
        x: area.x + 11,
        y: area.y + row,
        text: cpu,
        style: dim(fg(COLORS.textPrimary)),
        clip,
      });
      if (area.x + 11 + cpu.length + mem.length <= area.x + area.width) {
        cmds.push({
          type: "text",
          x: area.x + 11 + cpu.length,
          y: area.y + row,
          text: mem,
          style: dim(fg(COLORS.textPrimary)),
          clip,
        });
      }
      row++;
    }
  }

  // Panel-local actions hint
  if (focused) {
    const actionsRow = area.y + area.height - 1;
    const actions = "[V]iew log  ↑↓ navigate";
    cmds.push({
      type: "text",
      x: area.x,
      y: actionsRow,
      text: actions,
      style: fg(COLORS.accent),
      clip,
    });
  }

  return cmds;
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
): CellStyle {
  switch (status) {
    case "completed":
      return fg(COLORS.statusOk);
    case "running":
      return fg(COLORS.badgeRunning);
    case "starting":
    case "stopping":
      return fg(COLORS.statusWarn);
    case "error":
      return fg(COLORS.statusErr);
  }
}

function formatDurationSec(s: number): string {
  if (s < 60) return `${s.toFixed(1)}s`;
  const m = Math.floor(s / 60);
  const sec = Math.round(s % 60);
  return `${m}m ${sec}s`;
}

function hasMetrics(
  metrics: Record<string, { cpu: string; mem: string }>,
): boolean {
  return Object.keys(metrics).length > 0;
}

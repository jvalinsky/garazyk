/**
 * View Layer — renders DashboardState into the ScreenBuffer
 *
 * Composes all panel renderers, the status bar, and the hint bar
 * into a single frame on the screen buffer. All rendering goes
 * through the command pipeline — no direct buffer writes.
 *
 * @module tui/view
 */

import type { RenderCommand, ScreenBuffer } from "@garazyk/tui";
import {
  bold,
  COLORS,
  DEFAULT_STYLE,
  dim,
  fg,
} from "@garazyk/tui";
import type { DashboardLayout, PanelId } from "@garazyk/tui";
import type { FocusRing } from "@garazyk/tui";
import type { PanelStates } from "./panel_state.ts";
import type { DashboardState } from "../dashboard_state.ts";
import type { Run } from "../services/types.ts";
import { renderNetworkPanel } from "./panels/network.ts";
import { renderScenariosPanel } from "./panels/scenarios.ts";
import { renderRunPanel } from "./panels/run.ts";
import { renderHistoryPanel } from "./panels/history.ts";
import { rasterize } from "@garazyk/tui";

/** Render the full dashboard view onto the screen buffer. */
export function renderView(
  buf: ScreenBuffer,
  state: DashboardState,
  layout: DashboardLayout,
  focus: FocusRing,
  panelStates: PanelStates,
  recentRuns: Run[] = [],
): void {
  buf.clear();

  const commands: RenderCommand[] = [];

  // Status bar
  commands.push(...renderStatusBar(layout.statusBar, state));

  // Hint bar
  commands.push(...renderHintBar(layout.hintBar, focus));

  // Panel borders
  for (const panel of layout.panels) {
    const isFocused = focus.isFocused(panel.id);
    const title = panelTitle(panel.id);
    commands.push({
      type: "box",
      box: { x: panel.x, y: panel.y, width: panel.width, height: panel.height },
      style: DEFAULT_STYLE,
      title,
      focused: isFocused,
    });
  }

  // Panel content
  for (const panel of layout.panels) {
    const isFocused = focus.isFocused(panel.id);
    const ps = panelStates[panel.id];
    let panelCommands: RenderCommand[] = [];
    switch (panel.id) {
      case "network":
        panelCommands = renderNetworkPanel(
          panel,
          state.network.services,
          ps,
          isFocused,
        );
        break;
      case "scenarios":
        panelCommands = renderScenariosPanel(
          panel,
          state.scenarios.all,
          state.ux.collapsedCategories,
          state.ux.searchTerm,
          ps,
          isFocused,
        );
        break;
      case "run":
        panelCommands = renderRunPanel(
          panel,
          state.runs.active,
          state.runs.progressByRunId,
          isFocused,
        );
        break;
      case "history":
        panelCommands = renderHistoryPanel(
          panel,
          recentRuns,
          state.metrics.stats,
          ps,
          isFocused,
        );
        break;
    }
    commands.push(...panelCommands);
  }

  rasterize(commands, buf);
}

/** Panel display titles. */
const TITLES: Record<PanelId, string> = {
  network: "Network",
  scenarios: "Scenarios",
  run: "Active Run",
  history: "Run History",
};

function panelTitle(id: PanelId): string {
  return TITLES[id] ?? id;
}

/** Generate render commands for the top status bar. */
function renderStatusBar(
  bar: { x: number; y: number; width: number },
  state: DashboardState,
): RenderCommand[] {
  const cmds: RenderCommand[] = [];

  // Title
  cmds.push({
    type: "text",
    x: bar.x,
    y: bar.y,
    text: " Garazyk Scenario Dashboard",
    style: bold(fg(COLORS.title)),
  });

  // Time
  const time = new Date().toLocaleTimeString();
  cmds.push({
    type: "text",
    x: bar.x + bar.width - time.length - 1,
    y: bar.y,
    text: time,
    style: dim(fg(COLORS.textSecondary)),
  });

  // Running indicator
  const runningServices =
    state.network.services.filter((s) => s.status === "running").length;
  const totalServices = state.network.services.length;
  if (totalServices > 0) {
    const svcStr = ` ${runningServices}/${totalServices} svc `;
    const svcStyle = runningServices === totalServices
      ? fg(COLORS.statusOk)
      : runningServices > 0
      ? fg(COLORS.statusWarn)
      : fg(COLORS.statusMuted);
    cmds.push({
      type: "text",
      x: bar.x + 28,
      y: bar.y,
      text: svcStr,
      style: svcStyle,
    });
  }

  return cmds;
}

/** Generate render commands for the bottom hint bar. */
function renderHintBar(
  bar: { x: number; y: number; width: number },
  focus: FocusRing,
): RenderCommand[] {
  const cmds: RenderCommand[] = [];
  const hints = [
    "1 Network",
    "2 Scenarios",
    "3 Run",
    "4 History",
    "q/Esc Quit",
    "Tab Switch",
    "Ctrl+R Refresh",
  ];

  let col = bar.x + 1;
  for (const hint of hints) {
    if (col + hint.length > bar.x + bar.width) break;

    // Highlight the currently focused panel number
    const numMatch = hint.match(/^(\d) (.+)/);
    if (numMatch) {
      const num = numMatch[1]!;
      const label = numMatch[2]!;
      const isCurrent = parseInt(num) - 1 === focus.currentIndex;
      const numStyle = isCurrent
        ? bold(fg(COLORS.accent))
        : dim(fg(COLORS.textMuted));
      const labelStyle = isCurrent
        ? fg(COLORS.textPrimary)
        : dim(fg(COLORS.textMuted));

      cmds.push({ type: "text", x: col, y: bar.y, text: num, style: numStyle });
      cmds.push({
        type: "text",
        x: col + 1,
        y: bar.y,
        text: ` ${label}`,
        style: labelStyle,
      });
      col += hint.length + 2;
    } else {
      cmds.push({
        type: "text",
        x: col,
        y: bar.y,
        text: hint,
        style: dim(fg(COLORS.textMuted)),
      });
      col += hint.length + 2;
    }
  }

  return cmds;
}

/**
 * View Layer — renders DashboardState into the ScreenBuffer
 *
 * Composes all panel renderers, the status bar, and the hint bar
 * into a single frame on the screen buffer.
 *
 * @module tui/view
 */

import type { ScreenBuffer, CellStyle } from "@garazyk/tui";
import { DEFAULT_STYLE, COLORS, ANSI, bold, dim, fg, reverse } from "@garazyk/tui";
import type { DashboardLayout, PanelId } from "@garazyk/tui";
import { findPanel } from "@garazyk/tui";
import type { FocusRing } from "@garazyk/tui";
import type { PanelStates } from "./panel_state.ts";
import type { DashboardState } from "../dashboard_state.ts";
import type { Run } from "../services/types.ts";
import { renderNetworkPanel } from "./panels/network.ts";
import { renderScenariosPanel } from "./panels/scenarios.ts";
import { renderRunPanel } from "./panels/run.ts";
import { renderHistoryPanel } from "./panels/history.ts";

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

  // Status bar
  renderStatusBar(buf, layout.statusBar, state);

  // Hint bar
  renderHintBar(buf, layout.hintBar, focus);

  // Panel borders
  for (const panel of layout.panels) {
    const isFocused = focus.isFocused(panel.id);
    buf.box(panel.x, panel.y, panel.width, panel.height, DEFAULT_STYLE, isFocused);

    // Panel title
    const title = panelTitle(panel.id);
    buf.boxTitle(panel.x, panel.y, panel.width, title, DEFAULT_STYLE);
  }

  // Panel content
  for (const panel of layout.panels) {
    const isFocused = focus.isFocused(panel.id);
    const ps = panelStates[panel.id];
    switch (panel.id) {
      case "network":
        renderNetworkPanel(buf, panel, state.network.services, ps, isFocused);
        break;
      case "scenarios":
        renderScenariosPanel(
          buf,
          panel,
          state.scenarios.all,
          state.ux.collapsedCategories,
          state.ux.searchTerm,
          ps,
          isFocused,
        );
        break;
      case "run":
        renderRunPanel(buf, panel, state.runs.active, state.runs.progressByRunId, isFocused);
        break;
      case "history":
        renderHistoryPanel(buf, panel, recentRuns, state.metrics.stats, ps, isFocused);
        break;
    }
  }
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

/** Render the top status bar. */
function renderStatusBar(
  buf: ScreenBuffer,
  bar: { x: number; y: number; width: number },
  state: DashboardState,
): void {
  // Title
  const title = bold(fg(COLORS.title));
  buf.write(bar.x, bar.y, " Garazyk Scenario Dashboard", title);

  // Time
  const time = new Date().toLocaleTimeString();
  const timeStr = time.padStart(bar.width - 30);
  buf.write(bar.x + bar.width - time.length - 1, bar.y, time, dim(fg(COLORS.textSecondary)));

  // Running indicator
  const runningServices = state.network.services.filter((s) => s.status === "running").length;
  const totalServices = state.network.services.length;
  if (totalServices > 0) {
    const svcStr = ` ${runningServices}/${totalServices} svc `;
    const svcStyle = runningServices === totalServices
      ? fg(COLORS.statusOk)
      : runningServices > 0
      ? fg(COLORS.statusWarn)
      : fg(COLORS.statusMuted);
    buf.write(bar.x + 28, bar.y, svcStr, svcStyle);
  }
}

/** Render the bottom hint bar. */
function renderHintBar(
  buf: ScreenBuffer,
  bar: { x: number; y: number; width: number },
  focus: FocusRing,
): void {
  const hints = [
    "1 Network",
    "2 Scenarios",
    "3 Run",
    "4 History",
    "q/Esc Quit",
    "Tab Switch",
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
      const numStyle = isCurrent ? bold(fg(COLORS.accent)) : dim(fg(COLORS.textMuted));
      const labelStyle = isCurrent ? fg(COLORS.textPrimary) : dim(fg(COLORS.textMuted));

      buf.write(col, bar.y, num, numStyle);
      buf.write(col + 1, bar.y, ` ${label}`, labelStyle);
      col += hint.length + 2;
    } else {
      buf.write(col, bar.y, hint, dim(fg(COLORS.textMuted)));
      col += hint.length + 2;
    }
  }
}

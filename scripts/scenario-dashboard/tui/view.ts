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
  bg,
  bold,
  COLORS,
  DEFAULT_STYLE,
  dim,
  fg,
} from "@garazyk/tui";
import type { PanelId, ResolvedNode } from "@garazyk/tui";
import type { FocusRing } from "@garazyk/tui";
import { findPanel } from "@garazyk/tui";
import type { PanelStates } from "./panel_state.ts";
import type { DashboardState } from "../dashboard_state.ts";
import type { Run } from "../services/types.ts";
import { renderNetworkPanel } from "./panels/network.ts";
import { renderScenariosPanel } from "./panels/scenarios.ts";
import { renderRunPanel } from "./panels/run.ts";
import { renderHistoryPanel } from "./panels/history.ts";
import { renderRunDetailOverlay } from "./panels/run_detail.ts";
import { rasterize } from "@garazyk/tui";

/** Panel IDs in the order they appear in the layout tree. */
const PANEL_IDS: PanelId[] = ["network", "scenarios", "run", "history"];

/** Render the full dashboard view onto the screen buffer. */
export function renderView(
  buf: ScreenBuffer,
  state: DashboardState,
  layout: ResolvedNode,
  focus: FocusRing,
  panelStates: PanelStates,
  recentRuns: Run[] = [],
  helpOverlay = false,
): void {
  buf.clear();

  const commands: RenderCommand[] = [];

  // Base background — fill the entire screen with the deepest surface.
  // This ensures empty areas between panels have a consistent dark
  // background instead of the terminal's default (which may differ).
  commands.push({
    type: "rect",
    box: { x: 0, y: 0, width: buf.width, height: buf.height },
    char: " ",
    style: bg(COLORS.surfaceBase),
  });

  // Status bar
  const statusBar = findPanel(layout, "status-bar");
  if (statusBar) {
    commands.push(...renderStatusBar(statusBar, state));
  }

  // Hint bar
  const hintBar = findPanel(layout, "hint-bar");
  if (hintBar) {
    commands.push(...renderHintBar(hintBar, focus));
  }

  // Panel borders
  for (const panelId of PANEL_IDS) {
    const panel = findPanel(layout, panelId);
    if (!panel) continue;
    const isFocused = focus.isFocused(panelId);
    const title = panelTitle(panelId);
    commands.push({
      type: "box",
      box: { x: panel.x, y: panel.y, width: panel.width, height: panel.height },
      style: DEFAULT_STYLE,
      title,
      focused: isFocused,
    });
  }

  // Panel content
  for (const panelId of PANEL_IDS) {
    const panel = findPanel(layout, panelId);
    if (!panel) continue;
    const isFocused = focus.isFocused(panelId);
    const ps = panelStates[panelId];
    let panelCommands: RenderCommand[] = [];
    switch (panelId) {
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
      case "run": {
        // Show log text for the viewed run (if any)
        const viewedId = state.runs.viewedRunId;
        const logText = viewedId ? (state.logs.textByRunId[viewedId] ?? null) : null;
        panelCommands = renderRunPanel(
          panel,
          state.runs.active,
          state.runs.progressByRunId,
          isFocused,
          logText,
        );
        break;
      }
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

  // Help overlay — rendered on top of the normal view
  if (helpOverlay) {
    renderHelpOverlay(buf);
  }

  // Run detail overlay — rendered on top of everything
  if (state.runs.detailRunId && state.runs.detailRun) {
    renderRunDetailOverlay(
      buf,
      state.runs.detailRun,
      state.runs.detailResults,
      state.runs.detailCursor,
      state.runs.detailScrollOffset,
    );
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

/** Generate render commands for the top status bar. */
function renderStatusBar(
  bar: ResolvedNode,
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
    style: dim(fg(COLORS.textPrimary)),
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

/** Panel-specific keybinding hints for the context-sensitive hint bar. */
const PANEL_HINTS: Record<PanelId, string[]> = {
  network: ["s Start", "p PDS2", "x Stop"],
  scenarios: ["/ Filter", "Space Toggle", "Enter Run"],
  run: ["s Stop", "r Restart"],
  history: ["r Restart", "v View log"],
};

/** Global hints shown at the end of the hint bar regardless of focused panel. */
const GLOBAL_HINTS = ["1-4 Panel", "Tab Switch", "q Quit"];

/** Generate render commands for the bottom hint bar. Shows context-sensitive hints based on the focused panel. */
function renderHintBar(
  bar: ResolvedNode,
  focus: FocusRing,
): RenderCommand[] {
  const cmds: RenderCommand[] = [];
  const panel = focus.current;
  const panelHints = PANEL_HINTS[panel] ?? [];

  // Build the full hint list: panel-specific first, then global
  const hints: string[] = [...panelHints, ...GLOBAL_HINTS];

  let col = bar.x + 1;
  for (const hint of hints) {
    // Split hint into key part and label part
    const spaceIdx = hint.indexOf(" ");
    const key = spaceIdx > 0 ? hint.slice(0, spaceIdx) : hint;
    const label = spaceIdx > 0 ? hint.slice(spaceIdx + 1) : "";
    const fullLen = hint.length;

    if (col + fullLen > bar.x + bar.width) break;

    // Key is highlighted, label is muted
    cmds.push({
      type: "text",
      x: col,
      y: bar.y,
      text: key,
      style: bold(fg(COLORS.accent)),
    });
    if (label) {
      cmds.push({
        type: "text",
        x: col + key.length,
        y: bar.y,
        text: ` ${label}`,
        style: dim(fg(COLORS.textPrimary)),
      });
    }
    col += fullLen + 2; // +2 for spacing between hints
  }

  return cmds;
}

// ---------------------------------------------------------------------------
// Help overlay
// ---------------------------------------------------------------------------

/** Keybinding sections for the help overlay. */
const HELP_SECTIONS: Array<{ title: string; bindings: Array<{ key: string; action: string }> }> = [
  {
    title: "Global",
    bindings: [
      { key: "1-4", action: "Jump to panel" },
      { key: "Tab", action: "Switch panel" },
      { key: "?", action: "Toggle help" },
      { key: "q / Esc", action: "Quit" },
      { key: "Ctrl+R", action: "Refresh" },
    ],
  },
  {
    title: "Network",
    bindings: [
      { key: "s", action: "Start network" },
      { key: "p", action: "Start with PDS2" },
      { key: "x", action: "Stop network" },
    ],
  },
  {
    title: "Scenarios",
    bindings: [
      { key: "/", action: "Filter" },
      { key: "Space", action: "Toggle category" },
      { key: "Enter", action: "Run scenario/category" },
    ],
  },
  {
    title: "Run",
    bindings: [
      { key: "s", action: "Stop run" },
      { key: "r", action: "Restart run" },
    ],
  },
  {
    title: "History",
    bindings: [
      { key: "r", action: "Restart run" },
      { key: "v", action: "View log" },
    ],
  },
];

/** Render a full-screen help overlay on top of the current buffer content. */
function renderHelpOverlay(buf: ScreenBuffer): void {
  const overlayStyle = bg(COLORS.surfaceBase);
  const titleStyle = bold(fg(COLORS.accent));
  const keyStyle = bold(fg(COLORS.accent));
  const actionStyle = dim(fg(COLORS.textPrimary));

  // Calculate content dimensions
  let maxBindingWidth = 0;
  let totalRows = 0; // content rows (not counting border)
  for (const section of HELP_SECTIONS) {
    totalRows += 1; // section title
    for (const binding of section.bindings) {
      const line = `  ${binding.key.padEnd(8)} ${binding.action}`;
      if (line.length > maxBindingWidth) maxBindingWidth = line.length;
      totalRows++;
    }
    totalRows += 1; // blank line between sections
  }
  totalRows += 1; // "Press any key" footer

  const boxWidth = Math.min(maxBindingWidth + 4, buf.width - 2); // +4 for padding and border
  const boxHeight = Math.min(totalRows + 2, buf.height - 2); // +2 for border
  const boxX = Math.floor((buf.width - boxWidth) / 2);
  const boxY = Math.floor((buf.height - boxHeight) / 2);

  // Fill the entire screen with dark background
  buf.fillRect(0, 0, buf.width, buf.height, " ", overlayStyle);

  // Draw the help box border
  buf.box(boxX, boxY, boxWidth, boxHeight, overlayStyle, false);
  buf.boxTitle(boxX, boxY, boxWidth, "Help", overlayStyle);

  // Render content inside the box
  let row = boxY + 1; // start inside the top border
  const maxRow = boxY + boxHeight - 2; // stay inside the bottom border
  const contentX = boxX + 2; // left padding inside border
  const contentWidth = boxWidth - 4; // usable width inside border

  for (const section of HELP_SECTIONS) {
    if (row > maxRow) break;

    // Section title
    buf.writeClipped(contentX, row, section.title, titleStyle, {
      x: boxX + 1,
      y: boxY + 1,
      width: boxWidth - 2,
      height: boxHeight - 2,
    });
    row++;

    // Keybindings
    for (const binding of section.bindings) {
      if (row > maxRow) break;
      const keyText = `  ${binding.key}`.padEnd(10);
      buf.writeClipped(contentX, row, keyText, keyStyle, {
        x: boxX + 1,
        y: boxY + 1,
        width: boxWidth - 2,
        height: boxHeight - 2,
      });
      buf.writeClipped(contentX + 10, row, binding.action, actionStyle, {
        x: boxX + 1,
        y: boxY + 1,
        width: boxWidth - 2,
        height: boxHeight - 2,
      });
      row++;
    }

    // Blank line between sections
    row++;
  }

  // Footer
  if (row <= maxRow) {
    buf.writeClipped(contentX, row, "Press any key to close", dim(fg(COLORS.textPrimary)), {
      x: boxX + 1,
      y: boxY + 1,
      width: boxWidth - 2,
      height: boxHeight - 2,
    });
  }
}

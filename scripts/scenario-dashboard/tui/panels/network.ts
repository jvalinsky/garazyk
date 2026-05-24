/**
 * Network Panel — displays ATProto service status table
 *
 * Supports cursor navigation and per-service actions.
 * All writes are clipped to the panel content area.
 *
 * @module tui/panels/network
 */

import type { CellStyle, RenderCommand } from "@garazyk/tui";
import { bg, bold, COLORS, dim, fg } from "@garazyk/tui";
import type { ResolvedNode } from "@garazyk/tui";
import { panelContentArea } from "@garazyk/tui";
import type { PanelState } from "../panel_state.ts";
import type { ServiceStatus } from "../../services/types.ts";

/** Style for the cursor highlight row — elevated surface (blue bg), default fg. */
const CURSOR_STYLE: CellStyle = { ...bg(COLORS.surfaceElevated), fg: -1 };

/** Style for the cursor highlight row text — bold default foreground on blue. */
const CURSOR_TEXT_STYLE: CellStyle = {
  ...bg(COLORS.surfaceElevated),
  fg: -1,
  bold: true,
};

/** Render the network services panel. */
export function renderNetworkPanel(
  panel: ResolvedNode,
  services: ServiceStatus[],
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

  // Service list
  if (services.length === 0) {
    cmds.push({
      type: "text",
      x: area.x,
      y: area.y + row,
      text: "No services discovered",
      style: dim(fg(COLORS.textSecondary)),
      clip,
    });
    return cmds;
  }

  const scrollOffset = panelState.scrollOffset;
  const cursor = panelState.cursor;

  for (
    let i = scrollOffset;
    i < services.length && row < area.height - 1;
    i++
  ) {
    const svc = services[i]!;
    const isCursorRow = focused && i === cursor;

    // Status dot
    const dot = statusDot(svc.status, svc.healthy);
    const dotStyle = isCursorRow
      ? CURSOR_TEXT_STYLE
      : statusDotStyle(svc.status, svc.healthy);

    // Name
    const name = (svc.label || svc.name).padEnd(12);

    // Status badge
    const badge = statusBadge(svc.status, svc.healthy);
    const badgeStyle = isCursorRow
      ? CURSOR_TEXT_STYLE
      : statusBadgeStyle(svc.status, svc.healthy);

    // Endpoint
    const endpoint = svc.url || "";

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
      text: dot,
      style: dotStyle,
      clip,
    });
    col += 2;
    cmds.push({
      type: "text",
      x: col,
      y: area.y + row,
      text: name,
      style: isCursorRow ? CURSOR_TEXT_STYLE : bold(fg(COLORS.textPrimary)),
      clip,
    });
    col += 12;
    cmds.push({
      type: "text",
      x: col,
      y: area.y + row,
      text: badge,
      style: badgeStyle,
      clip,
    });
    col += badge.length + 1;

    if (col + endpoint.length <= area.x + area.width) {
      cmds.push({
        type: "text",
        x: col,
        y: area.y + row,
        text: endpoint,
        style: isCursorRow ? CURSOR_TEXT_STYLE : dim(fg(COLORS.textSecondary)),
        clip,
      });
    }

    row++;
  }

  // Panel-local actions hint
  if (focused) {
    const actionsRow = area.y + area.height - 1;
    const actions = "[S]tart  [P]ds2  [X]stop  ↑↓ navigate";
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

/** Get the selected service, or null if no services. */
export function getSelectedService(
  services: ServiceStatus[],
  panelState: PanelState,
): ServiceStatus | null {
  return services[panelState.cursor] ?? null;
}

function statusDot(status: ServiceStatus["status"], healthy?: boolean): string {
  if (status === "running" && healthy !== false) return "●";
  if (status === "running" && healthy === false) return "◐";
  if (status === "starting") return "◐";
  if (status === "error") return "✖";
  return "○";
}

function statusDotStyle(
  status: ServiceStatus["status"],
  healthy?: boolean,
): CellStyle {
  if (status === "running" && healthy !== false) return fg(COLORS.statusOk);
  if (status === "running" && healthy === false) return fg(COLORS.statusWarn);
  if (status === "starting") return fg(COLORS.statusWarn);
  if (status === "error") return fg(COLORS.statusErr);
  return fg(COLORS.statusMuted);
}

function statusBadge(
  status: ServiceStatus["status"],
  healthy?: boolean,
): string {
  if (status === "running" && healthy !== false) return " ok ";
  if (status === "running" && healthy === false) return " ?? ";
  if (status === "starting") return " .. ";
  if (status === "error") return " !! ";
  return " -- ";
}

function statusBadgeStyle(
  status: ServiceStatus["status"],
  healthy?: boolean,
): CellStyle {
  if (status === "running" && healthy !== false) return fg(COLORS.statusOk);
  if (status === "running" && healthy === false) return fg(COLORS.statusWarn);
  if (status === "starting") return fg(COLORS.statusWarn);
  if (status === "error") return fg(COLORS.statusErr);
  return fg(COLORS.statusMuted);
}

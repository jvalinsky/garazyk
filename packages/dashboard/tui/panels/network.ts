/**
 * Network Panel — displays ATProto service status table
 *
 * Supports cursor navigation and per-service actions.
 * All writes are clipped to the panel content area.
 *
 * @module tui/panels/network
 */

import type { ScreenBuffer, CellStyle } from "../renderer.ts";
import { DEFAULT_STYLE, COLORS, ANSI, bold, dim, fg, reverse } from "../renderer.ts";
import type { PanelLayout } from "../layout.ts";
import { panelContentArea } from "../layout.ts";
import type { PanelState } from "../panel_state.ts";
import type { ServiceStatus } from "../../services/types.ts";

/** Render the network services panel. */
export function renderNetworkPanel(
  buf: ScreenBuffer,
  panel: PanelLayout,
  services: ServiceStatus[],
  panelState: PanelState,
  focused: boolean,
): void {
  const area = panelContentArea(panel);

  if (area.height < 1 || area.width < 10) return;

  let row = 0;

  // Service list
  if (services.length === 0) {
    buf.writeClipped(area.x, area.y + row, "No services discovered", dim(fg(COLORS.textMuted)), area);
    return;
  }

  const scrollOffset = panelState.scrollOffset;
  const cursor = panelState.cursor;

  for (let i = scrollOffset; i < services.length && row < area.height - 1; i++) {
    const svc = services[i]!;
    const isCursorRow = focused && i === cursor;

    // Status dot
    const dot = statusDot(svc.status, svc.healthy);
    const dotStyle = isCursorRow ? reverse(fg(COLORS.accent)) : statusDotStyle(svc.status, svc.healthy);

    // Name
    const name = (svc.label || svc.name).padEnd(12);

    // Status badge
    const badge = statusBadge(svc.status, svc.healthy);
    const badgeStyle = isCursorRow ? reverse(fg(COLORS.accent)) : statusBadgeStyle(svc.status, svc.healthy);

    // Endpoint
    const endpoint = svc.url || (svc.port ? `localhost:${svc.port}` : "");

    // Render — clear row first if cursor for clean highlight
    if (isCursorRow) {
      buf.fillRect(area.x, area.y + row, area.width, 1, " ", reverse(fg(COLORS.accent)));
    }

    let col = area.x;
    buf.writeClipped(col, area.y + row, dot, dotStyle, area);
    col += 2;
    buf.writeClipped(col, area.y + row, name, isCursorRow ? reverse(fg(COLORS.accent)) : bold(fg(COLORS.textPrimary)), area);
    col += 12;
    buf.writeClipped(col, area.y + row, badge, badgeStyle, area);
    col += badge.length + 1;

    if (col + endpoint.length <= area.x + area.width) {
      buf.writeClipped(col, area.y + row, endpoint, isCursorRow ? reverse(fg(COLORS.accent)) : dim(fg(COLORS.textSecondary)), area);
    }

    row++;
  }

  // Panel-local actions hint
  if (focused) {
    const actionsRow = area.y + area.height - 1;
    const actions = "[S]tart  [P]ds2  [X]stop  ↑↓ navigate";
    buf.writeClipped(area.x, actionsRow, actions, dim(fg(COLORS.accent)), area);
  }
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

function statusDotStyle(status: ServiceStatus["status"], healthy?: boolean): CellStyle {
  if (status === "running" && healthy !== false) return fg(COLORS.statusOk);
  if (status === "running" && healthy === false) return fg(COLORS.statusWarn);
  if (status === "starting") return fg(COLORS.statusWarn);
  if (status === "error") return fg(COLORS.statusErr);
  return fg(COLORS.statusMuted);
}

function statusBadge(status: ServiceStatus["status"], healthy?: boolean): string {
  if (status === "running" && healthy !== false) return " ok ";
  if (status === "running" && healthy === false) return " ?? ";
  if (status === "starting") return " .. ";
  if (status === "error") return " !! ";
  return " -- ";
}

function statusBadgeStyle(status: ServiceStatus["status"], healthy?: boolean): CellStyle {
  if (status === "running" && healthy !== false) return fg(COLORS.statusOk);
  if (status === "running" && healthy === false) return fg(COLORS.statusWarn);
  if (status === "starting") return fg(COLORS.statusWarn);
  if (status === "error") return fg(COLORS.statusErr);
  return fg(COLORS.statusMuted);
}

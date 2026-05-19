/**
 * Scenarios Panel — displays scenario categories, coverage, and filter
 *
 * Supports collapsible categories, cursor navigation, and search filter.
 * All writes are clipped to the panel content area to prevent overflow.
 *
 * @module tui/panels/scenarios
 */

import type { CellStyle, RenderCommand } from "@garazyk/tui";
import {
  bold,
  COLORS,
  dim,
  fg,
  reverse,
  truncate,
} from "@garazyk/tui";
import type { PanelLayout } from "@garazyk/tui";
import { panelContentArea } from "@garazyk/tui";
import type { PanelState } from "../panel_state.ts";
import type { ScenarioMeta } from "../../dashboard_state.ts";
import { categorize } from "../../utils.ts";

/** Category display names and sort order. */
const CATEGORIES: Record<string, string> = {
  core: "Core ATProto",
  identity: "UI & Identity",
  scale: "Scale & AppView",
  edge: "Edge Cases",
};

const CATEGORY_ORDER = ["core", "identity", "scale", "edge"];

/** A flat list item — either a category header or a scenario row. */
interface FlatItem {
  type: "category" | "scenario";
  key: string; // category key or scenario id
  label: string;
  statusDot: string;
  statusStyle: CellStyle;
  isCollapsed: boolean;
  count: number;
}

/** Build a flat list of items from the grouped scenarios. */
function buildFlatItems(
  grouped: Record<string, ScenarioMeta[]>,
  collapsedCategories: Set<string>,
): FlatItem[] {
  const items: FlatItem[] = [];

  for (const catKey of CATEGORY_ORDER) {
    const list = grouped[catKey] || [];
    const isCollapsed = collapsedCategories.has(catKey);
    const label = CATEGORIES[catKey] || catKey;

    items.push({
      type: "category",
      key: catKey,
      label,
      statusDot: isCollapsed ? "▶" : "▼",
      statusStyle: bold(fg(COLORS.textPrimary)),
      isCollapsed,
      count: list.length,
    });

    if (!isCollapsed) {
      for (const sc of list) {
        items.push({
          type: "scenario",
          key: sc.id,
          label: sc.id + " " + sc.name,
          statusDot: scenarioStatusDot(sc.lastStatus),
          statusStyle: scenarioStatusStyle(sc.lastStatus),
          isCollapsed: false,
          count: 0,
        });
      }
    }
  }

  return items;
}

/** Render the scenarios panel. */
export function renderScenariosPanel(
  panel: PanelLayout,
  scenarios: ScenarioMeta[],
  collapsedCategories: Set<string>,
  searchTerm: string,
  panelState: PanelState,
  focused: boolean,
): RenderCommand[] {
  const area = panelContentArea(panel);
  const clip = { x: area.x, y: area.y, width: area.width, height: area.height };
  const cmds: RenderCommand[] = [];

  if (area.height < 1 || area.width < 10) return cmds;

  // Group scenarios by category
  const grouped: Record<string, ScenarioMeta[]> = {};
  for (const sc of scenarios) {
    const cat = categorize(sc.id);
    if (!grouped[cat]) grouped[cat] = [];
    grouped[cat].push(sc);
  }

  // Filter by search term
  const filtered: Record<string, ScenarioMeta[]> = {};
  for (const [cat, list] of Object.entries(grouped)) {
    filtered[cat] = searchTerm
      ? list.filter((s) =>
        s.id.includes(searchTerm) ||
        s.name.toLowerCase().includes(searchTerm.toLowerCase())
      )
      : list;
  }

  // Build flat list of items
  const items = buildFlatItems(filtered, collapsedCategories);

  let row = 0;

  // Search indicator
  if (searchTerm) {
    cmds.push({
      type: "text",
      x: area.x,
      y: area.y + row,
      text: `/${searchTerm}█`,
      style: fg(COLORS.accent),
      clip,
    });
    row++;
  }

  // Render items with scroll offset
  const scrollOffset = panelState.scrollOffset;
  const cursor = panelState.cursor;

  for (let i = scrollOffset; i < items.length && row < area.height - 1; i++) {
    const item = items[i]!;
    const isCursorRow = focused && i === cursor;

    // Highlight style for cursor row
    const rowStyle = isCursorRow ? reverse(fg(COLORS.accent)) : undefined;

    if (item.type === "category") {
      const header = `${item.statusDot} ${item.label} (${item.count})`;
      const style = isCursorRow ? rowStyle! : bold(fg(COLORS.textPrimary));
      cmds.push({
        type: "text",
        x: area.x,
        y: area.y + row,
        text: header,
        style,
        clip,
      });
    } else {
      // Scenario row
      const dotStyle = isCursorRow ? rowStyle! : item.statusStyle;
      const nameStyle = isCursorRow ? rowStyle! : fg(COLORS.textPrimary);
      const name = truncate(item.label, area.width - 4);

      // Clear the row first for clean reverse-video highlight
      if (isCursorRow) {
        cmds.push({
          type: "rect",
          box: { x: area.x, y: area.y + row, width: area.width, height: 1 },
          char: " ",
          style: rowStyle!,
          clip,
        });
      }

      cmds.push({
        type: "text",
        x: area.x,
        y: area.y + row,
        text: item.statusDot,
        style: dotStyle,
        clip,
      });
      cmds.push({
        type: "text",
        x: area.x + 2,
        y: area.y + row,
        text: name,
        style: nameStyle,
        clip,
      });
    }

    row++;
  }

  // Summary line
  const summaryRow = area.y + area.height - 1;
  if (focused) {
    const actions = "[Enter] run  [/] filter  [Space] toggle";
    cmds.push({
      type: "text",
      x: area.x,
      y: summaryRow,
      text: actions,
      style: dim(fg(COLORS.accent)),
      clip,
    });
  } else {
    const total = scenarios.length;
    const passed = scenarios.filter((s) => s.lastStatus === "passed").length;
    const pct = total > 0 ? Math.round((passed / total) * 100) : 0;
    const summary = `Total: ${total}  Last: ${pct}% pass`;
    cmds.push({
      type: "text",
      x: area.x,
      y: summaryRow,
      text: summary,
      style: dim(fg(COLORS.textSecondary)),
      clip,
    });
  }

  return cmds;
}

/** Get the flat item count for the scenarios panel. */
export function getScenariosItemCount(
  scenarios: ScenarioMeta[],
  collapsedCategories: Set<string>,
  searchTerm: string,
): number {
  const grouped: Record<string, ScenarioMeta[]> = {};
  for (const sc of scenarios) {
    const cat = categorize(sc.id);
    if (!grouped[cat]) grouped[cat] = [];
    grouped[cat].push(sc);
  }
  const filtered: Record<string, ScenarioMeta[]> = {};
  for (const [cat, list] of Object.entries(grouped)) {
    filtered[cat] = searchTerm
      ? list.filter((s) =>
        s.id.includes(searchTerm) ||
        s.name.toLowerCase().includes(searchTerm.toLowerCase())
      )
      : list;
  }
  return buildFlatItems(filtered, collapsedCategories).length;
}

/** Get the flat item at a given index. Returns null if out of bounds. */
export function getScenariosItemAt(
  scenarios: ScenarioMeta[],
  collapsedCategories: Set<string>,
  searchTerm: string,
  index: number,
): FlatItem | null {
  const grouped: Record<string, ScenarioMeta[]> = {};
  for (const sc of scenarios) {
    const cat = categorize(sc.id);
    if (!grouped[cat]) grouped[cat] = [];
    grouped[cat].push(sc);
  }
  const filtered: Record<string, ScenarioMeta[]> = {};
  for (const [cat, list] of Object.entries(grouped)) {
    filtered[cat] = searchTerm
      ? list.filter((s) =>
        s.id.includes(searchTerm) ||
        s.name.toLowerCase().includes(searchTerm.toLowerCase())
      )
      : list;
  }
  const items = buildFlatItems(filtered, collapsedCategories);
  return items[index] ?? null;
}

function scenarioStatusDot(status?: string | null): string {
  switch (status) {
    case "passed":
      return "●";
    case "failed":
      return "✖";
    case "skipped":
      return "○";
    default:
      return "○";
  }
}

function scenarioStatusStyle(status?: string | null): CellStyle {
  switch (status) {
    case "passed":
      return fg(COLORS.statusOk);
    case "failed":
      return fg(COLORS.statusErr);
    case "skipped":
      return fg(COLORS.statusWarn);
    default:
      return fg(COLORS.statusMuted);
  }
}

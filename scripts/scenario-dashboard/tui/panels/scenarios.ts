/**
 * Scenarios Panel — displays scenario categories, coverage, and filter
 *
 * Supports collapsible categories, cursor navigation, and search filter.
 * All writes are clipped to the panel content area to prevent overflow.
 *
 * Surface hierarchy (background shades create visual depth):
 * - surfaceBase (BLACK): app background, not used inside panels
 * - surfacePanel (BRIGHT_BLACK): subtle dark gray fills the panel interior
 * - surfaceElevated (BLUE): cursor highlight row
 *
 * The description preview row uses surfacePanel background with default
 * terminal foreground — the background tint creates visual hierarchy
 * without needing a special foreground color.
 *
 * @module tui/panels/scenarios
 */

import type { CellStyle, RenderCommand } from "@garazyk/tui";
import {
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
import type { ScenarioMeta } from "../../dashboard_state.ts";
import { categorize } from "../../utils.ts";
import type { ElementMeta } from "../../tui_types.ts";

/** Category display names and sort order. */
const CATEGORIES: Record<string, string> = {
  core: "Core ATProto",
  identity: "UI & Identity",
  scale: "Scale & AppView",
  edge: "Edge Cases",
};

const CATEGORY_ORDER = ["core", "identity", "scale", "edge"];

/** Style for the cursor highlight row — elevated surface (blue bg), default fg. */
const CURSOR_STYLE: CellStyle = { ...bg(COLORS.surfaceElevated), fg: -1 };

/** Style for the cursor highlight row text — bold default foreground on blue. */
const CURSOR_TEXT_STYLE: CellStyle = { ...bg(COLORS.surfaceElevated), fg: -1, bold: true };

/** A flat list item — either a category header or a scenario row. */
interface FlatItem {
  type: "category" | "scenario";
  key: string; // category key or scenario id
  label: string;
  description: string; // one-line description for scenarios, empty for categories
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
      description: "",
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
          description: sc.description,
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
  panel: ResolvedNode,
  scenarios: ScenarioMeta[],
  collapsedCategories: Set<string>,
  searchTerm: string,
  panelState: PanelState,
  focused: boolean,
  meta?: Map<string, ElementMeta>,
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

  // Reserve 2 rows at the bottom: description preview + summary line
  const bottomReserved = focused ? 2 : 1;
  const listHeight = area.height - bottomReserved;

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

  // Track the description of the cursor item for the preview area
  let cursorDescription = "";

  for (let i = scrollOffset; i < items.length && row < listHeight; i++) {
    const item = items[i]!;
    const isCursorRow = focused && i === cursor;

    if (isCursorRow && item.description) {
      cursorDescription = item.description;
    }

    if (item.type === "category") {
      const header = `${item.statusDot} ${item.label} (${item.count})`;
      const style = isCursorRow ? CURSOR_TEXT_STYLE : bold(fg(COLORS.textPrimary));

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

      cmds.push({
        type: "text",
        x: area.x,
        y: area.y + row,
        text: header,
        style,
        clip,
      });

      if (meta) {
        meta.set(`category.${item.key}`, {
          role: "heading",
          interactable: true,
          focused: isCursorRow,
          states: item.isCollapsed ? ["collapsed"] : ["expanded"],
          bounds: { x: area.x, y: area.y + row, width: area.width, height: 1 },
          ref: `category.${item.key}`,
          label: item.label,
          actions: ["space", "click", "enter"],
        });
      }
    } else {
      // Scenario row
      const dotStyle = isCursorRow ? CURSOR_TEXT_STYLE : item.statusStyle;
      const nameStyle = isCursorRow ? CURSOR_TEXT_STYLE : fg(COLORS.textPrimary);
      const name = truncate(item.label, area.width - 4);

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

      if (meta) {
        meta.set(`scenario.${item.key}`, {
          role: "scenario",
          interactable: true,
          focused: isCursorRow,
          states: [item.statusDot === "●" ? "passed" : item.statusDot === "✖" ? "failed" : item.statusDot === "○" ? "skipped" : "pending"],
          bounds: { x: area.x, y: area.y + row, width: area.width, height: 1 },
          ref: `scenario.${item.key}`,
          label: item.label,
          actions: ["enter", "click"],
        });
      }
    }

    row++;
  }

  // Description preview area — 1 row above the summary line
  // Uses default terminal foreground on the panel surface background.
  // The background tint creates visual hierarchy — no need for a special
  // foreground color. The description is visually distinct because it
  // sits on the same surfacePanel background as the rest of the panel,
  // but separated from the list by empty space.
  const descRow = area.y + area.height - 2;
  if (focused && cursorDescription) {
    const descText = truncate(cursorDescription, area.width - 2);
    cmds.push({
      type: "text",
      x: area.x + 1,
      y: descRow,
      text: descText,
      style: dim(fg(COLORS.textSecondary)),
      clip,
    });
  } else if (focused) {
    // Clear the description row when no scenario is selected
    // (already filled by the panel background rect above)
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
      style: fg(COLORS.accent),
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

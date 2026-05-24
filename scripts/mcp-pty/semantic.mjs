import path from "node:path";

// ── Constants ────────────────────────────────────────────────────────────

/** Unicode ranges for box-drawing characters used by TUI frameworks. */
const BOX_DRAWING = new Set([
  "┌","┐","└","┘","├","┤","┬","┴","┼",
  "─","│",
  "╭","╮","╰","╯",
  "═","║",
  "╔","╗","╚","╝","╠","╣","╦","╩","╬",
  "━","┃",
  "┏","┓","┗","┛","┣","┫","┳","┻","╋",
]);

/** Tree/list marker characters used by TUI frameworks. */
const LIST_MARKERS = new Set(["▾","▸","►","▹","•","◦","●","○","■","□"]);

/**
 * Check if a character is a Nerd Font icon commonly used as a list marker.
 * These are in the Private Use Area (U+E000-U+F8FF) and Supplemental Private Use Area.
 */
function isNerdFontIcon(char) {
  const cp = char.codePointAt(0);
  // Nerd Font icons in PUA ranges
  return (cp >= 0xE000 && cp <= 0xF8FF) ||  // Basic PUA
         (cp >= 0xF0000 && cp <= 0xFFFFF) || // Supplementary PUA-A
         (cp >= 0x100000 && cp <= 0x10FFFF); // Supplementary PUA-B
}

/** Horizontal rule characters. */
const HR_CHARS = new Set(["─","═","━","─"]);

/**
 * Extract descriptive key hints such as:
 *   "Press ESC / q to exit, / to search, & to filter, h for help"
 */
function extractDescriptiveKeyHints(text) {
  if (!text) return [];
  const hints = [];
  const descriptivePattern = /(?:Press\s+)?([A-Za-z0-9/&+\-]+(?:\s*\/\s*[A-Za-z0-9/&+\-]+)*)\s*(?:to|for)\s+([A-Za-z][\w\s-]*?)(?=,|\||\.|$)/gi;
  let match;
  while ((match = descriptivePattern.exec(text)) !== null) {
    const keyPart = match[1].trim();
    const action = match[2].trim();
    if (!keyPart || !action) continue;

    const keys = /\s+\/\s+|\s+or\s+/i.test(keyPart)
      ? keyPart.split(/\s+\/\s+|\s+or\s+/i).map(k => k.trim()).filter(Boolean)
      : [keyPart];

    // Filter out non-key words: real keys are short identifiers
    // (q, esc, enter, ctrl+c, f1, etc.) not phrases like "letters"
    const validKeys = keys.filter(key => {
      if (key.length > 8) return false; // "letters" is 7, but "ctrl+shift" is 10
      // Allow known key patterns
      if (/^(f\d+|esc|enter|tab|space|ctrl|shift|alt|up|down|left|right|home|end|pgup|pgdn|del|ins|backspace|return)$/i.test(key)) return true;
      // Allow single chars and short combos
      if (/^[a-z0-9+\-]{1,3}$/i.test(key)) return true;
      // Allow ctrl/shift combos
      if (/^(ctrl|shift|alt)\+[a-z]$/i.test(key)) return true;
      // Reject multi-letter words that aren't known keys
      if (/^[a-z]{4,}$/i.test(key)) return false;
      return true;
    });

    for (const key of validKeys) {
      hints.push({ key, action, raw: match[0].trim() });
    }
  }
  return hints;
}

// ── Fix 1: Grid Extraction with Color ────────────────────────────────────

export function extractGrid(buffer, cols, rows) {
  const grid = [];
  for (let y = 0; y < rows; y++) {
    const line = buffer.getLine(buffer.viewportY + y);
    const rowCells = [];
    if (line) {
      for (let x = 0; x < cols; x++) {
        const cell = line.getCell(x);
        if (cell) {
          rowCells.push({
            char: cell.getChars() || " ",
            bold: !!cell.isBold(),
            inverse: !!cell.isInverse(),
            underline: !!cell.isUnderline(),
            italic: !!cell.isItalic(),
            dim: !!cell.isDim(),
            fg: cell.getFgColor(),
            bg: cell.getBgColor(),
            fgMode: cell.getFgColorMode(),
            bgMode: cell.getBgColorMode(),
            width: cell.getWidth(),
          });
        } else {
          rowCells.push({
            char: " ", bold: false, inverse: false, underline: false,
            italic: false, dim: false, fg: -1, bg: -1,
            fgMode: 0, bgMode: 0, width: 1,
          });
        }
      }
    } else {
      for (let x = 0; x < cols; x++) {
        rowCells.push({
          char: " ", bold: false, inverse: false, underline: false,
          italic: false, dim: false, fg: -1, bg: -1,
          fgMode: 0, bgMode: 0, width: 1,
        });
      }
    }
    grid.push(rowCells);
  }
  return grid;
}

// ── Fix 2: New Detectors ──────────────────────────────────────────────────

/**
 * Detect tab bars: rows containing numbered tab indicators like
 * `Status [1] | Log [2] | Files [3]` or underlined tab labels.
 */
export function detectTabs(grid, lines) {
  const tabs = [];

  for (let y = 0; y < lines.length; y++) {
    const line = lines[y];
    if (!line) continue;

    // Pattern 1: Numbered tabs like [1], [2], (1), (2)
    // Split by pipe OR box-drawing corners (╮╭, ┐┌) first, then extract tab index and label
    const pipeParts = line.split(/\s*[|│]\s*|[╮┐][╭┌]/).filter(p => p.trim().length > 0);
    const foundTabs = [];
    for (const part of pipeParts) {
      // Format A: "Label [N]" (e.g., "Status [1]")
      const tabMatchA = part.match(/(\w[\w\s]*?)\s*\[(\d+)\]/);
      if (tabMatchA) {
        foundTabs.push({
          index: parseInt(tabMatchA[2], 10),
          label: tabMatchA[1].trim(),
          active: false,
          col: line.indexOf(part),
        });
        continue;
      }
      // Format B: "[N]─Label" or "[N] Label" (e.g., "[1]─Status", "[2] Files")
      const tabMatchB = part.match(/\[(\d+)\][─━\s]+([\w][\w\s.\-()]*?)(?:[─━]|$)/);
      if (tabMatchB) {
        foundTabs.push({
          index: parseInt(tabMatchB[1], 10),
          label: tabMatchB[2].trim(),
          active: false,
          col: line.indexOf(part),
        });
      }
    }

    if (foundTabs.length >= 2) {
      // Determine active tab: the one with underline styling or bold
      for (const tab of foundTabs) {
        const rowCells = grid[y] || [];
        // Check if cells around the tab label are underlined or bold
        for (let x = tab.col; x < Math.min(tab.col + tab.label.length + 5, rowCells.length); x++) {
          const cell = rowCells[x];
          if (cell && (cell.underline || cell.bold || cell.inverse)) {
            tab.active = true;
            break;
          }
        }
      }

      // If no tab is marked active via style, mark the first one
      if (!foundTabs.some(t => t.active) && foundTabs.length > 0) {
        foundTabs[0].active = true;
      }

      tabs.push({
        id: `tab_bar_${y}`,
        role: "tab_bar",
        tabs: foundTabs,
        bounds: { startY: y, endY: y },
        confidence: 0.9,
        evidence: [line.substring(0, 80)],
      });
    }

    // Pattern 2: Pipe-separated labels without numbers (e.g., "Headers | Body | Query")
    if (foundTabs.length === 0) {
      const pipeParts = line.split(/\s*[|│]\s*/).filter(p => p.trim().length > 0);
      if (pipeParts.length >= 3 && pipeParts.length <= 10) {
        // Check if this looks like tab labels (short words, not content)
        const allShort = pipeParts.every(p => p.trim().length <= 20);
        const rowCells = grid[y] || [];
        const hasUnderline = rowCells.some(c => c.underline);
        if (allShort && (hasUnderline || y === 0 || y === lines.length - 1)) {
          const tabItems = pipeParts.map((p, i) => {
            const label = p.trim();
            // Check if this part is underlined/bold
            const startIdx = line.indexOf(p);
            let isActive = false;
            for (let x = startIdx; x < startIdx + p.length && x < rowCells.length; x++) {
              if (rowCells[x] && (rowCells[x].underline || rowCells[x].bold || rowCells[x].inverse)) {
                isActive = true;
                break;
              }
            }
            return { index: i + 1, label, active: isActive };
          });

          tabs.push({
            id: `tab_bar_${y}`,
            role: "tab_bar",
            tabs: tabItems,
            bounds: { startY: y, endY: y },
            confidence: 0.7,
            evidence: [line.substring(0, 80)],
          });
        }
      }
    }

    // Pattern 3: Numbered panel borders like ╭─[1]─Status──╮
    // These are common in lazygit-style TUIs where panels are numbered
    // and you switch between them with number keys
    const panelBorderMatch = line.match(/[╭┌][─━]+\\[(\\d+)\\][─━]+(\\w[\\w\\s]*?)[─━]*[╮┐]/);
    if (panelBorderMatch && foundTabs.length === 0) {
      // This is a single panel border with a number — collect all such panels
      // We'll look for more on other lines
      // (Don't create a tab bar from a single panel — wait for collectNumberedPanels)
    }
  }

  // Pattern 3 (continued): Collect numbered panel borders across all lines
  // If we find multiple panels with [N] on their top border, treat them as a tab-like structure
  const numberedPanels = [];
  for (let y = 0; y < lines.length; y++) {
    const line = lines[y];
    if (!line) continue;
    // Match each [N]─Label inside a top border on this line
    // Labels can contain letters, spaces, dashes, dots, and parentheses
    const panelRegex = /\[(\d+)\][─━]+([\w][\w\s.\-()]*?)[─━]*(?=[╮┐│]|$)/g;
    let pm;
    while ((pm = panelRegex.exec(line)) !== null) {
      numberedPanels.push({
        index: parseInt(pm[1], 10),
        label: pm[2].trim(),
        active: false,
        row: y,
        col: pm.index,
      });
    }
  }

  if (numberedPanels.length >= 2) {
    // Determine active panel: the one with bold/inverse styling, or the one
    // that contains the cursor position
    let cursorY = -1;
    if (grid._cursorY !== undefined) cursorY = grid._cursorY;
    for (const panel of numberedPanels) {
      const rowCells = grid[panel.row] || [];
      for (let x = panel.col; x < Math.min(panel.col + panel.label.length + 5, rowCells.length); x++) {
        const cell = rowCells[x];
        if (cell && (cell.bold || cell.inverse)) {
          panel.active = true;
          break;
        }
      }
    }
    // If no panel is active via styling, mark the first one (lowest index)
    if (!numberedPanels.some(p => p.active)) {
      const sorted = [...numberedPanels].sort((a, b) => a.index - b.index);
      sorted[0].active = true;
    }

    // Find the row range for the tab bar
    const minRow = Math.min(...numberedPanels.map(p => p.row));
    const maxRow = Math.max(...numberedPanels.map(p => p.row));

    // Only add if we don't already have a tab bar from Pattern 1/2
    // that covers the same panels. Merge if there's overlap.
    const existingTabBars = tabs.filter(t => t.role === "tab_bar");
    const existingIndices = new Set(existingTabBars.flatMap(t => t.tabs?.map(tab => tab.index) || []));
    const newIndices = numberedPanels.map(p => p.index);
    const hasOverlap = newIndices.some(idx => existingIndices.has(idx));

    if (hasOverlap) {
      // Merge: replace existing tab bars with the comprehensive one from Pattern 3
      const mergedTabs = numberedPanels.map(p => ({
        index: p.index,
        label: p.label,
        active: p.active,
        col: p.col,
      }));
      // Remove existing tab bars and add the merged one
      tabs.length = 0;
      tabs.push({
        id: `tab_bar_panels`,
        role: "tab_bar",
        tabs: mergedTabs,
        bounds: { startY: minRow, endY: maxRow },
        confidence: 0.85,
        evidence: numberedPanels.map(p => `[#${p.index}] ${p.label}`),
      });
    } else {
      tabs.push({
        id: `tab_bar_panels`,
        role: "tab_bar",
        tabs: numberedPanels.map(p => ({
          index: p.index,
          label: p.label,
          active: p.active,
          col: p.col,
        })),
        bounds: { startY: minRow, endY: maxRow },
        confidence: 0.85,
        evidence: numberedPanels.map(p => `[#${p.index}] ${p.label}`),
      });
    }
  }

  return tabs;
}

/**
 * Detect split panes: bordered regions using box-drawing characters.
 * Finds rectangular regions bounded by ┌─┐│└─┘ etc.
 */
export function detectPanes(grid, lines) {
  const panes = [];

  // Find horizontal rules and vertical rules as pane boundaries
  const hRules = []; // { y, startX, endX }
  const vRules = []; // { x, startY, endY }

  for (let y = 0; y < lines.length; y++) {
    const rowCells = grid[y] || [];
    // Find horizontal rule runs
    let ruleStart = -1;
    for (let x = 0; x < rowCells.length; x++) {
      const ch = rowCells[x]?.char;
      if (ch && (HR_CHARS.has(ch) || ch === "┌" || ch === "┐" || ch === "└" || ch === "┘" ||
                 ch === "┬" || ch === "┴" || ch === "┼" || ch === "╭" || ch === "╮" ||
                 ch === "╰" || ch === "╯")) {
        if (ruleStart === -1) ruleStart = x;
      } else {
        if (ruleStart !== -1 && x - ruleStart >= 5) {
          hRules.push({ y, startX: ruleStart, endX: x - 1 });
        }
        ruleStart = -1;
      }
    }
    if (ruleStart !== -1 && rowCells.length - ruleStart >= 5) {
      hRules.push({ y, startX: ruleStart, endX: rowCells.length - 1 });
    }
  }

  // Find vertical rule runs (│ characters)
  for (let x = 0; x < (grid[0]?.length || 0); x++) {
    let ruleStart = -1;
    for (let y = 0; y < grid.length; y++) {
      const ch = grid[y]?.[x]?.char;
      if (ch === "│" || ch === "┃" || ch === "║") {
        if (ruleStart === -1) ruleStart = y;
      } else {
        if (ruleStart !== -1 && y - ruleStart >= 3) {
          vRules.push({ x, startY: ruleStart, endY: y - 1 });
        }
        ruleStart = -1;
      }
    }
    if (ruleStart !== -1 && grid.length - ruleStart >= 3) {
      vRules.push({ x, startY: ruleStart, endY: grid.length - 1 });
    }
  }

  // Find box titles: text on a horizontal rule line between ┌ and ┐
  for (const rule of hRules) {
    const rowCells = grid[rule.y] || [];
    // Look for ┌ followed by title text followed by ┐ on this line
    let titleStart = -1;
    let titleEnd = -1;
    let title = "";

    for (let x = rule.startX; x <= rule.endX; x++) {
      const ch = rowCells[x]?.char;
      if (ch === "┌" || ch === "╭") {
        titleStart = x + 1;
      } else if (ch === "┐" || ch === "╮") {
        titleEnd = x - 1;
        break;
      }
    }

    if (titleStart !== -1 && titleEnd > titleStart) {
      // Extract title text
      const titleChars = [];
      for (let x = titleStart; x <= titleEnd; x++) {
        const ch = rowCells[x]?.char;
        if (ch && ch !== "─" && ch !== "━" && ch !== "═") {
          titleChars.push(ch);
        }
      }
      title = titleChars.join("").trim();
    }

    if (title || rule.endX - rule.startX >= 10) {
      panes.push({
        id: title ? `pane_${title.replace(/\s+/g, "_")}` : `pane_${rule.y}`,
        role: "pane",
        title: title || undefined,
        bounds: { startY: rule.y, endY: rule.y },
        confidence: title ? 0.9 : 0.6,
        evidence: [lines[rule.y]?.substring(0, 80) || "horizontal rule"],
      });
    }
  }

  // Detect vertical split by finding vertical rules that span most of the screen
  if (vRules.length > 0) {
    for (const vr of vRules) {
      const span = vr.endY - vr.startY;
      if (span >= grid.length * 0.3) { // spans at least 30% of screen
        panes.push({
          id: `vsplit_${vr.x}`,
          role: "vertical_split",
          bounds: { startY: vr.startY, endY: vr.endY },
          confidence: 0.8,
          evidence: [`vertical rule at col ${vr.x}, rows ${vr.startY}-${vr.endY}`],
        });
      }
    }
  }

  return panes;
}

/**
 * Detect list items: tree markers (▾, ▸, •), cursor indicators (>),
 * and inverse/bold first characters indicating selection.
 */
export function detectLists(grid, lines) {
  const items = [];

  for (let y = 0; y < lines.length; y++) {
    const line = lines[y];
    if (!line || line.trim().length === 0) continue;
    const rowCells = grid[y] || [];

    // Pattern 1: Tree markers (may appear after box border │ and spaces)
    const treeMatch = line.match(/^[│┃║ ]*(\s*)([▾▸►▹•◦●○■□►])\s*(.+)/);
    if (treeMatch) {
      const indent = treeMatch[1].length;
      const marker = treeMatch[2];
      const label = treeMatch[3].trim().substring(0, 60);
      items.push({
        id: `list_${y}`,
        role: "list_item",
        label,
        marker,
        indent,
        selected: false,
        bounds: { startY: y, endY: y },
        confidence: 0.9,
        evidence: [line.substring(0, 60)],
      });
      continue;
    }

    // Pattern 1b: Nerd Font icons as list markers (Private Use Area characters)
    // These are commonly used by file managers like yazi
    const rowCells0 = grid[y] || [];
    let firstNonSpaceIdx = -1;
    for (let x = 0; x < rowCells0.length; x++) {
      if (rowCells0[x].char !== " " && !BOX_DRAWING.has(rowCells0[x].char)) {
        firstNonSpaceIdx = x;
        break;
      }
    }
    if (firstNonSpaceIdx >= 0) {
      const firstChar = rowCells0[firstNonSpaceIdx].char;
      if (isNerdFontIcon(firstChar) && firstChar.length <= 2) {
        // Found a Nerd Font icon — extract the label after it
        const afterIcon = line.substring(firstNonSpaceIdx + firstChar.length).trim().substring(0, 60);
        if (afterIcon.length > 0) {
          items.push({
            id: `list_${y}`,
            role: "list_item",
            label: afterIcon,
            marker: "nerd_icon",
            indent: firstNonSpaceIdx,
            selected: false,
            bounds: { startY: y, endY: y },
            confidence: 0.8,
            evidence: [line.substring(0, 60)],
          });
          continue;
        }
      }
    }

    // Pattern 2: Cursor indicator (> at start of line, possibly after box border)
    const cursorMatch = line.match(/^[│┃║ ]*(\s*)>\s+(.+)/);
    if (cursorMatch) {
      items.push({
        id: `list_${y}`,
        role: "list_item",
        label: cursorMatch[2].trim().substring(0, 60),
        marker: ">",
        indent: cursorMatch[1].length,
        selected: true,
        bounds: { startY: y, endY: y },
        confidence: 0.85,
        evidence: [line.substring(0, 60)],
      });
      continue;
    }

    // Pattern 3: Inverse/bold first non-space character (selection highlight)
    // Skip box-drawing border characters
    for (let x = 0; x < rowCells.length; x++) {
      const cell = rowCells[x];
      if (cell && cell.char !== " " && !BOX_DRAWING.has(cell.char)) {
        if (cell.inverse || (cell.bold && cell.fg >= 0 && cell.fg !== cell.bg)) {
          // This line has a styled first character — likely selected
          const label = line.trim().substring(0, 60);
          // Reject ASCII art / animation lines: if label has <30% alphanumeric, skip
          const alphaCount = (label.match(/[a-zA-Z0-9]/g) || []).length;
          if (label.length > 0 && alphaCount / label.length >= 0.3) {
            items.push({
              id: `list_${y}`,
              role: "list_item",
              label,
              marker: cell.inverse ? "inverse" : "bold",
              indent: x,
              selected: true,
              bounds: { startY: y, endY: y },
              confidence: 0.7,
              evidence: [line.substring(0, 60)],
            });
          }
        }
        break; // Only check first non-space character
      }
    }
  }

  // Group consecutive list items into a list container
  if (items.length >= 2) {
    // Find contiguous groups
    const groups = [];
    let currentGroup = [items[0]];
    for (let i = 1; i < items.length; i++) {
      if (items[i].bounds.startY === items[i - 1].bounds.startY + 1) {
        currentGroup.push(items[i]);
      } else {
        groups.push(currentGroup);
        currentGroup = [items[i]];
      }
    }
    groups.push(currentGroup);

    // Return both individual items and group containers
    const result = [];
    for (const group of groups) {
      if (group.length >= 2) {
        result.push({
          id: `list_container_${group[0].bounds.startY}`,
          role: "list",
          items: group,
          bounds: {
            startY: group[0].bounds.startY,
            endY: group[group.length - 1].bounds.endY,
          },
          confidence: 0.8,
          evidence: group.map(g => g.label).slice(0, 3),
        });
      }
      result.push(...group);
    }
    return result;
  }

  return items;
}

/**
 * Detect status bars: bottom rows with distinct colors (e.g., white-on-blue),
 * compact keybinding hints like [a], ^c, Ctrl+X, or descriptive phrases like
 * "Press ESC / q to exit" / "h for help".
 */
export function detectStatusBar(grid, lines) {
  const bars = [];
  const rows = lines.length;
  if (rows === 0) return bars;

  // Check last few non-empty rows for status bar patterns
  for (let y = rows - 1; y >= Math.max(0, rows - 3); y--) {
    const line = lines[y];
    if (!line || line.trim().length === 0) continue;

    const rowCells = grid[y] || [];

    // Pattern 1: Distinct background color on most of the row
    const bgColors = new Map();
    let maxBgCount = 0;
    let dominantBg = -1;
    for (const cell of rowCells) {
      if (cell.char !== " " && cell.bg >= 0) {
        const count = (bgColors.get(cell.bg) || 0) + 1;
        bgColors.set(cell.bg, count);
        if (count > maxBgCount) {
          maxBgCount = count;
          dominantBg = cell.bg;
        }
      }
    }

    const hasDistinctBg = maxBgCount > rowCells.length * 0.1 && dominantBg >= 0;

    // Pattern 2: Keybinding hints (both [key] and <key> notation)
    // Also match btop-style └┘key action format and descriptive phrases
    // like "Press ESC / q to exit" / "/ to search".
    const keyHintPattern = /\[([A-Za-z0-9⏎⇧↑↓←→]+)\]|<([A-Za-z0-9_-]+)>|\^([a-z])|Ctrl\+([A-Z])|└┘\s*([↑↓←→↵⏎A-Za-z0-9]+)\s*|(?:^|[^\w])(F\d+)|(?:Press\s+)?([A-Za-z0-9/&+\-]+(?:\s*\/\s*[A-Za-z0-9/&+\-]+)*)\s*(?:to|for)\s+(?:exit|quit|help|search|filter|close|cancel|back|select|confirm|save|open|toggle|next|previous|prev|menu|refresh|reload|sort|copy|paste|delete|remove)\b/g;
    const keyHints = [];
    const seenKeyHints = new Set();
    const pushKeyHint = (key) => {
      const normalized = key?.trim();
      if (!normalized || seenKeyHints.has(normalized)) return;
      seenKeyHints.add(normalized);
      keyHints.push(normalized);
    };
    let match;
    let descriptivePatternMatched = false;
    while ((match = keyHintPattern.exec(line)) !== null) {
      if (match[7]) descriptivePatternMatched = true;
      pushKeyHint(match[1] || match[2] || match[3] || match[4] || match[5] || match[6]);
    }

    const descriptiveKeyHints = extractDescriptiveKeyHints(line);
    for (const hint of descriptiveKeyHints) {
      pushKeyHint(hint.key);
    }

    // Pattern 3: Pipe-separated short labels at bottom
    const pipeParts = line.split(/\s*[|│]\s*/).filter(p => p.trim().length > 0);
    const isPipeBar = pipeParts.length >= 3 && y >= rows - 2 &&
      pipeParts.every(p => p.trim().length <= 30);

    const isLastLine = y === rows - 1;
    const hasDescriptiveStatusHints = descriptivePatternMatched || descriptiveKeyHints.length > 0;
    const isDescriptiveStatusBar = isLastLine && hasDescriptiveStatusHints;
    const isFileInfoStatusBar = isLastLine && !hasDistinctBg && keyHints.length === 0 && !isPipeBar &&
      /(?:\b[dl-][rwx-]{9}\b.*\b\d+\/\d+\b)|(?:\b\d+\/\d+\b.*\b(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\b)|(?:\b\d+(?:\.\d+)?[KMGTP]?B\b)/i.test(line);

    if (hasDistinctBg || keyHints.length >= 2 || isPipeBar || isDescriptiveStatusBar || isFileInfoStatusBar) {
      const keyActions = parseKeyHints(line);
      bars.push({
        id: `status_bar_${y}`,
        role: "status_bar",
        keybindings: keyHints.length > 0 ? keyHints : undefined,
        keyActions: keyActions.length > 0 ? keyActions : undefined,
        bgColor: dominantBg >= 0 ? dominantBg : undefined,
        bounds: { startY: y, endY: y },
        confidence: hasDistinctBg ? 0.9 : keyHints.length >= 2 ? 0.85 : isDescriptiveStatusBar ? 0.75 : isFileInfoStatusBar ? 0.65 : 0.6,
        evidence: [line.substring(0, 80)],
      });
      break; // Only detect the bottommost status bar
    }
  }

  return bars;
}

/**
 * Parse status bar text into structured key→action mappings.
 * Handles formats like:
 *   "Save [s] Quit [q] Tab [1-5]"
 *   "Stage All [a] Stage [⏎] Reset [⇧D]"
 *   "[s] start  [x] stop  [?] help"
 *   "j/k: navigate  q: quit  Enter: select"
 *   "Confirm: <enter> | Close/Cancel: <esc> | Copy: <c-o>"
 *
 * Returns an array of { key, action, raw } objects.
 */
export function parseKeyHints(text) {
  if (!text) return [];
  const hints = [];

  // Pattern 1: Action [key] or [key] Action (bracketed keys)
  // "Save [s] Quit [q]" → { key: "s", action: "Save" }, { key: "q", action: "Quit" }
  const bracketPattern = /(\w[\w\s]*?)\s*\[([^\]]+)\]/g;
  let match;
  while ((match = bracketPattern.exec(text)) !== null) {
    const action = match[1].trim();
    const key = match[2].trim();
    if (action && key) {
      hints.push({ key, action, raw: match[0] });
    }
  }

  // Pattern 1b: Action: <key> (angle-bracket notation, common in lazygit)
  // "Confirm: <enter> | Close/Cancel: <esc>" → { key: "enter", action: "Confirm" }
  const anglePattern = /(\w[\w\s/]*?)\s*[:=]?\s*<([A-Za-z0-9_-]+)>/g;
  while ((match = anglePattern.exec(text)) !== null) {
    const action = match[1].replace(/[|│]/g, "").trim();
    const key = match[2].trim().toLowerCase();
    if (action && key && !hints.some(h => h.key === key)) {
      hints.push({ key, action, raw: match[0] });
    }
  }

  // If no bracketed/angle patterns found, try colon-separated
  if (hints.length === 0) {
    // "j/k: navigate  q: quit  Enter: select"
    const colonPattern = /(?:^|[\s|,])([A-Za-z0-9⏎⇧↑↓←→\\/]+)\s*[:=]\s*(\w[\w\s]*?)(?=\s{2,}|$)/g;
    while ((match = colonPattern.exec(text)) !== null) {
      const key = match[1].trim();
      const action = match[2].trim();
      // Skip pure numeric keys — they're cursor positions (1:1, 23:5) not keybindings
      if (/^\d+$/.test(key)) continue;
      if (key && action) {
        hints.push({ key, action, raw: match[0] });
      }
    }
  }

  // If still nothing, try bare [key] at start of segments
  if (hints.length === 0) {
    // "[s] start  [x] stop  [?] help"
    const bareBracketPattern = /\[([^\]]+)\]\s*(\w[\w\s]*?)(?=\s*\[|$)/g;
    while ((match = bareBracketPattern.exec(text)) !== null) {
      const key = match[1].trim();
      const action = match[2].trim();
      if (key && action) {
        hints.push({ key, action, raw: match[0] });
      }
    }
  }

  // Pattern 5: htop-style F-key format
  // "F1Help F2Setup F10Quit" → { key: "F1", action: "Help" }
  // This also handles concatenated segments like "F3SearchF4Filter"
  const fkeyPattern = /F(\d+)(.*?)(?=F\d+|$)/g;
  while ((match = fkeyPattern.exec(text)) !== null) {
    const key = `F${match[1]}`;
    const action = match[2].trim();
    if (key && action) {
      hints.push({ key, action, raw: match[0].trim() });
    }
  }

  // Pattern 6: btop-style key symbols embedded in status bar
  // "╰┘↑ select ↓└┘info ↵└┘terminate└┘kill└┘signals"
  // Key symbols (↑↓←→↵⏎) appear before their action words
  // Skip symbols preceded by ^ (they're caret-notation keys like ^⏎)
  if (hints.length === 0) {
    const keySymbols = ["↑","↓","←","→","↵","⏎","⇥","⇧"];
    for (let i = 0; i < text.length; i++) {
      const char = text[i];
      if (keySymbols.includes(char)) {
        // Skip if preceded by ^ (caret notation)
        if (i > 0 && text[i - 1] === '^') continue;
        const after = text.substring(i + 1).replace(/^[└┘╰\s]+/, "").trim();
        const actionMatch = after.match(/^(\w+)/);
        if (actionMatch) {
          hints.push({ key: char, action: actionMatch[1], raw: char + " " + actionMatch[1] });
        }
      }
    }
  }

  // Pattern 7: Descriptive key hints: "Press ESC / q to exit", "/ to search", "h for help"
  // Extract each "key to/for action" pair and expand slash-separated keys.
  const descriptiveHints = extractDescriptiveKeyHints(text);
  for (const hint of descriptiveHints) {
    if (!hints.some(h => h.key === hint.key && h.action === hint.action)) {
      hints.push(hint);
    }
  }

  // Pattern 8: Textual ^key notation: "^c Quit ^j Send ^t Method ^s Save f1 Help"
  // Caret-prefix keys common in Python Textual TUI apps
  // Uppercase ^X means Ctrl+Shift+X, lowercase ^x means Ctrl+X
  // Also handles ^⏎ (Ctrl+Enter), ^⇧ (Ctrl+Shift), etc.
  // And "or" between keys: "^⏎ or ^j Run Query"
  if (hints.length === 0) {
    // First, normalize "or" between ^keys: "^⏎ or ^j Run Query" → "^⏎ Run Query ^j Run Query"
    // We need to find the action that follows the second key and duplicate it
    let normalized = text.replace(/\^(\S+)\s+or\s+\^(\S+)\s+(\w[\w\s]*?)(?=\s*\^|\s{2,}\w|$)/g,
      (m, k1, k2, action) => `^${k1} ${action} ^${k2} ${action} `);

    // Match ^ followed by ASCII letter/digit OR Unicode key symbols
    const textualPattern = /\^([a-zA-Z0-9⏎⇧⇥↑↓←→↵])\s+(\w[\w\s]*?)(?=\s*\^|\s{2,}\w|$)/g;
    while ((match = textualPattern.exec(normalized)) !== null) {
      const rawKey = match[1];
      // Map Unicode symbols to key names
      const symbolMap = { '⏎': 'enter', '↵': 'enter', '⇧': 'shift', '⇥': 'tab', '↑': 'up', '↓': 'down', '←': 'left', '→': 'right' };
      let key;
      if (symbolMap[rawKey]) {
        key = "ctrl+" + symbolMap[rawKey];
      } else if (rawKey === rawKey.toUpperCase() && rawKey !== rawKey.toLowerCase()) {
        key = "ctrl+shift+" + rawKey.toLowerCase();
      } else {
        key = "ctrl+" + rawKey.toLowerCase();
      }
      const action = match[2].trim();
      if (key && action) {
        hints.push({ key, action, raw: match[0].trim() });
      }
    }
    // Also pick up standalone f-key hints like "f1 Help"
    const fkeyStandalone = /\b(f\d+)\s+(\w[\w\s]*?)(?=\s*\^|\s{2,}|$)/gi;
    while ((match = fkeyStandalone.exec(text)) !== null) {
      const key = match[1].toLowerCase();
      const action = match[2].trim();
      if (key && action && !hints.some(h => h.key === key)) {
        hints.push({ key, action, raw: match[0].trim() });
      }
    }
  }

  // Pattern 9: Bare key + space + action, separated by double spaces
  // "s Start  p PDS2  x Stop  1-4 Panel  Tab Switch  q Quit"
  // Common in custom TUI dashboards (e.g., Garazyk Scenario Dashboard)
  if (hints.length === 0) {
    const bareKeyPattern = /(?:^|\s{2,})([a-zA-Z0-9]{1,3}(?:-[a-zA-Z0-9]{1,3})?)\s+([A-Za-z][\w\s]*?)(?=\s{2,}|$)/g;
    while ((match = bareKeyPattern.exec(text)) !== null) {
      const key = match[1].trim();
      const action = match[2].trim();
      // Skip if key is a common word, not a real key
      if (/^(the|and|for|not|but|are|was|has|all|can|may|its|our|you|out|get|set|let|new|now|old|see|way|who|did|got|use|her|him|she|how|too|any|own|sub|var|end|put|add|run|try|ask|men|few|lot|log|top|red|bad|big|low|cut|hot|hit|bit|ten|map|key|pay|say|buy|yet|age|day|far|fun|win|box|bar|net|tag|web|app|dir|mod|pkg|dev|ops|sql|api|css|dom|gui|ide|sdk|url|uri|xml|json|yaml|html|http|ssl|tls|tcp|udp|ssh|dns|vpn|cdn|otp|sso|mfa|jwt|sri|hsts|csp)$/i.test(key)) {
        // Allow known short keys that happen to be words
        if (!['s', 'p', 'x', 'q', 'a', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'm', 'n', 'r', 'v', 'w', 'y', 'z'].includes(key.toLowerCase())) continue;
      }
      if (key && action && action.length > 0) {
        hints.push({ key, action, raw: match[0].trim() });
      }
    }
  }

  return hints;
}

/**
 * Parse a help overlay into a full keybinding table.
 * Handles formats like:
 *   "q         quit          Quit the process"
 *   "<C-c>     close         Close the current tab"
 *   "j         arrow next    Next file"
 *   "k         arrow prev    Previous file"
 *
 * Returns an array of { key, command, description } objects.
 */
export function parseHelpOverlay(lines) {
  const bindings = [];
  for (const line of lines) {
    // Match: key + command + description, separated by 2+ spaces
    // Keys can be: single chars (j, k, q), multi-char (gg, G),
    // angle-bracket notation (<C-c>, <S-PageUp>, <Up>, <Space>), or shift+char (H, L)
    // Commands can contain spaces (e.g., "arrow next", "arrow prev")
    // Strategy: split on 2+ space gaps, take first as key, second as command, rest as description
    const parts = line.split(/\s{2,}/).filter(p => p.length > 0);
    if (parts.length >= 3) {
      const key = parts[0].trim();
      const command = parts[1].trim();
      const description = parts.slice(2).join('  ').trim();
      // Filter out non-keybinding lines
      if (key.length > 0 && command.length > 0 &&
          !key.startsWith('-') && !key.startsWith('┌') && !key.startsWith('│') &&
          !key.startsWith('─') && !key.startsWith('└') &&
          !description.includes('Press') && !description.includes('filter')) {
        bindings.push({ key, command, description });
      }
    }
  }
  return bindings;
}

/**
 * Build a navigation capability map from a semantic snapshot.
 * This is the core of the generalization: instead of "if gitui, do X",
 * we ask "what can I do here?" based on the detected elements.
 *
 * Returns a structured map of available interactions:
 *   { navigate, tabs, actions, dismiss, help, quit }
 *
 * The DECIDE step should read this map to choose actions.
 */
export function buildCapabilityMap(snapshot) {
  const caps = {
    // What navigation is available
    navigate: { keys: [], source: "" },
    // Tab switching
    tabs: { available: false, keys: [], activeTab: null, tabCount: 0, source: "" },
    // Discrete actions (from status bar key hints)
    actions: [],  // { key, action, source }
    // How to dismiss overlays
    dismiss: { keys: [], source: "" },
    // How to get help
    help: { keys: [], source: "" },
    // How to quit
    quit: { keys: [], source: "" },
    // Framework hint (affects key conventions)
    framework: snapshot.framework || "unknown",
  };

  // ── From status bar key hints ──
  for (const sb of snapshot.statusBars || []) {
    if (sb.keyActions) {
      for (const ka of sb.keyActions) {
        const action = ka.action.toLowerCase();
        const key = normalizeKey(ka.key);

        // Classify by action type
        // Function-key hints in apps like htop are best treated as explicit app actions,
        // except for the canonical F1 help and F10 quit bindings.
        const isFunctionKey = /^f\d+$/.test(key);
        if (isFunctionKey) {
          if (action.includes("quit") || action.includes("exit")) {
            caps.quit.keys.push(key);
            caps.quit.source = "status_bar";
          } else if (action.includes("help") || action === "?") {
            caps.help.keys.push(key);
            caps.help.source = "status_bar";
          } else {
            caps.actions.push({ key, action: ka.action, source: "status_bar" });
          }
        } else if (action.includes("quit") || action.includes("exit")) {
          caps.quit.keys.push(key);
          caps.quit.source = "status_bar";
        } else if (action.includes("help") || action === "?") {
          caps.help.keys.push(key);
          caps.help.source = "status_bar";
        } else if (action.includes("nav") || action.includes("next") || action.includes("prev") ||
                   action.includes("up") || action.includes("down") || action.includes("scroll")) {
          caps.navigate.keys.push(key);
          caps.navigate.source = "status_bar";
        } else if (action.includes("tab") || action.includes("switch")) {
          caps.tabs.keys.push(key);
          caps.tabs.source = "status_bar";
        } else if (action.includes("close") || action.includes("cancel") || action.includes("escape") ||
                   action.includes("back") || action.includes("dismiss")) {
          caps.dismiss.keys.push(key);
          caps.dismiss.source = "status_bar";
        } else {
          caps.actions.push({ key, action: ka.action, source: "status_bar" });
        }
      }
    }
  }

  // ── From tab bars ──
  for (const tabBar of snapshot.tabs || []) {
    if (tabBar.tabs && tabBar.tabs.length > 0) {
      caps.tabs.available = true;
      caps.tabs.tabCount = tabBar.tabs.length;
      const activeTab = tabBar.tabs.find(t => t.active);
      caps.tabs.activeTab = activeTab?.label || null;
      // Number keys for tab switching (if tabs are numbered)
      const numberedTabs = tabBar.tabs.filter(t => t.index != null);
      if (numberedTabs.length > 0 && !caps.tabs.keys.includes(String(numberedTabs[0].index))) {
        // Add number keys for each tab
        for (const tab of numberedTabs) {
          const key = String(tab.index);
          if (!caps.tabs.keys.includes(key)) {
            caps.tabs.keys.push(key);
          }
        }
        if (!caps.tabs.source) caps.tabs.source = "tab_bar";
      }
    }
  }

  // ── From list items ──
  const listItems = (snapshot.lists || []).filter(l => l.role === "list_item");
  if (listItems.length > 0) {
    // Lists imply navigation capability
    if (caps.navigate.keys.length === 0) {
      caps.navigate.source = "list_inference";
    }
  }

  // ── From popups ──
  if ((snapshot.popups || []).length > 0) {
    if (caps.dismiss.keys.length === 0) {
      caps.dismiss.keys.push("escape");
      caps.dismiss.source = "popup_inference";
    }
  }

  // ── Framework-based defaults ──
  // These fill in gaps when the status bar doesn't provide enough info
  if (caps.framework === "ratatui") {
    if (caps.navigate.keys.length === 0) {
      caps.navigate.keys = ["j", "k"];
      caps.navigate.source = "framework_ratatui";
    }
    if (caps.quit.keys.length === 0) {
      caps.quit.keys = ["q"];
      caps.quit.source = "framework_ratatui";
    }
    if (caps.help.keys.length === 0) {
      caps.help.keys = ["?"];
      caps.help.source = "framework_ratatui";
    }
  } else if (caps.framework === "textual") {
    if (caps.navigate.keys.length === 0) {
      caps.navigate.keys = ["up", "down"];
      caps.navigate.source = "framework_textual";
    }
    if (caps.quit.keys.length === 0) {
      caps.quit.keys = ["ctrl+c"];
      caps.quit.source = "framework_textual";
    }
    if (caps.tabs.keys.length === 0 && caps.tabs.available) {
      caps.tabs.keys = ["tab"];
      caps.tabs.source = "framework_textual";
    }
  } else if (caps.framework === "vim") {
    if (caps.navigate.keys.length === 0) {
      caps.navigate.keys = ["h", "j", "k", "l"];
      caps.navigate.source = "framework_vim";
    }
    if (caps.quit.keys.length === 0) {
      caps.quit.keys = [":q", "ZZ"];
      caps.quit.source = "framework_vim";
    }
    if (caps.help.keys.length === 0) {
      caps.help.keys = ["?", "F1"];
      caps.help.source = "framework_vim";
    }
  } else if (caps.framework === "bubbletea") {
    if (caps.navigate.keys.length === 0) {
      caps.navigate.keys = ["j", "k", "up", "down"];
      caps.navigate.source = "framework_bubbletea";
    }
    if (caps.quit.keys.length === 0) {
      caps.quit.keys = ["q", "escape"];
      caps.quit.source = "framework_bubbletea";
    }
    if (caps.help.keys.length === 0) {
      caps.help.keys = ["?"];
      caps.help.source = "framework_bubbletea";
    }
  }

  // ── App-specific overrides ──
  // fzf is a picker, not a full TUI — quit is ESC/Ctrl+C, navigate is up/down
  if (snapshot.app === "fzf") {
    caps.quit.keys = ["escape", "ctrl+c"];
    caps.quit.source = "app_fzf";
    caps.navigate.keys = ["up", "down", "j", "k"];
    caps.navigate.source = "app_fzf";
    caps.tabs.available = false;
    caps.help.keys = ["?"];
    caps.help.source = "app_fzf";
    caps.actions = [
      { key: "enter", action: "select", source: "app_fzf" },
      { key: "tab", action: "multi-select", source: "app_fzf" },
      { key: "shift-tab", action: "multi-select-down", source: "app_fzf" },
      { key: "ctrl-r", action: "refresh", source: "app_fzf" },
    ];
  }

  // ── Game overrides ──
  // ncurses games: arrow keys for movement, q to quit
  if (["nsnake", "nudoku", "nethack", "greed"].includes(snapshot.app)) {
    caps.navigate.keys = ["j", "k", "h", "l"];
    caps.navigate.source = "app_" + snapshot.app;
    caps.quit.keys = ["q"];
    caps.quit.source = "app_" + snapshot.app;
    caps.tabs.available = false;
    if (snapshot.app === "nethack") {
      caps.actions = [
        { key: "i", action: "inventory", source: "app_nethack" },
        { key: "m", action: "magic", source: "app_nethack" },
        { key: ".", action: "wait", source: "app_nethack" },
        { key: "s", action: "search", source: "app_nethack" },
      ];
    }
  }

  // ── Helix overrides ──
  // Helix is a modal editor like vim — uses :q to quit, h/j/k/l to navigate
  if (snapshot.app === "helix") {
    caps.navigate.keys = ["h", "j", "k", "l"];
    caps.navigate.source = "app_helix";
    caps.quit.keys = [":q"];
    caps.quit.source = "app_helix";
    caps.help.keys = [":help"];
    caps.help.source = "app_helix";
    caps.actions = [
      { key: "i", action: "insert_mode", source: "app_helix" },
      { key: "a", action: "append_mode", source: "app_helix" },
      { key: "o", action: "open_below", source: "app_helix" },
      { key: "d", action: "delete", source: "app_helix" },
      { key: "w", action: "next_word", source: "app_helix" },
      { key: "x", action: "select_line", source: "app_helix" },
      { key: "/", action: "search", source: "app_helix" },
      { key: ":", action: "command_mode", source: "app_helix" },
      { key: "space", action: "leader", source: "app_helix" },
    ];
  }

  // ── Dashboard overrides ──
  // Garazyk Scenario Dashboard: custom key map from footer
  if (snapshot.app === "dashboard") {
    caps.navigate.keys = ["up", "down", "j", "k"];
    caps.navigate.source = "app_dashboard";
    caps.tabs.keys = ["1", "2", "3", "4", "tab"];
    caps.tabs.available = true;
    caps.tabs.source = "app_dashboard";
    caps.quit.keys = ["q"];
    caps.quit.source = "app_dashboard";
    caps.help.keys = ["?"];
    caps.help.source = "app_dashboard";
    caps.actions = [
      { key: "s", action: "Start", source: "app_dashboard" },
      { key: "p", action: "PDS2", source: "app_dashboard" },
      { key: "x", action: "Stop", source: "app_dashboard" },
      { key: "enter", action: "Run", source: "app_dashboard" },
    ];
  } else if (caps.framework === "ncurses") {
    if (caps.navigate.keys.length === 0) {
      caps.navigate.keys = ["j", "k"];
      caps.navigate.source = "framework_ncurses";
    }
    if (caps.quit.keys.length === 0) {
      caps.quit.keys = ["q"];
      caps.quit.source = "framework_ncurses";
    }
    if (caps.help.keys.length === 0) {
      caps.help.keys = ["?"];
      caps.help.source = "framework_ncurses";
    }
  } else if (caps.framework === "textual") {
    if (caps.navigate.keys.length === 0) {
      caps.navigate.keys = ["up", "down", "j", "k"];
      caps.navigate.source = "framework_textual";
    }
    if (caps.quit.keys.length === 0) {
      caps.quit.keys = ["ctrl+c", "q"];
      caps.quit.source = "framework_textual";
    }
    if (caps.help.keys.length === 0) {
      caps.help.keys = ["?"];
      caps.help.source = "framework_textual";
    }
  }

  // ── Header line hints ──
  // Some apps (ncdu) put navigation hints in the header line
  // e.g., "Use the arrow keys to navigate, press ? for help"
  const facts = snapshot.facts || [];
  for (const fact of facts) {
    const text = (fact.label + " " + fact.value).toLowerCase();
    if (text.includes("navigate") && caps.navigate.keys.length === 0) {
      // The app says how to navigate — but trust our competence data over the app's suggestion
      // ncurses apps say "arrow keys" but those crash in PTY; use j/k instead
      if (caps.framework === "ncurses" || caps.framework === "unknown") {
        caps.navigate.keys = ["j", "k"];
        caps.navigate.source = "header_hint_override";
      }
    }
    if (text.includes("?") && text.includes("help") && !caps.help.keys.includes("?")) {
      caps.help.keys.push("?");
      if (!caps.help.source) caps.help.source = "header_hint";
    }
  }

  // ── Unknown framework fallback ──
  // If framework is unknown and no navigation keys found, use safe defaults
  if (caps.framework === "unknown") {
    if (caps.navigate.keys.length === 0) {
      caps.navigate.keys = ["j", "k"];
      caps.navigate.source = "framework_unknown";
    }
    if (caps.quit.keys.length === 0) {
      caps.quit.keys = ["q"];
      caps.quit.source = "framework_unknown";
    }
    if (caps.help.keys.length === 0) {
      caps.help.keys = ["?"];
      caps.help.source = "framework_unknown";
    }
  }

  // ── Universal fallbacks ──
  // These are always available regardless of framework
  if (!caps.dismiss.keys.includes("escape")) {
    caps.dismiss.keys.push("escape");
  }
  if (!caps.help.keys.includes("?")) {
    caps.help.keys.push("?");
  }
  if (!caps.help.keys.some(k => k.toLowerCase() === "f1")) {
    caps.help.keys.push("f1");
  }

  return caps;
}

/**
 * Normalize a key hint from status bar notation to a standard key name.
 * [s] → "s", [⇧D] → "shift+d", [⏎] → "enter", [↑↓→←] → "arrows"
 * <enter> → "enter", <esc> → "escape", <c-o> → "ctrl+o"
 */
function normalizeKey(key) {
  if (!key) return key;
  // Strip angle brackets if present, then normalize case so textual keys like
  // ESC / Ctrl+X / Enter collapse to a consistent representation.
  let result = key.replace(/^<(.+)>$/, "$1").trim();
  const lower = result.toLowerCase();

  const namedMap = {
    esc: "escape",
    escape: "escape",
    enter: "enter",
    return: "enter",
    tab: "tab",
    space: "space",
    backspace: "backspace",
    delete: "delete",
    up: "up",
    down: "down",
    left: "left",
    right: "right",
    home: "home",
    end: "end",
  };
  if (namedMap[lower]) return namedMap[lower];

  result = lower;

  // Unicode symbols
  const symbolMap = {
    "⏎": "enter",
    "↵": "enter",
    "⇥": "tab",
    "↑": "up",
    "↓": "down",
    "←": "left",
    "→": "right",
    "⇧": "shift+",
  };
  for (const [sym, replacement] of Object.entries(symbolMap)) {
    result = result.replace(sym, replacement);
  }
  // Handle combined arrow notation like "↑↓→←"
  if (result.includes("arrows")) result = "arrows";
  // Handle shift+key notation like "shift+D" → "shift+d"
  result = result.replace(/shift\+([a-z0-9])/g, (_, c) => "shift+" + c.toLowerCase());
  // Handle ctrl+key notation like "c-o" → "ctrl+o"
  result = result.replace(/^c-([a-z0-9])$/i, (_, c) => "ctrl+" + c.toLowerCase());
  // Handle function keys like F1/F10 → f1/f10
  result = result.replace(/^f(\d+)$/i, (_, n) => `f${n}`);
  return result;
}

/**
 * Detect popup overlays: centered bordered boxes that don't span the full width.
 */
export function detectPopups(grid, lines) {
  const popups = [];
  const cols = grid[0]?.length || 80;
  const rows = lines.length;

  // Find top borders of boxes (┌───┐ pattern) that are narrower than the screen
  for (let y = 0; y < rows; y++) {
    const rowCells = grid[y] || [];
    let firstCorner = -1;
    let lastCorner = -1;

    // Find ┌ and ┐ on the same line
    for (let x = 0; x < rowCells.length; x++) {
      const ch = rowCells[x]?.char;
      if (ch === "┌" || ch === "╭" || ch === "┏") {
        firstCorner = x;
      }
      if (ch === "┐" || ch === "╮" || ch === "┓") {
        lastCorner = x;
      }
    }

    if (firstCorner >= 0 && lastCorner > firstCorner && lastCorner - firstCorner < cols * 0.8) {
      // This is a top border that doesn't span the full width — could be a popup
      // But skip if it starts at column 0 or 1 (that's a pane, not a popup)
      if (firstCorner <= 1) continue;

      const width = lastCorner - firstCorner;

      // Check if it's centered (not at the edge)
      const centered = firstCorner > 5 && lastCorner < cols - 5;

      // Extract title from the border
      let title = "";
      for (let x = firstCorner + 1; x < lastCorner; x++) {
        const ch = rowCells[x]?.char;
        if (ch && ch !== "─" && ch !== "━" && ch !== "═") {
          title += ch;
        }
      }
      title = title.trim();

      // Find the bottom border
      let bottomY = y;
      for (let by = y + 1; by < rows; by++) {
        const bRow = grid[by] || [];
        const leftChar = bRow[firstCorner]?.char;
        const rightChar = bRow[lastCorner]?.char;
        if ((leftChar === "└" || leftChar === "╰" || leftChar === "┗") &&
            (rightChar === "┘" || rightChar === "╯" || rightChar === "┛")) {
          bottomY = by;
          break;
        }
      }

      popups.push({
        id: title ? `popup_${title.replace(/\s+/g, "_")}` : `popup_${y}`,
        role: "popup",
        title: title || undefined,
        centered,
        bounds: { startY: y, endY: bottomY },
        confidence: centered ? 0.9 : 0.7,
        evidence: [lines[y]?.substring(0, 60) || "popup border"],
      });
    }
  }

  return popups;
}

// ── Fix 3: Expanded App Guesser ───────────────────────────────────────────

export function guessApplication(command, lines, grid) {
  const base = path.basename(command || "");
  let guess = "unknown";
  let confidence = 0;
  let framework = "unknown";

  // Phase 1: Known command names
  const KNOWN_APPS = {
    top: "top", btop: "btop", htop: "htop",
    vim: "vim", vi: "vim", nvim: "vim",
    hx: "helix", helix: "helix",
    less: "less", more: "less",
    tmux: "tmux", git: "git", nano: "nano",
    gitui: "gitui", lazygit: "lazygit",
    tig: "tig",
    yazi: "yazi", csvlens: "csvlens",
    ncdu: "ncdu", posting: "posting",
    harlequin: "harlequin", trip: "trippy",
    ttysolitaire: "tty-solitaire",
    nsnake: "nsnake", nudoku: "nudoku",
    nethack: "nethack", greed: "greed",
    lf: "lf", moar: "moar", glow: "glow", broot: "broot",
    cbonsai: "cbonsai", fzf: "fzf",
  };

  if (KNOWN_APPS[base]) {
    guess = KNOWN_APPS[base];
    confidence = 0.9;
  }

  // Phase 2: Screen content heuristics (if command name didn't match)
  if (confidence === 0 && lines.length > 0) {
    const text = lines.join("\n");
    const allText = text.toLowerCase();
    const nonEmptyLines = lines.filter(line => line && line.trim().length > 0);
    const lastLine = nonEmptyLines[nonEmptyLines.length - 1] || "";
    const hasBoxDrawing = grid ? grid.some(row => row.some(c => BOX_DRAWING.has(c.char))) : false;
    const boxCount = grid ? grid.reduce((sum, row) =>
      sum + row.filter(c => BOX_DRAWING.has(c.char)).length, 0) : 0;
    const roundedBorders = grid ? grid.some(row => row.some(c =>
      c.char === "╭" || c.char === "╮" || c.char === "╰" || c.char === "╯")) : false;
    const hasTildeLines = lines.filter(line => /^~(?:\s|$)/.test(line)).length >= 3;
    const hasHelixMode = /\b(?:NOR|INS|SEL)\b/.test(lastLine) || /\b(?:NOR|INS|SEL)\b/.test(text);
    const hasVimMode = /--\s*(INSERT|VISUAL|NORMAL|SELECT|REPLACE|COMMAND)\s*--/i.test(text) ||
      /\b(?:NORMAL|INSERT|VISUAL|SELECT|REPLACE|COMMAND)\b/i.test(lastLine);
    const hasFKeyBar = nonEmptyLines.some(line =>
      /(F1|F2|F3|F4|F5|F6|F7|F8|F9|F10)/i.test(line) &&
      /\b(Help|Setup|Quit|Menu|Search|Filter|Options|Info)\b/i.test(line));
    const hasPermissions = /(?:^|\s)[dl-][rwx-]{9}(?:\s|$)/i.test(allText);
    const hasTreeMarkers = /[├└│]/.test(text);
    const hasMarkdown = /(^|\n)\s{0,3}#{1,6}\s+\S|(^|\n)\s{0,3}(?:\*\*|__|`)/m.test(text);
    const hasDescriptiveExit = /press\s+esc\s*(?:\/\s*q)?\s*to\s*(?:exit|quit)/i.test(text) ||
      /press\s+q\s*to\s*(?:exit|quit)/i.test(text);
    const hasKeyHintBar = nonEmptyLines.some(line =>
      /\[[^\]]+\]\s*[A-Za-z]/.test(line) ||
      /<([A-Za-z0-9_-]+)>/.test(line) ||
      /└┘\s*[A-Za-z0-9↵⏎↑↓←→]+/.test(line) ||
      /\^[a-zA-Z]\s+\w/.test(line) ||
      /\b[a-z]\s+[A-Z][a-z]+\s{2,}[a-z]\s+[A-Z]/.test(line));

    // App-specific signatures
    if (allText.includes("ncdu") && allText.includes("disk usage")) {
      guess = "ncdu"; confidence = 0.85;
    } else if (allText.includes("posting") && allText.includes("curl command")) {
      guess = "posting"; confidence = 0.85;
    } else if (allText.includes("trippy") && allText.includes("icmp")) {
      guess = "trippy"; confidence = 0.85;
    } else if (allText.includes("harlequin") && allText.includes("sql")) {
      guess = "harlequin"; confidence = 0.8;
    } else if (allText.includes("htop") && hasFKeyBar) {
      guess = "htop"; confidence = 0.9;
    } else if (allText.includes("tig") && hasBoxDrawing) {
      guess = "tig"; confidence = 0.85;
    } else if (/commit\s+[0-9a-f]{7,40}/i.test(text) && /author:/i.test(text) && !hasBoxDrawing) {
      guess = "git log"; confidence = 0.8;
    } else if (hasTildeLines && hasHelixMode) {
      guess = "helix"; confidence = 0.85;
    } else if (hasTildeLines && hasVimMode) {
      guess = "vim"; confidence = 0.8;
    } else if (hasDescriptiveExit) {
      guess = "moar"; confidence = 0.85;
    } else if (hasMarkdown && (allText.includes("glow") || /(^|\n)\s{0,3}(#{1,6}\s|[-*+]\s|```)/m.test(text))) {
      guess = "glow"; confidence = 0.8;
    } else if (hasPermissions && hasTreeMarkers) {
      guess = "broot"; confidence = 0.8;
    } else if (hasPermissions && /\/[^\s]+/.test(text)) {
      guess = "lf"; confidence = 0.75;
    } else if (allText.includes("gitui") || (allText.includes("status") && allText.includes("log") && allText.includes("stashing"))) {
      guess = "gitui"; confidence = 0.7;
    } else if (allText.includes("scenario dashboard") && hasBoxDrawing) {
      // Garazyk Scenario Dashboard: title + box drawing + service list
      guess = "dashboard"; confidence = 0.85;
    } else if (allText.includes("yazi") || allText.includes("terminal response timeout")) {
      guess = "yazi"; confidence = 0.7;
    } else if (lines.some(l => /^>/.test(l.trim())) && lines.some(l => /[▌▐]/.test(l)) && /\d+\/\d+/.test(text)) {
      // fzf: prompt line + cursor indicator + result counter
      guess = "fzf"; confidence = 0.85;
    } else if (allText.includes("tasks:") && allText.includes("load avg")) {
      guess = "top"; confidence = 0.7;
    } else if (allText.includes("vim - vi improved")) {
      guess = "vim"; confidence = 0.7;
    } else if (allText.includes("gnu nano")) {
      guess = "nano"; confidence = 0.8;
    } else if (allText.includes("commit ") && /[0-9a-f]{7,40}/.test(allText) && allText.includes("author:")) {
      guess = "git log"; confidence = 0.8;
    } else if (/\[\d+\].*:\w+\*/.test(text)) {
      // tmux: "[0] 0:bash*"
      guess = "tmux"; confidence = 0.7;
    }

    // Generic TUI detection
    if (confidence === 0 && grid) {
      const hasTabs = lines.some(l => /\[\d+\]/.test(l));
      const hasStatusBar = lines.length > 0 && /\[[a-z]\]|\^[a-z]|ctrl\+/i.test(lines[lines.length - 1] || "");

      if (hasBoxDrawing && hasTabs) {
        guess = "tui_panels_tabs"; confidence = 0.6;
      } else if (hasBoxDrawing) {
        guess = "tui_panels"; confidence = 0.5;
      } else if (hasStatusBar) {
        guess = "tui_app"; confidence = 0.4;
      }
    }
  }

  // Phase 3: Framework detection
  if (grid) {
    const text = lines.join("\n");
    const lowerText = text.toLowerCase();
    const nonEmptyLines = lines.filter(line => line && line.trim().length > 0);
    const lastLine = nonEmptyLines[nonEmptyLines.length - 1] || "";
    const hasBoxDrawing = grid.some(row => row.some(c => BOX_DRAWING.has(c.char)));
    const boxCount = grid.reduce((sum, row) =>
      sum + row.filter(c => BOX_DRAWING.has(c.char)).length, 0);
    const roundedBorders = grid.some(row => row.some(c =>
      c.char === "╭" || c.char === "╮" || c.char === "╰" || c.char === "╯"));
    const hasFKeyBar = nonEmptyLines.some(line =>
      /(F1|F2|F3|F4|F5|F6|F7|F8|F9|F10)/i.test(line) &&
      /\b(Help|Setup|Quit|Menu|Search|Filter|Options|Info)\b/i.test(line));
    const hasKeyHintBar = nonEmptyLines.some(line =>
      /\[[^\]]+\]\s*[A-Za-z]/.test(line) ||
      /<([A-Za-z0-9_-]+)>/.test(line) ||
      /└┘\s*[A-Za-z0-9↵⏎↑↓←→]+/.test(line) ||
      /\b(Press|Quit|Exit|Help)\b/i.test(line));
    const hasVimSignature = /--\s*(INSERT|VISUAL|NORMAL|SELECT|REPLACE|COMMAND)\s*--/i.test(text) ||
      (lines.filter(line => /^~(?:\s|$)/.test(line)).length >= 3 && /\b(?:NORMAL|INSERT|VISUAL|SELECT|REPLACE|COMMAND)\b/i.test(lastLine));
    const hasBubbleteaSignature = /press\s+esc\s*(?:\/\s*q)?\s*to\s*(?:exit|quit)/i.test(text) ||
      /press\s+q\s*to\s*(?:exit|quit)/i.test(text);
    const frameworkByApp = {
      htop: "ncurses",
      tig: "ncurses",
      ncdu: "ncurses",
      nsnake: "ncurses",
      nudoku: "ncurses",
      nethack: "ncurses",
      greed: "ncurses",
      vim: "vim",
      helix: "ratatui",
      gitui: "ratatui",
      lazygit: "ratatui",
      yazi: "ratatui",
      btop: "ratatui",
      broot: "ratatui",
      csvlens: "ratatui",
      cbonsai: "ratatui",
      lf: "bubbletea",
      moar: "bubbletea",
      glow: "bubbletea",
      fzf: "bubbletea",
      posting: "textual",
      harlequin: "textual",
      dashboard: "ratatui",
    };

    if (frameworkByApp[guess]) {
      framework = frameworkByApp[guess];
    } else if (hasVimSignature) {
      framework = "vim";
    } else if (hasFKeyBar || /\bncurses\b|\bcurses\b/i.test(text)) {
      framework = "ncurses";
    } else if (hasBubbleteaSignature || (hasBoxDrawing && /press\s+.*(exit|quit)/i.test(text))) {
      framework = "bubbletea";
    } else if ((boxCount > 20 && (hasKeyHintBar || roundedBorders)) ||
               (hasBoxDrawing && hasKeyHintBar) ||
               (hasBoxDrawing && boxCount > 10) ||
               /\b(ratatui|tui|terminal ui)\b/i.test(text)) {
      framework = "ratatui";
    }

    // Textual apps use ^c, ^j, ^s notation in status bar
    if (framework === "unknown" && (/\^[a-z]/i.test(lastLine) || /ctrl\+[a-z]/i.test(lastLine))) {
      framework = "textual";
    }
  }

  return { app: guess, confidence, framework };
}

// ── Existing Detectors (kept, improved) ────────────────────────────────────

export function detectStatusLines(grid, lines) {
  const facts = [];
  const rows = grid.length;
  if (rows === 0) return facts;

  const lastLine = lines[rows - 1];
  const firstLine = lines[0];

  if (lastLine && lastLine.includes("-- INSERT --")) {
    facts.push({ label: "Mode", value: "Insert", sourceBounds: { startY: rows - 1, endY: rows - 1 }, confidence: 0.9 });
  } else if (lastLine && lastLine.includes("-- VISUAL --")) {
    facts.push({ label: "Mode", value: "Visual", sourceBounds: { startY: rows - 1, endY: rows - 1 }, confidence: 0.9 });
  } else if (lastLine && lastLine.includes("-- NORMAL --")) {
    facts.push({ label: "Mode", value: "Normal", sourceBounds: { startY: rows - 1, endY: rows - 1 }, confidence: 0.9 });
  } else if (lastLine && lastLine.trim() === ":" && lastLine.length > 0) {
    facts.push({ label: "Mode", value: "Command", sourceBounds: { startY: rows - 1, endY: rows - 1 }, confidence: 0.6 });
  }

  // Helix mode indicator: "NOR" (Normal), "INS" (Insert), "SEL" (Select)
  // Appears on the status bar line, not the last line
  for (let y = Math.max(0, rows - 3); y < rows; y++) {
    const line = lines[y];
    if (!line) continue;
    const helixMatch = line.match(/\b(NOR|INS|SEL)\b/);
    if (helixMatch) {
      const modeMap = { NOR: "Normal", INS: "Insert", SEL: "Select" };
      facts.push({ label: "Mode", value: modeMap[helixMatch[1]] || helixMatch[1], sourceBounds: { startY: y, endY: y }, confidence: 0.85 });
      break;
    }
  }

  if (firstLine && firstLine.includes("top -")) {
    facts.push({ label: "Header", value: "System top", sourceBounds: { startY: 0, endY: 0 }, confidence: 0.9 });
  }

  // Detect alt screen mode from content patterns
  if (rows > 0 && lines.every(l => l.trim().length > 0 || l === "")) {
    // Full-screen app with content — likely in alt screen
    facts.push({ label: "TerminalMode", value: "alt_screen", sourceBounds: { startY: 0, endY: rows - 1 }, confidence: 0.5 });
  }

  return facts;
}

export function detectTables(grid, lines) {
  const tables = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line.match(/PID\s+USER\s+PR\s+NI\s+VIRT\s+RES/i) ||
        line.match(/PID\s+COMMAND\s+%CPU\s+TIME/i) ||
        line.match(/NAME\s+(SIZE|AGE|CITY|SCORE)/i) ||
        line.match(/#\s+HOST\s+.*LOSS/i) ||  // trippy
        line.match(/\s+\d+\s+\d+\s+/)) {     // generic numeric columns
      tables.push({
        id: `table_${i}`,
        role: "table",
        columns: line.trim().split(/\s{2,}/),
        bounds: { startY: i, endY: Math.min(i + 20, lines.length - 1) },
        confidence: 0.8,
        evidence: [line.substring(0, 80)],
      });
      break;
    }
  }
  return tables;
}

export function detectContainers(grid, lines) {
  const regions = [];
  const vimBlankStart = lines.findIndex(l => l.startsWith("~"));
  if (vimBlankStart !== -1) {
    let end = vimBlankStart;
    while (end < lines.length && lines[end].startsWith("~")) {
      end++;
    }
    regions.push({
      id: "filler",
      role: "empty_space",
      bounds: { startY: vimBlankStart, endY: end - 1 },
      confidence: 0.8,
      evidence: ["~ lines"],
    });
  }
  return regions;
}

export function detectControls(grid, lines) {
  const controls = [];
  const rows = lines.length;

  for (let i = 0; i < rows; i++) {
    const line = lines[i];
    if (!line) continue;

    // Checkboxes
    const checkboxRegex = /\[[ xX]\]|\([ *]\)/g;
    let match;
    while ((match = checkboxRegex.exec(line)) !== null) {
      controls.push({
        role: "checkbox",
        bounds: { startY: i, endY: i },
        confidence: 0.8,
        label: line.substring(match.index + match[0].length).split("  ")[0].trim() || match[0],
        evidence: [line.substring(0, 60)],
      });
    }

    // Buttons
    const buttonRegex = /\[\s+[A-Za-z0-9_]+\s+\]|\<\s*[A-Za-z0-9_]+\s*\>/g;
    while ((match = buttonRegex.exec(line)) !== null) {
      controls.push({
        role: "button",
        bounds: { startY: i, endY: i },
        confidence: 0.8,
        label: match[0],
        evidence: [line.substring(0, 60)],
      });
    }
  }

  // Input fields (underline/inverse runs)
  for (let y = 0; y < rows; y++) {
    let inputStart = -1;
    let runLength = 0;
    const rowCells = grid[y] || [];
    for (let x = 0; x < rowCells.length; x++) {
      const cell = rowCells[x];
      if (cell.underline || cell.inverse) {
        if (inputStart === -1) inputStart = x;
        runLength++;
      } else {
        if (runLength > 4) {
          // Extract the text content of the input field
          const label = rowCells.slice(inputStart, inputStart + runLength)
            .map(c => c.char).join("").trim();
          controls.push({
            role: "input",
            bounds: { startY: y, endY: y },
            confidence: 0.7,
            label: label || "Input field",
            evidence: ["Styled cells"],
          });
        }
        inputStart = -1;
        runLength = 0;
      }
    }
    if (runLength > 4) {
      const label = rowCells.slice(inputStart, inputStart + runLength)
        .map(c => c.char).join("").trim();
      controls.push({
        role: "input",
        bounds: { startY: y, endY: y },
        confidence: 0.7,
        label: label || "Input field",
        evidence: ["Styled cells"],
      });
    }
  }

  return controls;
}

// ── Fix 4: Snapshot Diff ──────────────────────────────────────────────────

/**
 * Compare two semantic snapshots and return what changed.
 * Used in the VERIFY step to detect if an action had an effect.
 */
export function diffSnapshots(before, after) {
  if (!before || !after) return { anyChange: false };

  // Cursor movement
  const cursorMoved =
    before.cursor?.x !== after.cursor?.x ||
    before.cursor?.y !== after.cursor?.y;

  // Content change — compare line-by-line
  const beforeLines = before.lines || [];
  const afterLines = after.lines || [];
  const changedLineIndices = [];
  const maxLen = Math.max(beforeLines.length, afterLines.length);
  for (let i = 0; i < maxLen; i++) {
    if ((beforeLines[i] || "") !== (afterLines[i] || "")) {
      changedLineIndices.push(i);
    }
  }

  // Tab change
  const beforeTabs = before.tabs?.[0]?.tabs?.map(t => `${t.label}:${t.active}`).join(",") || "";
  const afterTabs = after.tabs?.[0]?.tabs?.map(t => `${t.label}:${t.active}`).join(",") || "";
  const tabsChanged = beforeTabs !== afterTabs;

  // Active tab changed
  const beforeActiveTab = before.tabs?.[0]?.tabs?.find(t => t.active)?.label;
  const afterActiveTab = after.tabs?.[0]?.tabs?.find(t => t.active)?.label;
  const activeTabChanged = beforeActiveTab !== afterActiveTab;

  // Popup appeared/disappeared
  const beforePopups = before.popups?.length || 0;
  const afterPopups = after.popups?.length || 0;
  const popupsChanged = beforePopups !== afterPopups;

  // Selection changed
  const beforeSelected = before.lists?.filter(l => l.selected)?.map(l => l.label).join(",") || "";
  const afterSelected = after.lists?.filter(l => l.selected)?.map(l => l.label).join(",") || "";
  const selectionChanged = beforeSelected !== afterSelected;

  // Status bar changed
  const beforeStatus = before.statusBars?.[0]?.evidence?.[0] || "";
  const afterStatus = after.statusBars?.[0]?.evidence?.[0] || "";
  const statusBarChanged = beforeStatus !== afterStatus;

  const anyChange = cursorMoved || changedLineIndices.length > 0 ||
    tabsChanged || popupsChanged || selectionChanged || statusBarChanged;

  return {
    anyChange,
    cursorMoved,
    cursorBefore: before.cursor,
    cursorAfter: after.cursor,
    changedLineIndices,
    changedLineCount: changedLineIndices.length,
    tabsChanged,
    activeTabChanged,
    activeTabBefore: beforeActiveTab,
    activeTabAfter: afterActiveTab,
    popupsChanged,
    popupCountBefore: beforePopups,
    popupCountAfter: afterPopups,
    selectionChanged,
    selectedBefore: beforeSelected,
    selectedAfter: afterSelected,
    statusBarChanged,
  };
}

// ── VDOM Builder (improved) ───────────────────────────────────────────────

export function buildTuiVdom(snapshot, rows) {
  const root = {
    type: "Container",
    role: "screen",
    bounds: { startY: 0, endY: rows - 1 },
    children: [],
  };

  const allElements = [];

  if (snapshot.regions) {
    snapshot.regions.forEach(r => allElements.push({ type: "Region", role: r.role, label: r.id, bounds: r.bounds, tabs: r.tabs }));
  }
  if (snapshot.tables) {
    snapshot.tables.forEach(t => allElements.push({ type: "Table", role: "table", label: t.id, bounds: t.bounds, columns: t.columns }));
  }
  if (snapshot.controls) {
    snapshot.controls.forEach(c => allElements.push({ type: "Control", role: c.role, label: c.label, bounds: c.bounds }));
  }
  if (snapshot.facts) {
    snapshot.facts.forEach(f => allElements.push({ type: "Fact", role: "fact", label: `${f.label}: ${f.value}`, bounds: f.sourceBounds }));
  }
  if (snapshot.tabs) {
    snapshot.tabs.forEach(t => allElements.push({ type: "TabBar", role: "tab_bar", label: t.tabs?.map(tb => `${tb.label}[${tb.index}]`).join("|"), bounds: t.bounds, tabs: t.tabs }));
  }
  if (snapshot.panes) {
    snapshot.panes.forEach(p => allElements.push({ type: "Pane", role: p.role, label: p.title || p.id, bounds: p.bounds }));
  }
  if (snapshot.lists) {
    snapshot.lists.forEach(l => {
      if (l.role === "list") {
        allElements.push({ type: "List", role: "list", label: `List(${l.items?.length || 0} items)`, bounds: l.bounds });
      } else {
        allElements.push({ type: "ListItem", role: "list_item", label: l.label, bounds: l.bounds, selected: l.selected, marker: l.marker });
      }
    });
  }
  if (snapshot.statusBars) {
    snapshot.statusBars.forEach(s => allElements.push({ type: "StatusBar", role: "status_bar", label: s.keybindings?.join(", ") || "status", bounds: s.bounds }));
  }
  if (snapshot.popups) {
    snapshot.popups.forEach(p => allElements.push({ type: "Popup", role: "popup", label: p.title || "popup", bounds: p.bounds, centered: p.centered }));
  }

  // Sort by size descending
  allElements.sort((a, b) => {
    const sizeA = (a.bounds?.endY || 0) - (a.bounds?.startY || 0);
    const sizeB = (b.bounds?.endY || 0) - (b.bounds?.startY || 0);
    return sizeB - sizeA;
  });

  // Nest elements
  for (const el of allElements) {
    if (!el.bounds) continue;
    let parent = root;
    let foundContainer = true;
    while (foundContainer) {
      foundContainer = false;
      if (!parent.children) parent.children = [];
      for (const child of parent.children) {
        if (child.bounds && el.bounds.startY >= child.bounds.startY && el.bounds.endY <= child.bounds.endY) {
          if (child !== el) {
            parent = child;
            foundContainer = true;
            break;
          }
        }
      }
    }
    if (!parent.children) parent.children = [];
    parent.children.push(el);
  }

  return root;
}

export function visualizeTuiVdom(node, prefix = "", isLast = true, isRoot = true) {
  let out = "";

  const startY = node.bounds?.startY ?? 0;
  const endY = node.bounds?.endY ?? 0;
  const boundsStr = `[${startY}..${endY}]`;

  const typeStr = node.type ? `${node.type} ` : "Container ";
  const roleStr = node.role ? `"${node.role}" ` : "";
  const labelStr = node.label ? `(${node.label}) ` : "";
  const extraStr = node.selected ? "★" : "";
  const tabStr = node.tabs ? ` tabs=[${node.tabs.map(t => t.active ? `*${t.label}*` : t.label).join(",")}]` : "";

  const line = `${typeStr}${roleStr}${labelStr}${extraStr}${boundsStr}${tabStr}`;

  if (isRoot) {
    out += line + "\n";
  } else {
    out += prefix + (isLast ? "└── " : "├── ") + line + "\n";
  }

  const newPrefix = isRoot ? "" : prefix + (isLast ? "    " : "│   ");

  if (node.children && node.children.length > 0) {
    node.children.sort((a, b) => (a.bounds?.startY || 0) - (b.bounds?.startY || 0));
    for (let i = 0; i < node.children.length; i++) {
      out += visualizeTuiVdom(node.children[i], newPrefix, i === node.children.length - 1, false);
    }
  }

  return out;
}

// ── Build Semantic Snapshot (improved) ────────────────────────────────────

export function buildSemanticSnapshot(session, detail = "compact", includePrompt = false) {
  const buffer = session.term.buffer.active;
  const cols = session.cols;
  const rows = session.rows;

  // Get raw lines
  const lines = [];
  for (let row = 0; row < rows; row += 1) {
    const lineObj = buffer.getLine(buffer.viewportY + row);
    lines.push(lineObj ? lineObj.translateToString(true) : "");
  }

  const grid = extractGrid(buffer, cols, rows);
  const appGuess = guessApplication(session.command, lines, grid);

  // Run all detectors
  const facts = detectStatusLines(grid, lines);
  const tables = detectTables(grid, lines);
  const containers = detectContainers(grid, lines);
  const controls = detectControls(grid, lines);
  const tabs = detectTabs(grid, lines);
  const panes = detectPanes(grid, lines);
  const lists = detectLists(grid, lines);
  const statusBars = detectStatusBar(grid, lines);
  const popups = detectPopups(grid, lines);

  const regions = [...containers];

  // Terminal mode detection
  const normalBuffer = session.term.buffer.normal;
  const altScreen = buffer !== normalBuffer;

  const snapshot = {
    sessionId: session.sessionId,
    app: appGuess.app,
    confidence: appGuess.confidence,
    framework: appGuess.framework,
    cursor: { x: buffer.cursorX, y: buffer.cursorY },
    altScreen,
    facts,
    tables,
    regions,
    controls,
    tabs,
    panes,
    lists,
    statusBars,
    popups,
  };

  const vdom = buildTuiVdom(snapshot, rows);
  snapshot.vdomViz = "\n" + visualizeTuiVdom(vdom).trimEnd();

  // Build navigation capability map from detected elements
  snapshot.capabilities = buildCapabilityMap(snapshot);

  if (detail === "full") {
    snapshot.lines = lines;
  }

  const result = { snapshot };

  if (includePrompt) {
    result.prompt = buildAgentPrompt(appGuess.app);
  }

  return result;
}

export function buildAgentPrompt(appGuess) {
  return `You are a semantic analyzer for terminal UIs.
The user is requesting an interpretation of a terminal screen.
The terminal is currently running an application guessed to be: ${appGuess}.

Below is a structured "Semantic Snapshot" of the terminal buffer, including the raw text lines and deterministically detected regions, tables, controls, and facts.

Your task is to infer higher-level meaning from this evidence. For example:
- Identify what the user is currently looking at or doing.
- Point out any important warnings, errors, or prominent metrics.
- Determine the state of the application (e.g., editing a file, viewing a list, waiting for input).
- Decide which interactive controls are actionable.

Respond strictly in JSON matching this schema:
{
  "summary": "A brief 1-2 sentence summary of the screen state",
  "appState": "A short string describing the state (e.g., 'Normal mode', 'Viewing process list')",
  "keyMetrics": [{"name": "CPU Usage", "value": "12.3%"}],
  "warnings": ["Any warnings visible on screen"],
  "availableActions": ["A list of suggested tool calls to interact with the detected controls using pty_action"]
}
`;
}

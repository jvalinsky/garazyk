---
name: tui-semantic-recognition
description: Extract UI semantics, components, and interaction patterns from raw TUI buffer grids and asciicasts.
---

# TUI Semantic Recognition

Use this skill when you need to extract structural meaning from raw Terminal User Interfaces (TUIs), ASCIICasts, or MCP terminal snapshots where the underlying DOM/VDOM is unavailable.

## When to Use

* You are given a raw terminal screenshot or asciicast and asked to describe its interface.
* You are writing an MCP tool or script to parse generic terminal program outputs (e.g., `top`, `vim`, `wttr.in`).
* You are building automated testing for TUIs that asserts on the presence of semantic elements (modals, tables, checkboxes).
* You are tasked with inferring available actions from a terminal screen.

## The Two-Layer Model

When analyzing a TUI, we use a two-layer extraction model. Try to use Layer 1 if possible; if you are looking at raw output from a third-party tool, use Layer 2.

### Layer 1: App Metadata (White-Box)

If you have source access to the TUI (e.g., a React/Ink app, BubbleTea, Textual):
* **Do not parse the text.** Instead, inject a side-channel metadata map during the render cycle.
* Attach `semanticRole`, `interactable`, and `states` metadata directly to the UI elements.
* The snapshot builder should export this metadata alongside the raw text grid, enabling zero-parsing extraction.

### Layer 2: Generic BufferScanner (Black-Box)

If you are analyzing raw terminal grids from standard Linux/macOS tools:

#### 1. Unicode Semantic Roles

Classify characters to infer UI structure. Nearly all TUIs use standard Unicode mapping:
* **Box Drawing (U+2500 - U+257F)**: Defines Containers, Tables, Modals, and Dividers (`┌`, `┐`, `└`, `┘`, `├`, `┤`, `┬`, `┴`, `┼`, `─`, `│`).
* **Block Elements (U+2580 - U+259F)**: Defines Scrollbars, Progress Bars, and Active Selections (`█`, `▓`, `▒`, `░`).
* **Geometric Shapes (U+25A0 - U+25FF)**: Acts as Bullet points, Tree expanders, or Radio buttons (`■`, `□`, `▼`, `▶`).
* **Controls**: Look for Checkboxes (`[ ]`, `[x]`, `(*)`) and Buttons (`< Submit >`, `[ OK ]`).

#### 2. Container and Table Detection

When parsing a raw grid for structures, follow these algorithms:
* **Containers (Modals/Panels)**: Find a corner character (e.g., `┌`). Trace continuous vertical and horizontal borders to find the corresponding corners (`┐`, `└`, `┘`). The enclosed space is a rectangular `Container`.
* **Tables/Grids**: Inside a container, look for intersection characters (`┬`, `┴`, `├`, `┤`, `┼`). These subdivide a container into a table or grid of `Cells`.
* **Lists**: Identify rows with leading marker characters (bullets, shapes) aligned on the same column.

#### 3. Interaction Detection

To determine what elements the user can interact with or what state the app is in:
* **Cursor**: The terminal's hardware cursor `(cursorX, cursorY)` frequently indicates the active input field or selection.
* **Styling**: `Inverse` or `Underline` ANSI styling is universally used to denote the focused element or a selected row.
* **Status Lines**: Look at the absolute top or bottom line of the buffer. Patterns like `-- INSERT --`, `top -`, or `:` suggest specific application modes (Vim, Top, Less, etc.).

## Output Representation

When distilling a TUI, group the findings hierarchically into a "TuiElement Tree" (VDOM). For example, a parsed screen should be structured as:
* `Container` (e.g., Main App)
  * `Table` (e.g., Weather Report)
    * `Cell` (e.g., Morning)
    * `Cell` (e.g., Noon)
  * `Controls` (e.g., Checkboxes or Buttons)
  * `GameBoard` (e.g., arena with wall chars)
  * `Player` (e.g., @ character)
  * `GameEntity` (e.g., snake body, food, bonus)
  * `CardGame` (e.g., solitaire with card faces/backs)
  * `CardFace` (e.g., K♥, 5♦ with rank/suit/suitColor)

## Game Element Detection

Games require specialized detection beyond standard UI patterns:

### Board Games (nsnake, nethack)
- **Game board**: Bordered area with wall characters (▒░█)
- **Player**: `@` character (roguelike convention)
  - Single `@` → player
  - Multiple `@` with game board → pick colored fg
  - Multiple `@` without board → skip (ASCII art)
- **Body segments**: `o`/`O` only inside bordered game boards
- **Food**: `$`, `★`, `♥`, `♦` characters
- **Score bar**: Lines with Score/Level/Speed/Lives patterns

### Card Games (tty-solitaire)
- **Card faces**: Two formats:
  - Rank+suit: `K♥`, `10♠`, `A♣` (top of cascade)
  - Suit+rank: `♥K`, `♠10`, `♣A` (below in cascade)
- **Card backs**: Small bordered boxes `┌─────┐` with green background
- **Pile detection**: Group by x-position (~8-char columns)
  - Stock: top-left card backs
  - Waste: top-row face-up cards (left side)
  - Foundations: top-row face-up cards (right side, x > 50%)
  - Tableau: columns with face-up cards below top row
- **Suit colors**: ♥♦ = red (fg=1), ♣♠ = black (fg=7)

## Screen State Extraction

When the semantic snapshot doesn't provide enough structured data,
parse raw screen lines to build a state model. This is the technique
used by the solitaire AI player and generalizes to any structured TUI.

### Pattern: Position-Based State Extraction

1. **Identify structural regions** by x/y position:
   - Top row: stock, waste, foundations (card games)
   - Main area: tableau columns, list items, table rows
   - Bottom row: status bar, key hints

2. **Find character patterns** that mark elements:
   - Card faces: `([2-9]|10|J|Q|K|A)[♠♥♦♣]` or `[♠♥♦♣]([2-9]|10|J|Q|K|A)`
   - List markers: `▸`, `▾`, `>`, Nerd Font icons
   - Cell borders: `│`, `┃`, `|`
   - Selection highlight: inverse styling, `> ` prefix

3. **Group by position** into semantic collections:
   - Same x-position → same column/pile
   - Adjacent y-positions → same group
   - Position relative to screen center → left/right role

4. **Build a state object** with:
   - `legalMoves()` — enumerate all valid actions
   - `applyMove(move)` — return new state after action (immutable)
   - `clone()` — deep copy for search tree exploration
   - `isWon` / `isStuck` — terminal condition detection

### Generalization Table

| TUI Type | State Elements | Position Heuristic | Pattern |
|----------|---------------|-------------------|---------|
| Card games | cards, piles, foundations | x-position → pile role | rank+suit regex |
| File managers | files, dirs, selection | column → pane, y → item | icon+name regex |
| Process monitors | processes, CPU, mem | column → field, y → process | fixed-width fields |
| Git UIs | files, diffs, staging | panel → role, y → item | status prefix |
| Form editors | fields, values, validation | y → field, x → label/value | `: ` separator |

### Example: Solitaire Screen Parser

```javascript
function parseScreen(lines, cols) {
  const state = new GameState();
  const cardPattern = /([2-9]|10|J|Q|K|A)([♠♥♦♣])/g;
  const suitFirstPattern = /([♠♥♦♣])([2-9]|10|J|Q|K|A)/g;

  for (let y = 0; y < lines.length; y++) {
    const line = lines[y];
    // Find all card faces in this line
    // Group by x-position into columns
    // Top row (y < 5): stock/waste/foundations
    // Main area (y >= 5): tableau columns
    // Face-down cards: ┌─────┐ pattern
  }
  return state;
}
```

This pattern applies to any TUI where the screen layout maps to a
structured domain model. The key insight: **position is semantics** in
TUIs — where something appears on screen determines what it means.

## Chart Detection

TUI monitoring apps render data visualizations using terminal characters:

### Braille Charts (btop, trippy)
- **Characters**: U+2800–U+28FF (⣀⢀⡀⢠⣤⣶⣷⠸⡿⠁)
- **Sparkline**: 2D chart with few chars per line, multiple aligned rows
  - Example: btop network graph (⢀⣸ / ⠈⢹ across 2 rows)
  - Detection: ≥3 Braille chars per line, aligned x-positions (variance < 3)
- **Bar chart**: Inline Braille bars next to labels/values
  - Example: btop CPU cores ("C0 ⣀⣀⣀⣀⢠⢠ 40%")
  - Detection: ≥3 Braille chars per line, varying x-positions
- **Filtering**: Process list inline bars are excluded by checking x-alignment
  variance across lines (unaligned = table, not chart)

### Block Bars (btop, progress indicators)
- **Characters**: ■ █ ▓ ▒ ░
- **Pattern**: label + block chars + percentage/value
  - Example: "CPU ■■■■■■■■■■ 24%"
  - Example: "Used ⢠⣤ 7.01 GiB" (Braille bar with memory value)
- **Detection**: Regex matching label + block/Braille chars + value

### Pipe Meters (htop)
- **Pattern**: `label[||||||    XX.X%]`
- **Characters**: `|` (pipe) inside brackets
- **Example**: "0[||||||||||               26.2%]"
- **Example**: "Mem[|||||||||||||||||||||11.9G/16.0G]"
- **Detection**: Regex `(\w+)\[([|]+)\s*([^\]]+)\]`
- **Multiple meters**: htop pairs CPU cores on same line (e.g., "0[|||] 4[|||]")

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

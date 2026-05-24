# Semantic TUI Extraction: Virtual DOM for Terminals

## The Problem

Terminal User Interfaces (TUIs) render as grids of styled characters. Unlike HTML, the output is a
flat raster — every structural tree is lost by the time cells hit the screen. To build AI agents
that can interact with TUIs semantically (not by pixel coordinates), we need to reconstruct that
tree from the rendered output.

This document defines a **two-layer semantic extraction model** that recovers structured element
metadata from TUI output, drawing on patterns from six major TUI frameworks.

---

## The Two-Layer Model

```
┌─────────────────────────────────────────────────────────────┐
│                     Layer 1: Application Metadata            │
│  Widget Tree ──→ Layout ──→ Position Map ──→ Element Meta   │
│  (rich, accurate, own-TUI only)                             │
├─────────────────────────────────────────────────────────────┤
│                     Layer 2: Generic Buffer Scanner          │
│  Raw Cells ──→ Char Classify ──→ Region Detect ──→ VDOM    │
│  (heuristic, universal, any TUI)                            │
├─────────────────────────────────────────────────────────────┤
│                  Agent Snapshot (TuiElement tree)            │
│  roles, bounds, interactable, states, actions, children     │
└─────────────────────────────────────────────────────────────┘
```

### Layer 1 — Application Metadata

For TUIs where you control the source code (like Garazyk's dashboard), emit a side-channel
metadata map during rendering:

1. Walk the widget tree during `renderView()`
2. For each widget, record: `{ role, interactable, focused, states, bounds, ref }`
3. Store as `Map<string, ElementMeta>` on the ScreenBuffer before flushing to stdout
4. The snapshot builder reads from this map — zero character-level parsing needed

**Pattern source:** prompt_toolkit's `Screen.visible_windows_to_write_positions`
(`layout/screen.py:199`). Every Window that writes to the screen records its WritePosition,
making the render fully invertible.

### Layer 2 — Generic Buffer Scanner

For any TUI (including third-party programs), run a 3-stage pipeline on the raw character grid:

```
┌──────────────┐    ┌──────────────────┐    ┌──────────────────┐
│ 1. Character  │    │ 2. Region         │    │ 3. Semantic       │
│    Classify   │───→│    Detection      │───→│    Labeling       │
│ Per cell:     │    │ Connected-comp    │    │ Frame ─→ Panel    │
│ box-drawing   │    │ on border chars   │    │ Grid ─→ Table     │
│ block/shade   │    │ Flood-fill        │    │ Bullet ─→ List    │
│ geometric     │    │ content regions   │    │ Block ─→ Progress │
│ arrow         │    │ Column dividers   │    │ Inverse ─→ Status │
│ text          │    │ Section splits    │    │ [x] ─→ Checkbox   │
└──────────────┘    └──────────────────┘    └──────────────────┘
```

---

## TuiElement Virtual DOM Interface

The output of both layers is a tree of TuiElement nodes:

```typescript
interface TuiElement {
  // Identity
  type: "container" | "text" | "list" | "table" | "input" | "button"
      | "progress" | "checkbox" | "radio" | "scrollbar" | "status" | "heading";
  role: string;               // semantic ARIA-like role

  // Spatial
  bounds: { x: number; y: number; w: number; h: number };

  // Content
  content?: string;           // visible text, stripped of style
  label?: string;             // accessible label (from widget metadata)

  // Interaction
  interactable: boolean;
  focused: boolean;
  cursorPosition?: { x: number; y: number };
  actions: ElementAction[];   // what an agent can do here

  // State
  id: string;                 // stable ref
  states: string[];           // "selected", "disabled", "active", "expanded"
  style: { fg?: string; bg?: string; bold?: boolean; italic?: boolean };

  // Tree
  children: TuiElement[];
}

type ElementAction =
  | { type: "click" }
  | { type: "press_key"; key: string }
  | { type: "type"; hint?: string }
  | { type: "scroll"; direction: "up" | "down" }
  | { type: "toggle" }
  | { type: "focus" };
```

### YAML Representation

```yaml
- panel "@pds1" [role=service, state=online, ref=e3]
  - heading "Services"
  - list:
    - item "PDS 1" [state=online, interactable=true]
    - item "PDS 2" [state=offline, interactable=true]
```

---

## Framework Extraction Models

Each of the six libraries has a different "vdom" and extraction path:

| Framework | Vdom equivalent | How to extract |
|-----------|----------------|----------------|
| **Urwid** | `CompositeCanvas.shards` + widget tree | Walk shards; each `cview` has `attr_map` + `canvas`. Shard structure IS the composition tree. |
| **Textual** | DOMNode tree + WidgetPlacement[] | `walk_breadth_first()`, each node has `_css_type_names` (role), `region` from layout. Richest metadata. |
| **Ink** | DOMElement tree + Yoga positions | Walk `childNodes`, each has `yogaNode.getComputedLeft/Top/Width/Height()`. Fully invertible. |
| **Ratatui** | Buffer only | **Hardest** — no intermediate tree. Requires inverse analysis from final Cell grid. |
| **prompt_toolkit** | Container tree + visible_windows_to_write_positions | Screen dict maps each Window → WritePosition. Fragment markers tag interactable positions. |
| **BubbleTea** | Lipgloss layer tree + z-index | `comp.Render()` with named layers, z-index, hit-testing. Each layer has an ID. |

---

## Unicode-Based Structure Detection

Characters in specific Unicode ranges encode structural UI semantics. See
`docs/tui/unicode-ui-elements.md` for the complete reference.

**Classification by range:**

| Range | Characters | Encodes |
|-------|-----------|---------|
| U+2500-257F | `─│┌┐└┘├┤┬┴┼` etc. | **Borders, containers, tables** |
| U+2580-259F | `█▌▐░▒▓▄▀` | **Progress, scrollbars, focus state** |
| U+25A0-25FF | `●○■□▪▶▼◉◎` | **Bullets, radios, expand, selection** |
| U+2190-21FF | `←↑→↓↕▲▼` | **Scroll indicators, sort direction** |
| U+2610-2612 | `☐☑☒` | **Checkbox states** |
| U+2713-2718 | `✓✗✘` | **Check/cross marks** |

---

## Interaction Detection Heuristics

Determining whether an element is interactable combines six signals:

1. **Cursor position** — The terminal cursor is always on the currently focused element.
2. **Border style change** — Focus toggles border from plain (`┌─┐`) to thick (`┏━┓`) or
   changes border color.
3. **Fragment markers** — In framework pipelines like prompt_toolkit, `[SetCursorPosition]`
   in the fragment stream marks where click handling occurs.
4. **Unicode markers** — Certain characters ALWAYS mean interactivity:
   - `☐☑☒` → checkbox toggle
   - `◉◎○` → radio toggle
   - `▶▶▸▾` → expand/collapse
   - `[Text]` → button
   - Underlined chars → keyboard shortcut
5. **Widget tree query** — `Widget.selectable()` in Urwid; `is_focusable()` in prompt_toolkit;
   CSS pseudo-class `:focus` in Textual.
6. **Style inversion** — Inverse video (bg/fg swap) often indicates hover or focus.

---

## References

- [Unicode UI Element Reference](unicode-ui-elements.md) — complete character catalog
- [Agent Protocol](agent-protocol.md) — MCP tool schemas and agent workflows
- [MCP Implementation Plan](/.scratchpad/mcp-implementation-plan.md) — server gap fixes
- Urwid: `canvas.py` CompositeCanvas.shard model
- Textual: `dom.py` DOMNode, `layout.py` WidgetPlacement
- Ink: `dom.ts` DOMElement, `reconciler.ts` host config
- prompt_toolkit: `layout/screen.py` visible_windows_to_write_positions
- BubbleTea: `examples/clickable/main.go` layer compositor
- Deciduous node 881 (observation: Unicode encodes UI semantics)
- Deciduous node 888 (observation: two-layer extraction model)
- Deciduous node 895 (decision: TuiElement vdom interface)

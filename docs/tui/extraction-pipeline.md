# Semantic Extraction Pipeline

Detailed specification of the 3-stage pipeline for extracting a TuiElement tree from a raw
character buffer.

---

## Stage 1: Character Classification

### Input

A `ScreenBuffer` — a 2D grid of `(char, style, x, y)` cells plus cursor position.

### Output

A `CharToken[][]` — same dimensions, each cell classified into one of:

```typescript
type CharTokenType =
  // Border tokens — form containers and tables
  | "corner_tl" | "corner_tr" | "corner_bl" | "corner_br"
  | "edge_h" | "edge_v"
  | "tee_l" | "tee_r" | "tee_d" | "tee_u"    // T-junctions
  | "cross"                                      // ┼ grid intersection

  // Block tokens — indicate fills, progress, scroll
  | "block_full" | "block_half_l" | "block_half_r"
  | "block_qtr" | "shade_dark" | "shade_med" | "shade_light"

  // Interaction markers
  | "bullet" | "radio_on" | "radio_off"
  | "checkbox_on" | "checkbox_off" | "checkbox_mixed"
  | "expand_collapsed" | "expand_expanded"
  | "scroll_up" | "scroll_down" | "scroll_thumb"

  // Content
  | "whitespace" | "text" | "separator";
```

### Classification Rules

```typescript
function classifyChar(cp: number, style: Style): CharTokenType {
  // Box drawing (U+2500-257F)
  if (cp >= 0x2500 && cp <= 0x257F) {
    if (isCorner(cp)) {
      if (cp >= 0x250C && cp <= 0x250F) return "corner_tl";  // ┌┍┎┏
      if (cp >= 0x2510 && cp <= 0x2513) return "corner_tr";  // ┐┑┒┓
      if (cp >= 0x2514 && cp <= 0x2517) return "corner_bl";  // └┕┖┗
      if (cp >= 0x2518 && cp <= 0x251B) return "corner_br";  // ┘┙┚┛
      // Rounded variants ╒╓╔╕╖╗╘╙╚╛╜╝
      if (cp >= 0x2552 && cp <= 0x255D) return classifyRoundedCorner(cp);
    }
    if (isTee(cp)) { /* ├┤┬┴┝┥┰┸ etc */ }
    if (isCross(cp)) return "cross";
    if (isHorizontal(cp)) return "edge_h";
    if (isVertical(cp)) return "edge_v";
  }

  // Block elements (U+2580-259F)
  if (cp == 0x2588) return "block_full";          // █
  if (cp == 0x258C || cp == 0x258E) return "block_half_l";  // ▌▎
  if (cp == 0x2590) return "block_half_r";        // ▐
  if (cp >= 0x2591 && cp <= 0x2593) {              // ░▒▓
    return cp == 0x2591 ? "shade_light"
         : cp == 0x2592 ? "shade_med"
         : "shade_dark";
  }

  // Geometric shapes (U+25A0-25FF)
  if (cp == 0x25CF) return "radio_on";           // ●
  if (cp == 0x25CB) return "radio_off";          // ○
  if (cp == 0x25C9) return "radio_on";           // ◉
  if (cp == 0x25A0 || cp == 0x25A1) {            // ■□
    return cp == 0x25A0 ? "bullet" : "radio_off";
  }
  if (cp == 0x25B6 || cp == 0x25B8) return "expand_collapsed";  // ▶▸
  if (cp == 0x25BC || cp == 0x25BE) return "expand_expanded";   // ▼▾
  if (cp == 0x25C6 || cp == 0x25C7) return "bullet";            // ◆◇

  // Checkboxes (U+2610-2612)
  if (cp == 0x2610) return "checkbox_off";       // ☐
  if (cp == 0x2611) return "checkbox_on";        // ☑
  if (cp == 0x2612) return "checkbox_mixed";     // ☒

  // Arrows (U+2190-21FF)
  if (cp == 0x2191 || cp == 0x25B2) return "scroll_up";    // ↑▲
  if (cp == 0x2193 || cp == 0x25BC) return "scroll_down";  // ↓▼

  return cp == 0x20 ? "whitespace" : "text";
}
```

### Border Character Subclassification

```typescript
const CORNER_TOPLEFT     = new Set([0x250C, 0x250D, 0x250E, 0x250F, 0x2552, 0x2553, 0x2554]);
const CORNER_TOPRIGHT    = new Set([0x2510, 0x2511, 0x2512, 0x2513, 0x2555, 0x2556, 0x2557]);
const CORNER_BOTLEFT     = new Set([0x2514, 0x2515, 0x2516, 0x2517, 0x2558, 0x2559, 0x255A]);
const CORNER_BOTRIGHT    = new Set([0x2518, 0x2519, 0x251A, 0x251B, 0x255B, 0x255C, 0x255D]);
const TEE_LEFT           = new Set([0x251C, 0x251D, 0x251E, 0x251F, 0x2520, 0x2521, 0x2522, 0x2523]);
const TEE_RIGHT          = new Set([0x2524, 0x2525, 0x2526, 0x2527, 0x2528, 0x2529, 0x252A, 0x252B]);
const TEE_DOWN           = new Set([0x252C, 0x252D, 0x252E, 0x252F, 0x2530, 0x2531, 0x2532, 0x2533]);
const TEE_UP             = new Set([0x2534, 0x2535, 0x2536, 0x2537, 0x2538, 0x2539, 0x253A, 0x253B]);
const CROSS              = new Set([0x253C, 0x253D, 0x253E, 0x253F, 0x2540, 0x2541, 0x2542, 0x2543, 0x2544, 0x2545, 0x2546, 0x2547, 0x2548, 0x2549, 0x254A, 0x254B]);

const EDGE_HORIZONTAL    = [0x2500, 0x2501, 0x2504, 0x2505, 0x2508, 0x2509, 0x250C, 0x250D, 0x250E, 0x250F, ...]; // light, heavy, dashed variants
const EDGE_VERTICAL      = [0x2502, 0x2503, 0x2506, 0x2507, 0x250A, 0x250B, ...];
```

### Style Augmentation

Classification can be refined by style attributes:

```typescript
interface CharToken {
  type: CharTokenType;
  char: string;
  style: {
    fg?: string;    // color name or hex
    bg?: string;
    bold: boolean;
    dim: boolean;
    italic: boolean;
    underline: boolean;
    inverse: boolean;   // swapped fg/bg
  };
  weight: "light" | "heavy" | "double";  // from box-drawing char
  glyph: string;    // the actual character
}
```

Inverse video (`inverse: true`) typically indicates:
- Focused element
- Selected item
- Active tab
- Hovered button

Bold text typically indicates:
- Headings and labels
- Important values
- Active state

---

## Stage 2: Region Detection

### 2a. Container Detection (Border Walk)

Scan for corner characters, then walk edges to find bounded rectangles:

```
Algorithm: findContainers(buffer, tokens)

1. Scan every cell for corner_tl characters (┌┏╒╓)
2. For each corner at (x, y):
   a. Walk right along edge_h characters until corner_tr (┐┓╕╖) or tee_down (┬┮┰┲)
      → this is the container's right edge at x2
   b. Walk down along edge_v characters until corner_bl (└┗╘╙) or tee_left (├┝┠┣)
      → this is the container's bottom edge at y2
   c. Verify corner_br at (x2, y2) or trace right→down from bottom-left
   d. Record Rect(x, y, x2-x+1, y2-y+1)
3. Sort rects by area descending
4. For each rect, test if it fully contains smaller rects → parent-child relationship
```

### 2b. Column Splits (Panel Boundaries)

```
Algorithm: findColumnSplits(buffer, tokens)

1. For each row, find all edge_v and tee characters (│┃║├┤┼)
2. Cluster column positions that appear across >50% of rows
3. Each stable cluster = a column split boundary
4. Column regions = x-ranges between consecutive splits
```

### 2c. Table Detection

```
Algorithm: findTables(buffer, tokens)

1. Find rows containing cross (┼) or tee_d (┬) characters
2. A row with N+1 cross/tee chars spanning a rect = table header separator
3. Column boundaries = x-positions of vertical stems in the cross row
4. Row below the separator = table body rows
5. Row above the separator (between tee_d and a horizontal edge) = column headers
6. Table spans from the rect containing these rows
```

### 2d. Section Dividers

```
Algorithm: findSections(buffer, tokens, container)

1. Within a container, find rows where ≥80% of cells are edge_h or whitespace
2. These are section dividers
3. Content between section dividers = distinct semantic sections
4. First section = header (if bold/inverse style)
5. Last section = footer/status (if inverse style)
```

---

## Stage 3: Semantic Labeling

After containers and regions are detected, assign roles:

```typescript
interface DetectedElement {
  type: TuiElement["type"];
  bounds: Rect;
  role: string;
  content: string;
  children: DetectedElement[];
  interactable: boolean;
  cellData: CharToken[][];  // raw tokens for this region
}
```

### Labeling Rules

| Pattern | Role | Detection Rule |
|---------|------|----------------|
| Top-level rect with border | `panel` | Bounded by 4 corners, contains interior cells |
| Rect with title at top edge | `panel` | Border + bold/inverse text row inside top edge |
| Bottom row below divider, inverse | `statusBar` | `edge_h` separator above, inverse-styled row |
| Grid with cross/tee header | `table` | Cross char row defines column boundaries |
| Vertical stack of leading-marker rows | `list` | Same-column marker chars across consecutive rows |
| Block chars inside `[` `]` | `progressBar` | block_full/shade chars between bracket edges |
| `[text]` or `<text>` | `button` | Text wrapped in brackets with optional inverse style |
| Bold/inverse top row | `heading` | First content row in a container, different style |
| Thin block column at right edge | `scrollbar` | Vertical strip of block/shade/edge characters |
| Leading `☐☑☒` or `( )` | Checkable item | Checkbox or radio marker at start of row |
| Leading `▶▸` | Expandable item | Expand arrow at start of row |
| `▲` | `scrollUp` | Arrow at top of container (above content) |
| `▼` | `scrollDown` | Arrow at bottom of container (below content) |

### Tree Construction

```typescript
function buildTree(elements: DetectedElement[]): TuiElement {
  // 1. Sort by area descending
  // 2. Test containment: if A contains B, B is A's child
  // 3. Merge: if A and B have same type and are adjacent → sibling list items
  // 4. Label: apply semantic role from detection rules
  // 5. Assign stable refs
  // 6. Compute interactable from: cursor in bounds, style state, marker chars
  // 7. Compute actions from interactable + element type
}
```

---

## Interaction Detection Heuristics

### From Cursor Position

The terminal cursor (`ScreenBuffer.cursor`) always points at the active element:

```typescript
function findFocusedElement(buffer: ScreenBuffer, tree: TuiElement[]): TuiElement | null {
  if (!buffer.cursor) return null;
  return findDeepest(tree, el =>
    el.bounds.x <= buffer.cursor.x && buffer.cursor.x < el.bounds.x + el.bounds.w &&
    el.bounds.y <= buffer.cursor.y && buffer.cursor.y < el.bounds.y + el.bounds.h
  );
}
```

### From Style Changes

Compare consecutive frames. A border change from plain to thick or a color shift indicates
focus change on that element:

```typescript
function detectFocusChange(prev: RegionStyle, curr: RegionStyle): boolean {
  // Border weight change: ┌─┐ → ┏━┓
  // Color change: fg changes from gray to bright
  return prev.borderWeight !== curr.borderWeight
      || prev.fgBrightness !== curr.fgBrightness;
}
```

### From Unicode Markers

Certain characters are unambiguous signals of interactivity:

| Char | CP | Meaning | Action |
|------|----|---------|--------|
| `☐` | 0x2610 | Unchecked checkbox | `toggle` |
| `☑` | 0x2611 | Checked checkbox | `toggle` |
| `☒` | 0x2612 | Indeterminate/mixed | `toggle` |
| `◉` | 0x25C9 | Radio selected | `focus` |
| `○` | 0x25CB | Radio unselected | `focus` |
| `▶` | 0x25B6 | Collapsed expandable | `click` |
| `▼` | 0x25BC | Expanded expandable | `click` |
| `▸` | 0x25B8 | Collapsed (small) | `click` |
| `▾` | 0x25BE | Expanded (small) | `click` |

### From Underlined Characters

Underlined characters within text hint at keyboard shortcuts:

```typescript
function findShortcuts(text: string, styles: Style[][]): Shortcut[] {
  return styles.flatMap((row, y) =>
    row.filter(cell => cell.underline && cell.char.match(/[a-zA-Z0-9]/))
       .map(cell => ({ key: cell.char, position: "x": cell.x, y }))
  );
}
```

### Determining Available Actions

```typescript
function computeActions(el: TuiElement): ElementAction[] {
  const actions: ElementAction[] = [];

  // All focused elements accept focus action
  actions.push({ type: "focus" });

  switch (el.type) {
    case "button":
    case "list":
      actions.push({ type: "click" }, { type: "press_key", key: "enter" });
      break;
    case "checkbox":
    case "radio":
      actions.push({ type: "toggle" }, { type: "click" });
      break;
    case "input":
      actions.push({ type: "type" });
      if (el.focused) actions.push({ type: "press_key", key: "enter" });
      break;
    case "scrollbar":
      actions.push({ type: "scroll", direction: "up" }, { type: "scroll", direction: "down" });
      break;
  }

  return actions;
}
```

---

## Performance Considerations

- Character classification is O(n) per cell — negligible for terminal-sized buffers (80×24 = 1920
  cells).
- Region detection (border walk) scans at most 4 edges per container — O(containers × edge length).
- Container nesting inference is O(c²) where c is container count — typically <20.
- For real-time frame differencing, cache previous frame's token grid and only reclassify changed
  regions. Frame diff can be computed by comparing byte hashes of each row.

---

## References

- [Semantic Extraction Theory](semantic-extraction.md) — two-layer model and vdom spec
- [Unicode UI Element Reference](unicode-ui-elements.md) — complete character catalog
- [Agent Protocol](agent-protocol.md) — MCP tool schemas
- Ratatui `widgets/borders.rs` — border character sets (PLAIN, ROUNDED, DOUBLE, THICK, dashed variants)
- Urwid `canvas.py` — CanvasCombine, CanvasJoin, CanvasOverlay composition
- Textual `_box_drawing.py` — Quad-based box character composition
- Deciduous node 894 (decision: generic BufferScanner)
- Deciduous node 890 (observation: interaction detection heuristics)

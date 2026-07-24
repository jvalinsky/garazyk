# Overlay Alignment Design

A design document for eliminating misalignment between semantic overlays and
terminal output in the HTML export system.

## Problem

The HTML export renders semantic overlay boxes on top of a styled `<pre>` block
containing ANSI-rendered terminal output. These overlays label UI elements
(panes, popups, lists, game elements, charts) with colored bounding boxes.
Misalignment between overlay boxes and the underlying terminal characters
degrades the visual quality of exports and agent reasoning.

### Root Cause: Four Independent Coordinate Pipelines

The current system has four separate coordinate pipelines that must produce
identical results for alignment to hold:

```
  PTY buffer (cell grid)
      ↓ extractGrid()
  Detector bounds (startX/endX/startY/endY)
      ↓ toRect() / boundsToPixels()
  Overlay pixel positions (CSS left/top/width/height)
      ↓ charW/lineH measured from hidden <span>
  Terminal <pre> rendering (ANSI parser → HTML string)
```

Each conversion is a potential source of drift. The `charW`/`lineH`
measurement is especially fragile — it depends on the browser's font loading
state, zoom level, OS font rendering, and whether the monospace font actually
renders with the requested metrics. When `charW` or `lineH` drift by even a
fraction of a pixel, overlay boxes compound the error across width/height
calculations.

Additional sources of misalignment:

1. **Padding mismatch** — `#overlay` has `top: 12px; left: 12px` hardcoded to
   match `#terminal`'s `padding: 12px`. If the CSS changes, the overlay
   silently shifts.
2. **Wide character handling** — CJK characters, emoji, and Nerd Font icons
   occupy 2 terminal columns but render as 1 or 2 CSS characters. Bounds
   computed in cell units assume 1 cell = 1 character width, but the CSS
   rendering may disagree.
3. **Font loading race** — `charMetrics()` reads `getBoundingClientRect()` from
   a hidden `<span>`. If the font hasn't loaded yet, metrics are wrong and
   never corrected.
4. **Line-height variance** — `line-height: 1.4` is a relative value. The
   actual rendered line height depends on the font's ascent/descent, which
   varies across platforms and browsers.

## Design Principle: Eliminate Coordinate Conversion

Every coordinate conversion introduces potential error. The ideal system has
**one coordinate system** that everyone agrees on. The terminal rendering and
the overlay positioning should derive from the same source of truth — the
browser's layout engine — rather than from independent measurement.

## Three-Layer Improvement Plan

### Layer 1: CSS-Native Positioning (Immediate)

Replace JavaScript `charW`/`lineH` measurement with CSS `ch` and `lh` units.
These are part of the CSS specification and are guaranteed by the browser to
match the rendered font for the element.

#### Changes to `recording.mjs`

**In `buildStandaloneHtml()`, update the CSS:**

```css
/* Remove the hidden measurement span */
/* #measure { ... } — DELETE */

/* Make #terminal the positioning context */
#terminal {
  position: relative;  /* was: no position set */
  padding: 12px;
}

#overlay {
  position: absolute;
  top: 12px;    /* was: top: 12px relative to .terminal-frame */
  left: 12px;   /* was: left: 12px relative to .terminal-frame */
  pointer-events: none;
}

/* Overlay box positions use CSS custom properties + ch/lh units */
.ov {
  position: absolute;
  left: calc(var(--x) * 1ch);
  top: calc(var(--y) * 1lh);
  width: calc(var(--w) * 1ch);
  height: calc(var(--h) * 1lh);
  border-radius: 3px;
  pointer-events: none;
}
```

**Replace `boundsToPixels()` and `makeBoundsBox()` with CSS custom property
assignment:**

```js
function makeBoundsBox(type, bounds, label, extra) {
  const b = boundsToPixels(bounds);  // struct with x,y,w,h in cell units
  const el = document.createElement("div");
  el.className = "semantic-box ov ov-" + type + " ov-enter";
  el.style.setProperty("--x", b.x);  // cell units, not pixels
  el.style.setProperty("--y", b.y);
  el.style.setProperty("--w", b.w);
  el.style.setProperty("--h", b.h);
  // ...
}
```

**Remove `charMetrics()`, `boundsToPixels()`, `makeBox()`, and the `#measure`
span entirely.**

**Advantages:**
- Zero JS measurement — the browser computes `ch` and `lh` from the actual
  rendered font.
- No font-loading race — CSS units are computed lazily by the layout engine.
- No padding drift — `#overlay` is inside `#terminal`, so their coordinate
  origins are the same by construction.
- Changes ~30 lines of JS, removes ~35 lines of measurement code.

**Risks:**
- `ch` unit matches the width of the `0` glyph, not the average monospace
  width. For some fonts, `ch` may differ from the visual character width. This
  is rare for standard monospace fonts (Fira Code, Cascadia, SF Mono, Menlo)
  but warrants the checkerboard debug mode (Layer 2) as a verification tool.

### Layer 2: Diagnostics & Debug Tooling (Medium Effort)

These additions make misalignment **obvious** when it occurs and provide
evidence for debugging.

#### 2a. Checkerboard Debug Toggle

A button that overlays a 1ch × 1lh grid on the terminal, making any drift
between character cells and overlay boxes instantly visible:

```js
function toggleCheckerboard() {
  const grid = document.getElementById("checkerboard");
  if (grid) {
    grid.remove();
    return;
  }
  const canvas = document.createElement("canvas");
  canvas.id = "checkerboard";
  canvas.style.cssText = "position:absolute;top:0;left:0;pointer-events:none;opacity:0.3;z-index:50";
  canvas.width = width * charW;
  canvas.height = height * lineH;
  const ctx = canvas.getContext("2d");
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if ((x + y) % 2 === 0) {
        ctx.fillStyle = "rgba(255,255,255,0.05)";
        ctx.fillRect(x * charW, y * lineH, charW, lineH);
      }
    }
  }
  // ... append to terminal frame
}
```

With CSS-native positioning (Layer 1), `charW`/`lineH` can be measured once
for the checkerboard canvas only — it doesn't affect overlay positioning.

#### 2b. Anchor-Span Measurement

Inject invisible anchor spans at known cell positions during terminal
rendering, then measure their actual screen positions to detect drift:

```js
// In renderLine(), inject at the start of each line:
function renderLine(line, yIndex) {
  // ... existing rendering ...
  return '<span class="cell-anchor" data-x="0" data-y="' + yIndex + '"></span>' + html;
}
```

```js
// On render, compare anchor positions to expected:
function checkAlignment() {
  const anchors = document.querySelectorAll(".cell-anchor");
  let maxDriftX = 0, maxDriftY = 0;
  for (const anchor of anchors) {
    const x = parseInt(anchor.dataset.x);
    const y = parseInt(anchor.dataset.y);
    const rect = anchor.getBoundingClientRect();
    const expectedX = x * charW + terminalLeft;
    const expectedY = y * lineH + terminalTop;
    maxDriftX = Math.max(maxDriftX, Math.abs(rect.left - expectedX));
    maxDriftY = Math.max(maxDriftY, Math.abs(rect.top - expectedY));
  }
  if (maxDriftX > 2 || maxDriftY > 2) {
    showDriftWarning(maxDriftX, maxDriftY);
  }
}
```

**Note:** With Layer 1's CSS-native positioning, this diagnostic becomes a
verification tool rather than a correction mechanism. It confirms that `ch` and
`lh` units match the expected grid.

#### 2c. Render-Time Drift Warning Banner

A visible `[ALIGNMENT DRIFT]` banner shown when the measured terminal width
doesn't match the expected `charW × cols`:

```js
function showDriftWarning(driftX, driftY) {
  const banner = document.createElement("div");
  banner.id = "drift-warning";
  banner.style.cssText = "position:fixed;top:8px;left:50%;transform:translateX(-50%);"
    + "background:#da3633;color:#fff;padding:8px 16px;border-radius:6px;"
    + "font:13px ui-monospace,monospace;z-index:999;box-shadow:0 4px 12px rgba(0,0,0,.5)";
  banner.textContent = `⚠ ALIGNMENT DRIFT: ${driftX.toFixed(1)}px X, ${driftY.toFixed(1)}px Y`;
  document.body.appendChild(banner);
  setTimeout(() => banner.remove(), 5000);
}
```

#### 2d. `bounds_vs_content` Diagnostic

After rendering, verify that the text content at each overlay's bounds position
matches the overlay's label:

```js
function validateOverlayContent() {
  const warnings = [];
  for (const el of overlay.children) {
    const x = parseInt(el.style.getPropertyValue("--x"));
    const y = parseInt(el.style.getPropertyValue("--y"));
    const label = el.dataset.ovLabel;
    if (!label || x === undefined || y === undefined) continue;

    // Read terminal text at the overlay position
    const terminalText = readTerminalTextAt(x, y, label.length);
    if (!fuzzyMatch(terminalText, label)) {
      warnings.push({
        ref: el.dataset.ovRef,
        label,
        actualText: terminalText,
        position: { x, y },
      });
    }
  }
  return warnings;
}
```

### Layer 3: Architectural Improvements (V2)

These are fundamental redesigns that eliminate the overlay-as-separate-layer
pattern entirely. Defer until the system has stabilized with Layers 1 and 2.

#### 3a. CSS Grid Terminal Rendering

Render the terminal as `display: grid` with one cell per terminal column. Each
cell is exactly one CSS grid cell. Overlays use `grid-area` for zero-math
positioning:

```css
#terminal {
  display: grid;
  grid-template-columns: repeat(var(--cols), 1ch);
  grid-auto-rows: 1lh;
}

.cell {
  grid-column: var(--x);
  grid-row: var(--y);
}

.ov {
  grid-area: var(--row-start) / var(--col-start) / var(--row-end) / var(--col-end);
}
```

**Advantages:** The browser guarantees alignment because both terminal
characters and overlays occupy the same grid. No coordinate conversion exists.

**Disadvantages:** Major rewrite of the ANSI renderer. Each cell becomes a DOM
element, which is heavier than the current `<pre>` + `<span>` approach. For an
80×24 terminal, that's 1,920 elements — manageable, but 5× heavier than the
current approach of one `<span>` per style run.

#### 3b. Inline DOM Wrappers

Instead of a separate overlay `<div>`, inject semantic `<span>` tags directly
around the text tokens during `renderLine()`. The overlay physically contains
the characters it labels:

```js
function renderLine(line, yIndex, annotations) {
  // annotations = [{ startX, endX, type, label }] for this line
  // Inject <span class="ov-{type}"> around annotated regions
}
```

**Advantages:** Impossible to misalign — the annotation spans wrap the actual
text. No separate coordinate pipeline exists.

**Disadvantages:** Requires per-frame annotation data, which means the
annotations must be pre-computed during ANSI parsing rather than at render
time. This couples the detector pipeline more tightly to the renderer.

## Diagnostics for Agent Feedback

The `TuiWorld.validate()` function already includes a `low_relation_count`
warning that catches cases where spatial relation extraction produced zero
edges despite having visible nodes. For alignment diagnostics, we add:

### New Diagnostic Codes

| Code | Severity | Trigger | Agent Action |
|------|----------|---------|-------------|
| `overlay_drift` | warning | Measured `charW × cols` differs from terminal frame width by >2px | Check font loading; try zoom reset |
| `overlay_content_mismatch` | warning | Text at overlay position doesn't match overlay label | Bounds extraction may have shifted; check detector output |
| `overlay_bounds_clipped` | warning | Overlay bounds extend beyond viewport | Detector produced out-of-bounds coordinates |
| `zero_char_metrics` | error | `charMetrics()` returned zero width or height | Font failed to load; export may be unusable |

### Diagnostic Data in World Snapshots

Each overlay element in the `TuiWorld` carries:

```ts
interface OverlayDiagnostic {
  ref: string;          // node ref
  role: string;         // semantic role (e.g., "popup", "list")
  bounds: Bounds;       // computed bounds in cell units
  boundsAccuracy: "exact" | "row" | "estimated";
  contentAtBounds: string | null;  // actual terminal text at bounds position
  label: string | null;            // overlay label text
  match: boolean | null;           // whether content matches label (null if not checked)
}
```

This gives the agent structured evidence when reviewing exports: it can see
that a popup labeled "Help" is positioned at cell (10,5) and that the actual
terminal content at that position reads "Help" — confirming alignment.

## Implementation Order

| Step | Effort | Impact | Dependency |
|------|--------|--------|------------|
| 1. CSS `ch`/`lh` positioning | ~30 lines | Eliminates measurement drift | None |
| 2. Remove `charMetrics()` / `boundsToPixels()` | ~35 lines deleted | Simplifies code | Step 1 |
| 3. Checkerboard debug toggle | ~40 lines | Visual alignment verification | Step 2 |
| 4. Drift warning banner | ~25 lines | Catches font-loading issues | Step 2 |
| 5. Anchor-span measurement | ~50 lines | Precise drift quantification | Step 2 |
| 6. `bounds_vs_content` diagnostic | ~60 lines | Content-aware alignment check | Step 2 |
| 7. World diagnostic codes (4 new codes) | ~30 lines | Agent-visible alignment evidence | Step 6 |
| 8. Full corpus re-run to validate | ~5 min CI | Regression check | Steps 1-7 |

Steps 1-4 are a single atomic change; steps 5-7 can follow as a second batch.

## Verification

After Layer 1 implementation:

1. Run the corpus runner with `--sidecar` on all 14 curated scenarios.
2. Open each `index.html` and visually verify alignment at multiple zoom levels
   (100%, 125%, 150%).
3. Toggle the checkerboard in each export; verify no sub-pixel drift.
4. Run the corpus runner on a wide-character scenario (add `mc.yaml` if it
   uses box-drawing, or create a `widechars.yaml` with CJK/emoji content).
5. Verify no `[ALIGNMENT DRIFT]` banner appears on any scenario.

## References

- [Agent Protocol](agent-protocol.md) — TuiWorld, `worldQuery`, ref system
- [Semantic Extraction Theory](semantic-extraction.md) — detector pipeline
- [Extraction Pipeline](extraction-pipeline.md) — grid extraction, bounds
  computation
- Deciduous nodes 880-897 — semantic model decisions

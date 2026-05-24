# Unicode UI Element Reference

Complete catalog of Unicode characters used in terminal UIs, organized by semantic function.
Every major TUI framework (Urwid, Textual, Ratatui, Ink, prompt_toolkit, BubbleTea) uses these
same codepoints for the same structural purposes.

---

## Box Drawing: U+2500–257F

Used for containers, panels, tables, dividers. The character shape encodes the structural role,
and the line weight (light/heavy/double) encodes hierarchy or emphasis.

### Corners — Container Boundaries

A set of four corners at (x,y), (x+w,y), (x,y+h), (x+w,y+h) defines a rectangular container.

```
Single:  ┌ ┐  └ ┘
Heavy:   ┏ ┓  ┗ ┛
Double:  ╔ ╗  ╚ ╝
Rounded: ╒ ╕  ╘ ╛
```

| Codepoint | Char | Variant | Semantic meaning |
|-----------|------|---------|-----------------|
| 0x250C | `┌` | Light down-right | Standard panel TL corner |
| 0x250D | `┍` | Down-right, light-heavy | Title emphasis |
| 0x250E | `┎` | Heavy-light | Left border emphasis |
| 0x250F | `┏` | Heavy down-right | Focused/active panel TL corner |
| 0x2510 | `┐` | Light down-left | Standard panel TR corner |
| 0x2511 | `┑` | Down-left, light-heavy | Title emphasis |
| 0x2512 | `┒` | Heavy-light | Right border emphasis |
| 0x2513 | `┓` | Heavy down-left | Focused/active panel TR corner |
| 0x2514 | `└` | Light up-right | Standard panel BL corner |
| 0x2515 | `┕` | Up-right, light-heavy | Bottom border emphasis |
| 0x2516 | `┖` | Heavy-light | Left border emphasis |
| 0x2517 | `┗` | Heavy up-right | Focused/active panel BL corner |
| 0x2518 | `┘` | Light up-left | Standard panel BR corner |
| 0x2519 | `┙` | Up-left, light-heavy | Bottom border emphasis |
| 0x251A | `┚` | Heavy-light | Right border emphasis |
| 0x251B | `┛` | Heavy up-left | Focused/active panel BR corner |
| 0x2554 | `╔` | Double down-right | Dialog/modal TL corner |
| 0x2557 | `╗` | Double down-left | Dialog/modal TR corner |
| 0x255A | `╚` | Double up-right | Dialog/modal BL corner |
| 0x255D | `╝` | Double up-left | Dialog/modal BR corner |
| 0x2552 | `╒` | Light down-right, double | Rounded variant |
| 0x2555 | `╕` | Light down-left, double | Rounded variant |
| 0x2558 | `╘` | Light up-right, double | Rounded variant |
| 0x255B | `╛` | Light up-left, double | Rounded variant |
| 0x256D | `╭` | Arc down-right | Soft corner (Ratatui Rounded) |
| 0x256E | `╮` | Arc down-left | Soft corner |
| 0x256F | `╰` | Arc up-right | Soft corner |
| 0x2570 | `╯` | Arc up-left | Soft corner |

### Edges — Container Borders

```
Single:  ─ │
Heavy:   ━ ┃
Double:  ═ ║
```

| Codepoint | Char | Variant | Detection |
|-----------|------|---------|-----------|
| 0x2500 | `─` | Light horizontal | Top/bottom panel edges, section dividers |
| 0x2501 | `━` | Heavy horizontal | Focused panel edge, important divider |
| 0x2502 | `│` | Light vertical | Left/right panel edges, column separators |
| 0x2503 | `┃` | Heavy vertical | Focused panel side, active column |
| 0x2550 | `═` | Double horizontal | Dialog/modal edges, major section |
| 0x2551 | `║` | Double vertical | Dialog/modal edges |
| 0x2504 | `╌` | Light dashed horizontal | Subtle divider |
| 0x2505 | `╍` | Heavy dashed horizontal | Emphasized divider |
| 0x2506 | `╎` | Light dashed vertical | Subtle column separator |
| 0x2507 | `╏` | Heavy dashed vertical | Emphasized separator |

### T-Junctions and Crosses — Table Grid Lines

```
├ ┤ ┬ ┴ ┼  — single
┝ ┥ ┰ ┸ ╂  — mixed weight
┠ ┨ ┲ ┺ ╊  — heavy
╟ ╢ ╤ ╧ ╫  — double (single-sided)
╠ ╣ ╦ ╩ ╬  — double (all double)
```

T-junctions indicate grid edges (left, right, top, bottom boundaries within a table).
Crosses (`┼` variants) indicate interior cell boundaries.

| Codepoint | Char | Meaning |
|-----------|------|---------|
| 0x251C | `├` | Vertical line meets horizontal from right — row separator, open on left |
| 0x2524 | `┤` | Vertical line meets horizontal from left — row separator, open on right |
| 0x252C | `┬` | Horizontal line meets vertical from top — column header separator |
| 0x2534 | `┴` | Horizontal line meets vertical from bottom — footer separator |
| 0x253C | `┼` | Four-way intersection — interior table cell separator |
| 0x2523 | `┣` | Heavy tee left — focused row boundary |
| 0x252B | `┫` | Heavy tee right — focused row boundary |
| 0x2533 | `┳` | Heavy tee down — focused column header |
| 0x253B | `┻` | Heavy tee up — focused footer |
| 0x254B | `╋` | Heavy cross — focused cell |

---

## Block Elements: U+2580–259F

Used for progress bars, scrollbar thumbs, selection indicators, and visual density.

### Full and Partial Blocks

| Codepoint | Char | Name | TUI usage |
|-----------|------|------|-----------|
| 0x2588 | `█` | Full block | Progress bar filled, selected item bg, scrollbar thumb, filled gauge |
| 0x2589 | `▉` | Left 7/8 block | Partial progress, fine-grained gauges |
| 0x258A | `▊` | Left 3/4 block | Partial progress, fine-grained gauges |
| 0x258B | `▋` | Left 5/8 block | Partial progress, fine-grained gauges |
| 0x258C | `▌` | Left half block | Bidi text marker, partial selection, split indicator |
| 0x258D | `▍` | Left 3/8 block | Partial progress, fine-grained gauges |
| 0x258E | `▎` | Left 1/4 block | Partial progress, fine-grained gauges |
| 0x258F | `▏` | Left 1/8 block | Minimal progress indicator |
| 0x2590 | `▐` | Right half block | Bidi text marker, continuation indicator |
| 0x2594 | `▔` | Upper 1/8 block | Overline, heading underline |
| 0x2581 | `▁` | Lower 1/8 block | Sparkline, audio visualizer, histogram |
| 0x2582 | `▂` | Lower 1/4 block | Sparkline |
| 0x2583 | `▃` | Lower 3/8 block | Sparkline |
| 0x2584 | `▄` | Lower half block | Progress bar lower fill, sparkline |
| 0x2585 | `▅` | Lower 5/8 block | Sparkline |
| 0x2586 | `▆` | Lower 3/4 block | Sparkline |
| 0x2587 | `▇` | Lower 7/8 block | Sparkline |

### Shade Characters

| Codepoint | Char | Shade level | TUI usage |
|-----------|------|-------------|-----------|
| 0x2591 | `░` | Light 25% | Scrollbar track, disabled element, background fill |
| 0x2592 | `▒` | Medium 50% | Inactive tab, dimmed element, loading indicator |
| 0x2593 | `▓` | Dark 75% | Hover state, active-but-dimmed element |

**Detection pattern for progress bars:** A sequence of `█` characters followed by `▒` or `░`
characters, optionally bounded by `[` `]` or `│` edges. The count of `█` relative to total
width gives the percentage.

**Detection pattern for scrollbars:** A vertical strip of `░▒▓█` characters plus `▁▂▃▄` at the
right edge of a container, where the proportion of `█` to total height indicates scroll position.

---

## Geometric Shapes: U+25A0–25FF

Used for list markers, radio buttons, expand/collapse indicators.

| Codepoint | Char | Name | Semantic meaning |
|-----------|------|------|-----------------|
| 0x25A0 | `■` | Black square | Selected/unselected item marker |
| 0x25A1 | `□` | White square | Unselected list item, empty checkbox alternative |
| 0x25AA | `▪` | Black small square | Bullet, sub-list item marker |
| 0x25AB | `▫` | White small square | Minor bullet |
| 0x25CF | `●` | Black circle | Radio selected, active bullet |
| 0x25CB | `○` | White circle | Radio unselected, inactive item |
| 0x25C9 | `◉` | Fisheye | Radio selected (alternative), button indicator |
| 0x25CE | `◎` | Bullseye | Radio selected (focused) |
| 0x25B6 | `▶` | Black right-pointing | Collapsed disclosure (expand) |
| 0x25B8 | `▸` | Black right-pointing small | Collapsed sub-menu (expand) |
| 0x25BC | `▼` | Black down-pointing | Expanded disclosure (collapse) |
| 0x25BE | `▾` | Black down-pointing small | Expanded sub-menu (collapse) |
| 0x25C0 | `◀` | Black left-pointing | Collapsed right-side panel |
| 0x25C6 | `◆` | Black diamond | Important/focused list item |
| 0x25C7 | `◇` | White diamond | Optional list item |
| 0x25B2 | `▲` | Black up-pointing | Scroll up indicator, sort ascending |
| 0x25BC | `▼` | Black down-pointing | Scroll down indicator, sort descending |
| 0x25A3 | `▣` | White square containing black | Checked item (alternative) |
| 0x25A4 | `▤` | Square with horizontal fill | Partial/indeterminate |

---

## Checkboxes and UI Controls: U+2610–2612

| Codepoint | Char | Name | Semantic meaning |
|-----------|------|------|-----------------|
| 0x2610 | `☐` | Ballot box | Unchecked checkbox — toggleable OFF state |
| 0x2611 | `☑` | Ballot box with check | Checked checkbox — toggleable ON state |
| 0x2612 | `☒` | Ballot box with X | Indeterminate/mixed checkbox state |

**Detection:** Leading character on a row, followed by space + label text. Interactable = toggle.

---

## Weather/Dingbats: U+2713–2718

| Codepoint | Char | Name | Semantic meaning |
|-----------|------|------|-----------------|
| 0x2713 | `✓` | Check mark | Success indicator, passed test |
| 0x2714 | `✔` | Heavy check mark | Emphasized success |
| 0x2717 | `✗` | Ballot X | Failure indicator, failed test |
| 0x2718 | `✘` | Heavy ballot X | Emphasized failure |
| 0x2716 | `✖` | Heavy multiplication X | Error/delete indicator |

---

## Miscellaneous

| Codepoint | Char | Semantic meaning |
|-----------|------|-----------------|
| 0x2026 | `…` | Truncated text, "more" indicator |
| 0x00B7 | `·` | Separator dot, breadcrumb divider |
| 0x2022 | `•` | Bullet, list item marker |
| 0x2605 | `★` | Active star rating |
| 0x2606 | `☆` | Inactive star rating |
| 0x2699 | `⚙` | Settings/configuration indicator |
| 0x26A1 | `⚡` | Warning/alert indicator |
| 0x26A0 | `⚠` | Warning sign |
| 0x2714 | `✔` | Success/check |
| 0x2718 | `✘` | Error/cross |
| 0x2753 | `❓` | Help/question |
| 0x2757 | `❗` | Important/exclamation |

---

## Keyboard Shortcut Indicators

Underline style in TUIs often indicates keyboard shortcuts:

```
// Text with underlined character: _S_ave, (q)uit, [F1] Help
```

Detection: scan for `underline: true` style on a single character within text. That character
is the shortcut key.

Additional patterns:
- `[F1]`, `[F2]`, etc. = function key shortcuts
- `(c)`, `(x)`, etc. = Ctrl+letter shortcuts
- `_K_ey` (underlined `K`) = Alt+K shortcut

---

## Bulk Classification by Unicode Range

| Start | End | Block | TUI semantics |
|-------|-----|-------|---------------|
| 0x2500 | 0x257F | Box Drawing | Borders, containers, tables, dividers |
| 0x2580 | 0x259F | Block Elements | Progress, scrollbars, selection |
| 0x25A0 | 0x25FF | Geometric Shapes | Markers, bullets, radios, expand |
| 0x2190 | 0x21FF | Arrows | Navigation, scroll indicators |
| 0x2600 | 0x26FF | Misc Symbols | UI icons (star, settings, warning) |
| 0x2700 | 0x27BF | Dingbats | Check/cross marks, status indicators |
| 0x2610 | 0x2612 | — | Checkbox controls |
| 0x2B00 | 0x2BFF | Misc Arrows | Additional arrows and triangles |
| 0x2300 | 0x23FF | Misc Technical | Keyboard symbols (⌘⌥⌃⇧) |

---

## References

- Unicode Standard v16.0: Box Drawing block (U+2500), Block Elements (U+2580), Geometric Shapes
  (U+25A0)
- Ratatui: `ratatui-widgets/src/borders.rs` — border set definitions
- Textual: `src/textual/_box_drawing.py` — Quad-based box character composition
- Urwid: `urwid/canvas.py` — TextCanvas and CompositeCanvas character model
- [Semantic Extraction Theory](semantic-extraction.md) — two-layer extraction model
- [Extraction Pipeline](extraction-pipeline.md) — detection algorithm specifications
- [Agent Protocol](agent-protocol.md) — MCP tool schemas and agent workflows
- Deciduous node 881 (observation: Unicode encodes UI semantics)
- Deciduous node 897 (decision: Unicode reference doc)

# Admin UI — Web Assets

Static CSS and JS served by `PDSAdminUIServer`. Contains the design tokens,
component classes, layout primitives, and two HTMX-flavored JavaScript
bundles (`lab.js`, `mst-viewer/`) that the server renders the admin
HTML against. `PDSAdminUIServer` runs HTMX for partial-page interactions,
per the project root README.

The design system is documented in full at
[`DESIGN_SYSTEM.md`](./DESIGN_SYSTEM.md) and
[`QUICK_REFERENCE.md`](./QUICK_REFERENCE.md). This README lists the
files and the entry points you need to use them.

## File Inventory

```
AdminUIServer/Assets/
├── css/
│   ├── reset.css           Browser reset.
│   ├── system.css          Base styles, font stack.
│   ├── tokens.css          CSS custom properties (light + dark).
│   ├── layout.css          Toolbar, sidebar, inspector, responsive.
│   ├── components.css      Component classes (btn, form, table, card, …).
│   ├── utilities.css       Spacing, display, text helpers.
│   └── mst-viewer.css      Legacy MST visualization (kept as-is).
├── html/
│   └── demo.html           Interactive showcase mounted at /admin/demo.
├── js/
│   ├── lab.js              Legacy dashboard scripts.
│   └── mst-viewer/         MST tree inspector and viewer bundles.
├── DESIGN_SYSTEM.md        Full design philosophy, tokens, patterns.
├── QUICK_REFERENCE.md      Copy-paste component cheat sheet.
└── README.md               This file.
```

## Tokens

Colors use OKLCH so equal lightness steps read equal across hues. Light
mode targets 96% backgrounds with a faint neutral tint; dark mode drops
to 15–28% with strawberry-red warmth (chroma 0.01–0.012) so brand
identity remains visible. Both modes aim for 7:1 contrast on body text
(WCAG AAA). Token names and values are in `css/tokens.css`.

Spacing follows a 4pt grid: `xs(4) sm(8) md(12) lg(16) xl(24) 2xl(32)
3xl(48) 4xl(64)`. Type scale is five steps on a 1.25× ratio
(`11 / 12 / 15 / 19 / 24 / 30` px). Line-height options are
`tight (1.2) / normal (1.5) / relaxed (1.75)`. Weights are
500 (UI), 600 (headings), 700 (emphasis). Font stack falls back to
`SF Pro` on macOS, `Segoe UI` on Windows, then the system default.

Default transitions are `0.15s ease`; every animation respects
`prefers-reduced-motion`.

## Quick Start

```html
<link rel="stylesheet" href="/css/system.css">
<link rel="stylesheet" href="/css/tokens.css">
<link rel="stylesheet" href="/css/layout.css">
<link rel="stylesheet" href="/css/components.css">
<link rel="stylesheet" href="/css/utilities.css">
```

```html
<button class="btn btn-primary">Save</button>
<button class="btn btn-secondary">Cancel</button>
<button class="btn btn-destructive">Delete Account</button>
<button class="btn btn-ghost">Learn more</button>
```

```html
<form class="form">
  <div class="form-group">
    <label class="form-label required">Service URL</label>
    <input type="url" class="form-input" placeholder="https://...">
  </div>
  <div class="form-footer">
    <button type="button" class="btn btn-secondary">Reset</button>
    <button type="submit" class="btn btn-primary">Save</button>
  </div>
</form>
```

## Components

Class names in `css/components.css` fall into five families. Use the
class — never inline the styles.

| Family   | Classes                                                                                  |
| -------- | ---------------------------------------------------------------------------------------- |
| Buttons  | `btn`, `btn-primary`, `btn-secondary`, `btn-destructive`, `btn-success`, `btn-ghost`, `btn-sm`, `btn-block` |
| Forms    | `form`, `form-group`, `form-row`, `form-label`, `form-input`, `form-help`, `form-error`, `form-footer` |
| Tables   | `table`, `table-wrapper`, `table-dense`                                                  |
| Cards    | `card`, `card-header`, `card-body`, `card-footer`, `card-title`                          |
| Feedback | `alert`, `alert-info`, `alert-success`, `alert-warning`, `alert-destructive`, `badge`, `progress`, `modal` |

## Layout

AppKit-inspired shell: 52px toolbar, 220px sidebar, 320px inspector, with
a flexible content area and 44px status bar. Responsive breakpoints at
768px (sidebar collapses to a drawer, inspector hides) and 480px (single
column). Layout classes live in `css/layout.css` (`app-layout`,
`toolbar`, `sidebar`, `inspector-pane`, `content-area`, `status-bar`).

## Accessibility

- Focus visible: 2px outline with 2px offset. Never removed.
- Body text contrast: ≥ 7:1 (WCAG AAA).
- All animations respect `prefers-reduced-motion`.
- Buttons, forms, tables use native HTML elements; ARIA is layered on
  for modals and live regions only where semantics need reinforcement.

## Demo

`/admin/demo` serves `html/demo.html` with every component variant, the
full token palette, the type scale, and three example screens (login,
dashboard, accounts). Use it to verify changes during development.

## Tests

The CSS has no unit tests. The `mst-viewer/` JS bundle has integration
tests under `Garazyk/Tests/` and is exercised by the admin UI browser
smoke scripts.

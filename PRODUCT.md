# Design Context

## Users

Server operators running PDS instances. They are developers and system
administrators who manage AT Protocol infrastructure, monitor health, manage
users, configure settings, and diagnose issues.

## Brand Personality

The UI follows Apple AppKit conventions: toolbar, sidebar, inspectors, and
familiar desktop patterns.

## Aesthetic Direction

- Theme: light and dark mode via system preference.
- Visual tone: AppKit-native. NSToolbar, NSOutlineView sidebar, NSTableView
  lists, NSVisualEffectView materials.
- Polish motif: "garazyk" means "little garage" in Polish. Use strawberry
  iconography instead of the Apple logo.
- Build a native macOS app, not a web admin panel.

## Design Principles

1. AppKit fidelity. Use native macOS visual patterns: toolbar at top,
   source-list sidebar, content area with inspectors.
2. Approachable clarity. Present complex information simply.
3. Progressive disclosure. Start simple, reveal complexity on demand.
4. System-aware theming. Respect the OS light/dark preference via
   NSVisualEffectView.
5. Polish pride. Add subtle strawberry motifs.

## Design System

Delivered May 2026.

### Component Library

- Buttons: primary, secondary, destructive, success, ghost variants, plus `sm`
  and `lg` sizes.
- Forms: text inputs, selects, checkboxes, radios, with focus states and error
  handling.
- Tables: standard and dense modes, with hover states and sorting indicators.
- Cards: simple, with headers, with footers.
- Alerts: info, success, warning, destructive, with semantic colors. Full
  borders, no side-stripes.
- Badges: filled and outline variants.
- Modals: dialog with header, body, footer.
- Tabs: tab navigation with active indicators.
- Progress bars, with an optional striped animation.
- Status indicators: connected, disconnected, pending.
- Metrics and stats: dashboard cards with values and change indicators.
- Loading states: spinner animation and skeleton loading.

### Layout System

- Toolbar (52px): brand, navigation segments, user menu. Full width.
- Sidebar (220px): source-list navigation, section grouping, collapsible
  sections.
- Inspector pane (320px): detail and property panels. Collapses on mobile.
- Content area: main content with scroll.
- Status bar (44px): system status, uptime, connection indicators.

All patterns respond at the 768px and 480px breakpoints.

### Color System (OKLCH)

- Light mode: bright backgrounds (96% lightness), subtle brand tint (chroma
  0.003 to 0.005).
- Dark mode: dark backgrounds (15% to 28% lightness), visible brand warmth
  (chroma 0.006 to 0.012).
- Semantic tokens: success, warning, destructive, info, at high contrast.
- Tinted neutrals: all backgrounds tinted toward strawberry red (15°).
- Contrast ratio: all text at 7:1 or better (WCAG AAA).

### Spacing and Typography

- 4pt grid: xs(4), sm(8), md(12), lg(16), xl(24), 2xl(32), 3xl(48), 4xl(64).
- Type scale: 11px, 12px, 15px, 19px, 24px, 30px (1.25x ratio).
- System fonts: SF Pro on macOS, Segoe UI on Windows, sans-serif fallback.
- Line heights: tight (1.2), normal (1.5), relaxed (1.75).

### Documentation

- `DESIGN_SYSTEM.md`: color, typography, spacing, components, responsive
  patterns, accessibility.
- `QUICK_REFERENCE.md`: developer cheat sheet with copy-paste examples.
- `/admin/demo`: interactive showcase of components, colors, and typography.

### CSS Architecture

- `tokens.css`: OKLCH colors, spacing scale, typography, shadows.
- `layout.css`: toolbar, sidebar, inspector, content, status bar, responsive.
- `components.css`: component styles with interactive states.
- `utilities.css`: flexbox, grid, spacing, text, visibility helpers.
- `system.css`: global reset and font loading.

## Brand Tinting

Strawberry red (hue 15°) carries the brand through the color palette alone.
Light mode uses a barely perceptible warm tint; dark mode uses 0.01 to 0.012
chroma so the warmth reads without being jarring. OKLCH values keep the tint
perceptually consistent across lightness levels.

There are no strawberry SVG graphics. Generated vector art was unreliable, so
the brand is carried by color precision instead.

## Dark Mode

Dark mode has full parity with light mode. Brand tinting is stronger in dark
backgrounds, and all interactive states carry across both modes. The switch
respects `@media (prefers-color-scheme: dark)`.

## Three-Pane Layout

Active. The content area holds the main scrollable content, and the inspector
pane (320px) holds detail panels, edit forms, and metadata: account details,
settings panels, property editors. The inspector hides on mobile and opens as a
drawer on demand.

## Component Showcase

The `/admin/demo` page demonstrates the patterns across the login, dashboard,
accounts, connections, and metrics screens. It covers every button, form, card,
table, alert, and badge; the full palette with OKLCH values; the type scale,
weights, and line heights; and behavior at mobile breakpoints.

## Patterns to Avoid

Do not use side-stripe borders (`border-left: 4px`) or gradient text
(`background-clip: text`). Use full borders with semantic colors, solid text
with weight and size variation, deliberate shadows, and varied spacing.

## Accessibility (WCAG AAA)

- Contrast: 7:1 minimum for text on backgrounds.
- Focus indicators: 2px outline at 2px offset, never hidden.
- Keyboard: Tab, Shift+Tab, Enter, and Escape all work.
- Modals: focus trap, return focus to the trigger on close.
- Animations: respect `prefers-reduced-motion`.
- Semantics: native HTML, with ARIA labels where needed.

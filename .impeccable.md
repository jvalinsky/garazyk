# Design Context

## Users
Server operators who run their own PDS instances. They're technical users managing AT Protocol infrastructure — typically developers or system administrators who need to monitor health, manage users, configure settings, and diagnose issues.

## Brand Personality
Clean & approachable. The UI should feel like **Apple AppKit** — native macOS application feel with toolbar, sidebar, inspectors, and familiar desktop patterns. Professional, polished, and distinctly macOS.

## Aesthetic Direction
- **Theme**: Both light and dark mode support (system preference aware)
- **Visual tone**: AppKit-native — NSToolbar, NSOutlineView sidebar, NSTableView lists, NSVisualEffectView materials
- **Polish motif**: Subtle strawberry references (our name "garazyk" means "little garage" in Polish) — use strawberry iconography instead of Apple logo, perhaps in the toolbar or as subtle branding elements
- **Philosophy**: Feels like a native macOS app, not a web admin panel

## Design Principles
1. **AppKit fidelity** — Use native macOS visual patterns: toolbar at top, source-list sidebar, content area with inspectors
2. **Approachable clarity** — Complex information presented simply, not overwhelming
3. **Progressive disclosure** — Start simple, reveal complexity on demand (show less detail initially, expandable sections)
4. **System-aware theming** — Respect user's OS preference (light/dark) with NSVisualEffectView
5. **Polish pride** — Subtle strawberry motifs that only those "in the know" will notice

## Design System — COMPLETE ✓

### Deliverables (May 2026)

#### 1. Production-Grade Component Library
- **Buttons**: Primary, Secondary, Destructive, Success, Ghost variants + sizes (sm, lg)
- **Forms**: Text inputs, selects, checkboxes, radios with focus states and error handling
- **Tables**: Standard and dense modes with hover states and sorting indicators
- **Cards**: Simple, with headers, with footers — flexible composition
- **Alerts**: Info, Success, Warning, Destructive with semantic colors (full borders, no side-stripes)
- **Badges**: Filled and outline variants
- **Modals**: Dialog with header, body, footer
- **Tabs**: Tab navigation with active indicators
- **Progress bars**: With striped animation option
- **Status indicators**: Connected, disconnected, pending states
- **Metrics/Stats**: Dashboard cards with values and change indicators
- **Loading states**: Spinner animation + skeleton loading

#### 2. Layout System
- **Toolbar** (52px): Brand, navigation segments, user menu — full-width
- **Sidebar** (220px): Source-list navigation, section grouping, collapsible sections
- **Inspector Pane** (320px): Detail/property panels, collapses on mobile
- **Content Area**: Flexible main content with scroll
- **Status Bar** (44px): System status, uptime, connection indicators
- All patterns respond gracefully at 768px and 480px breakpoints

#### 3. Color System (OKLCH-Based)
- **Light Mode**: Bright backgrounds (96% lightness), subtle brand tint (chroma 0.003–0.005)
- **Dark Mode**: Dark backgrounds (15–28% lightness), visible brand warmth (chroma 0.006–0.012)
- **Semantic tokens**: Success, Warning, Destructive, Info with high contrast
- **Tinted neutrals**: All backgrounds tinted toward strawberry red (15°) for subtle cohesion
- Contrast ratio: All text ≥ 7:1 (WCAG AAA)

#### 4. Spacing & Typography
- **4pt grid**: xs(4), sm(8), md(12), lg(16), xl(24), 2xl(32), 3xl(48), 4xl(64)
- **5-step type scale**: 11px → 12px → 15px → 19px → 24px → 30px (1.25× ratio)
- **System fonts**: SF Pro (macOS), Segoe UI (Windows), fallback to sans-serif
- **Line height scale**: Tight (1.2), Normal (1.5), Relaxed (1.75)

#### 5. Documentation
- **DESIGN_SYSTEM.md**: Comprehensive guide covering color, typography, spacing, components, responsive patterns, accessibility
- **QUICK_REFERENCE.md**: Developer cheat sheet with common patterns, copy-paste examples
- **/admin/demo**: Interactive showcase of all components, colors, typography

#### 6. CSS Architecture
- `tokens.css`: OKLCH colors, spacing scale, typography, shadows
- `layout.css`: Toolbar, sidebar, inspector, content, status bar, responsive
- `components.css`: All component styles with interactive states
- `utilities.css`: Flexbox, grid, spacing, text, visibility helpers
- `system.css`: Global reset + font loading

### Brand Tinting (No SVG Logos)
- Strawberry red (hue 15°) is **the brand** — expressed through color palette alone
- Light mode: Subtle warm tint (barely noticeable chroma)
- Dark mode: **Visible warmth** (0.01–0.012 chroma) for brand presence without being jarring
- **No strawberry SVG graphics** — AI generation unreliable; rely on color precision
- Color values in OKLCH ensure perceptual consistency across lightness

### Dark Mode Implementation
- Full parity with light mode — not an afterthought
- Stronger brand tinting in dark backgrounds for visual warmth and brand presence
- All interactive states maintained across both modes
- Respects system preference via `@media (prefers-color-scheme: dark)`

### Three-Pane Layout (Active)
- **Content Area**: Main scrollable content
- **Inspector Pane** (320px): Detail/property panels, edit forms, metadata
- Responsive: Hides on mobile, drawer on demand
- Perfect for: Account details, settings panels, property editors

### Component Showcase
- Interactive `/admin/demo` page demonstrates all patterns
- Screens: Login, Dashboard, Accounts, Connections, Metrics
- Components: All buttons, forms, cards, tables, alerts, badges
- Colors: Full palette swatches with OKLCH values
- Typography: Type scale, weights, line heights
- Responsive: Adapts to mobile breakpoints

### Avoiding AI Slop Patterns
- ✗ Side-stripe borders (`border-left: 4px`)
- ✗ Gradient text (`background-clip: text`)
- ✓ Full borders + semantic colors
- ✓ Solid text with weight/size variation
- ✓ Intentional shadows, varied spacing

### Accessibility (WCAG AAA)
- Contrast: 7:1 minimum (text on backgrounds)
- Focus indicators: 2px outline, 2px offset (never hidden)
- Keyboard: Tab, Shift+Tab, Enter, Escape all work
- Modals: Focus trap, return to trigger on close
- Animations: Respect `prefers-reduced-motion`
- Semantics: Native HTML, ARIA labels where needed
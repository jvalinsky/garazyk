# Garazyk Admin UI — Design System Guide

**Version**: 2.0  
**Updated**: May 2026  
**Theme**: AppKit-native aesthetic for AT Protocol server operators

---

## Overview

The Garazyk Admin UI is designed for **technical server operators** managing AT Protocol infrastructure. The interface should feel like a native macOS application—professional, clear, and approachable—not a generic web admin panel.

### Design Philosophy

1. **AppKit Fidelity** — Use macOS visual patterns: toolbars, source-list sidebars, inspector panes, status bars
2. **Clarity First** — Complex information presented simply, never overwhelming
3. **Progressive Disclosure** — Start simple; reveal complexity on demand
4. **System Aware** — Respect user's OS theme preference (light/dark)
5. **Polish Without Ornament** — Subtle brand presence via color, not graphics

---

## Color System

### OKLCH Foundation

Colors are defined in **OKLCH color space** for perceptual uniformity. Equal steps in lightness *look* equal, unlike HSL.

```
oklch(lightness% chroma hue)
```

**Key advantage**: As you move toward white/black, chroma naturally reduces to prevent garish highlights.

### Semantic Palette

| Token | Light | Dark | Purpose |
|-------|-------|------|---------|
| `--color-bg-primary` | oklch(96% 0.003 200) | oklch(15% 0.006 15) | Main background |
| `--color-bg-secondary` | oklch(99% 0.003 200) | oklch(22% 0.01 15) | Secondary surfaces (cards, panels) |
| `--color-bg-tertiary` | oklch(93% 0.005 200) | oklch(28% 0.012 15) | Hover states, subtle contrast |
| `--color-text-primary` | oklch(13% 0.005 200) | oklch(96% 0.003 200) | Main text |
| `--color-text-secondary` | oklch(45% 0.005 200) | oklch(70% 0.005 200) | Secondary labels, captions |
| `--color-accent` | oklch(52% 0.18 255) | oklch(52% 0.18 255) | Primary actions, focus states |

### Brand Tinting

**Strawberry red** (hue: 15°) subtly tints backgrounds for cohesion. Dark mode uses *stronger* tinting (chroma 0.01–0.012) for visibility.

- Light mode: Very subtle (chroma 0.003–0.005)
- Dark mode: Noticeable warmth (chroma 0.006–0.012)

### Action Colors

| Semantic | OKLCH | Use Case |
|----------|-------|----------|
| Success | oklch(60% 0.18 145) | Positive outcomes, confirmations |
| Warning | oklch(75% 0.18 70) | Caution, requires attention |
| Destructive | oklch(58% 0.22 25) | Deletion, irreversible actions |
| Info | oklch(60% 0.15 210) | Informational messages |

---

## Typography

### Font Stack

```css
--font-system: -apple-system, BlinkMacSystemFont, "SF Pro Text",
               "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
```

Uses native system fonts: **SF Pro** on macOS/iOS, **Segoe UI** on Windows.

### Type Scale (5-step, 1.25× ratio)

| Level | Size | Use Case |
|-------|------|----------|
| `xs` | 11px | Labels, helper text, captions |
| `sm` | 12px | Form labels, small UI text |
| `md` | 15px | Body text, standard content |
| `lg` | 19px | Headings, section titles |
| `xl` | 24px | Page titles |
| `2xl` | 30px | Hero titles |

### Line Height Scale

```
--line-height-tight: 1.2    (headings, dense info)
--line-height-normal: 1.5   (body text)
--line-height-relaxed: 1.75 (wide columns, light text on dark)
```

**Rule**: Light text on dark backgrounds gets +0.1 line-height for readability.

### Weight Distribution

| Weight | Usage |
|--------|-------|
| 500 | Labels, button text, small UI |
| 600 | Card headers, section titles |
| 700 | Page titles, emphasized text |

---

## Spacing

### 4pt Grid

All spacing follows a **4pt baseline grid** with semantic naming:

```css
--space-xs: 4px
--space-sm: 8px
--space-md: 12px
--space-lg: 16px
--space-xl: 24px
--space-2xl: 32px
--space-3xl: 48px
--space-4xl: 64px
```

### Spacing Patterns

- **Tight grouping** (within component): `space-xs` / `space-sm`
- **Normal grouping** (sibling elements): `space-md` / `space-lg`
- **Generous separation** (section breaks): `space-xl` / `space-2xl`

### Margin vs. Padding

- **Use `padding`** for internal spacing (inside containers)
- **Use `gap`** for sibling spacing (eliminates margin collapse)
- **Avoid margins** on component boundaries (parent controls spacing)

---

## Components

### Buttons

**Hierarchy**:
1. **Primary** — High-intent, promoted action (save, create, submit)
2. **Secondary** — Standard, safe action (cancel, reset, view)
3. **Destructive** — Irreversible, dangerous action (delete, remove)
4. **Ghost** — Minimal, de-emphasized action (inline links, hints)

**Sizes**:
- `btn-sm`: 24px height (tight contexts)
- `btn` (default): 28px height (standard)
- `btn-lg`: 36px height (prominent actions)

**Interactive States**:
- **Hover**: Darker shade + enhanced shadow
- **Active**: Scale(0.98) for tactile feedback
- **Focus**: 2px outline, 2px offset
- **Disabled**: 50% opacity, `cursor: not-allowed`

### Forms

**Input Focus**:
- Border → `--color-accent`
- Shadow → `0 0 0 3px rgba(0, 113, 227, 0.1)` (subtle glow)

**Labels**:
- Font size: `var(--font-size-sm)` (12px)
- Font weight: 500
- Color: `--color-text-primary`
- Required indicator: red asterisk

**Form Group Spacing**:
```
Form Group
├─ Label (space-sm)
├─ Input
├─ Help text (space-sm)
└─ Error message
```

### Tables

**Hierarchy**:
- Header background: `--color-bg-tertiary` (slightly raised)
- Header text: Font weight 600
- Body rows: Hover → `--color-bg-tertiary`
- Borders: 1px `--separator-color` (subtle)

**Dense Tables**: For data-heavy dashboards, use `table-dense` class (smaller padding, smaller font).

### Cards

**Anatomy**:
```
Card
├─ Header (optional, border-bottom)
│  ├─ Title
│  └─ Action buttons
├─ Body (main content)
└─ Footer (optional, border-top, right-aligned buttons)
```

**Spacing**:
- Outer padding: `space-lg` (16px)
- Header/footer borders: `separator-color-secondary`

### Alerts

**Never use side-stripe borders** (it's an AI slop pattern). Use **full borders instead**:

```css
border: 1px solid var(--color-warning);
background: rgba(255, 149, 0, 0.08);
color: var(--color-warning);
```

**Types**:
- **Info**: Blue border + blue text
- **Success**: Green border + green text
- **Warning**: Orange border + orange text
- **Destructive**: Red border + red text

### Badges

**Usage**: Status labels, tag pills, category indicators

**Types**:
- Filled: `badge-success`, `badge-warning`, `badge-destructive`
- Outline: `badge-outline` + variant class
- Secondary: `badge-secondary` (neutral)

### Metrics

**Dashboard stat cards**:
```
Metric Block
├─ Label (uppercase, small)
├─ Value (large, 2xl)
└─ Change (positive/negative/neutral)
```

---

## Layout Patterns

### Toolbar

- Height: 52px
- Padding: `0 space-md`
- Border-bottom: 1px separator
- Items: Vertically centered with `gap: space-md`

### Sidebar (Source List)

- Width: 220px
- Background: `--color-bg-secondary`
- Padding: `space-md 0`
- Section title: Uppercase, `font-size-xs`, `letter-spacing: 0.5px`

### Inspector Pane

- Width: 320px (collapsible)
- Background: `--color-bg-secondary`
- Used for: Detail views, property panels, form sidebars
- Closes on mobile

### Main Content

- Background: `--color-bg-primary`
- Padding: `space-lg` (16px)
- Max content width: 1200px (for very wide screens)

---

## Interactive States

### Hover

- Background elevation: Subtle shift in `--color-bg-tertiary`
- Shadow: None (keep it flat unless it's a button)
- Transition: `all 0.15s ease`

### Focus

- Outline: 2px solid `--color-accent`, 2px offset
- For form inputs: Blue glow shadow instead
- Never remove focus indicators

### Active/Pressed

- Scale: `0.98` (feels pressable)
- Transition: Immediate
- Release: Quick spring back

### Disabled

- Opacity: 0.5
- Cursor: `not-allowed`
- Pointer events: None
- No hover effects

---

## Dark Mode

### Philosophy

Dark mode isn't just "invert colors." It's a **first-class design equal to light mode**.

### Implementation

Use `@media (prefers-color-scheme: dark)` to apply dark-specific tokens:

```css
@media (prefers-color-scheme: dark) {
  :root {
    --color-bg-primary: oklch(15% 0.006 15);
    --color-bg-secondary: oklch(22% 0.01 15);
    /* ... */
  }
}
```

### Key Differences

| Aspect | Light | Dark |
|--------|-------|------|
| Background | Very light (96% lightness) | Very dark (15% lightness) |
| Brand tint | Subtle (chroma 0.003) | Visible (chroma 0.01) |
| Shadows | Transparent black | Darker opacity |
| Separation | Thin lines | More visible lines |

### Text on Dark

- Standard body text: `--color-text-primary` (96% lightness)
- Secondary text: `--color-text-secondary` (70% lightness)
- Contrast ratio: Always ≥ 7:1 (WCAG AAA)

---

## Responsiveness

### Breakpoints

- **768px and down**: Mobile/tablet layout
  - Inspector pane hidden (drawer on demand)
  - Sidebar becomes collapsible
  - Tables scroll horizontally
  - Grid → single column

- **480px and down**: Small mobile
  - Cards stack fully
  - Full-width buttons
  - Toolbar items wrap

### Mobile Patterns

1. **Toolbar**: Stays fixed, single-column layout
2. **Navigation**: Sidebar drawer (off-canvas)
3. **Forms**: Single column, full-width inputs
4. **Tables**: Horizontal scroll or card view
5. **Modals**: Full height except for keyboard

---

## Accessibility (WCAG AAA)

### Color Contrast

All text meets **7:1 minimum ratio**:
- Primary text on primary background: Enforced
- Secondary text on secondary background: Enforced
- Action colors: Large text (18pt+) meets 4.5:1 minimum

### Focus Indicators

- Never removed, always visible
- 2px outline, 2px offset for clarity
- Color: `--color-accent` (high contrast)

### Keyboard Navigation

- Tab order follows visual flow
- All interactive elements reachable via keyboard
- No keyboard traps
- Modals trap focus (return to trigger on close)

### Motion

- Respect `prefers-reduced-motion`
- Default animations: 0.15s ease (not bouncy)
- No auto-playing animations
- Critical animations still respect preference

### Semantics

- Use native HTML: `<button>`, `<form>`, `<input>`
- ARIA labels where needed: `aria-label`, `aria-describedby`
- Status messages: Use `role="status"` for live updates
- Alerts: Use `role="alert"` for urgent messages

---

## Avoiding AI Slop Patterns

### ✗ BANNED PATTERNS

1. **Side-stripe borders** (`border-left: 4px solid color`)
   - Rewrite: Use full border or background tint
2. **Gradient text** (`background-clip: text`)
   - Rewrite: Solid color text with weight/size variation
3. **Glassmorphism everywhere** (blur effects, glow borders)
   - Use sparingly: Only when semantically meaningful

### ✓ GOOD PATTERNS

1. **Full borders** for visual distinction
2. **Solid colors** for text
3. **Intentional shadows** for depth
4. **Varied spacing** for rhythm
5. **Semantic color** for meaning

---

## Component Showcase

See `/admin/demo` for an interactive showcase of:
- All button variants and sizes
- Form patterns (inputs, selects, checkboxes)
- Tables (standard and dense)
- Cards (with/without headers)
- Alerts (all types)
- Badges (filled/outline)
- Status indicators
- Loading states
- Empty states
- Modal patterns
- Color palette swatches

---

## Usage in HTML

### Basic Structure

```html
<div class="card">
  <div class="card-header">
    <h2 class="card-title">Card Title</h2>
    <button class="btn btn-secondary btn-sm">Action</button>
  </div>
  <div class="card-body">
    <form class="form">
      <div class="form-group">
        <label class="form-label required">Field</label>
        <input type="text" class="form-input" placeholder="...">
        <span class="form-help">Helper text</span>
      </div>
    </form>
  </div>
  <div class="card-footer">
    <button class="btn btn-destructive">Cancel</button>
    <button class="btn btn-primary">Save</button>
  </div>
</div>
```

### Layout Example

```html
<div class="app-layout">
  <header class="toolbar">
    <div class="toolbar-section">Logo</div>
    <div class="toolbar-section">Navigation</div>
    <div class="toolbar-section">User menu</div>
  </header>
  <aside class="sidebar"><!-- Navigation --></aside>
  <main class="content">
    <div class="content-pane"><!-- Content --></div>
    <div class="inspector-pane"><!-- Inspector --></div>
  </main>
</div>
```

---

## Future Enhancements

- [ ] Component variants library (Storybook export)
- [ ] Animation micro-interactions guide
- [ ] Theming plugin system
- [ ] RTL support
- [ ] High contrast mode support
- [ ] Mobile-first guide expansion

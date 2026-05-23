# Garazyk Admin UI — Quick Reference

## CSS Architecture

### Import Order

```html
<link rel="stylesheet" href="/css/system.css">
<!-- Fonts, vars, reset -->
<link rel="stylesheet" href="/css/tokens.css">
<!-- Color & spacing tokens -->
<link rel="stylesheet" href="/css/layout.css">
<!-- Toolbar, sidebar, panes -->
<link rel="stylesheet" href="/css/components.css">
<!-- Buttons, forms, cards -->
<link rel="stylesheet" href="/css/utilities.css">
<!-- Spacing, text, helpers -->
```

---

## Common Patterns

### Button Hierarchy

```html
<!-- Primary: Main action -->
<button class="btn btn-primary">Save</button>

<!-- Secondary: Safe, reversible -->
<button class="btn btn-secondary">Cancel</button>

<!-- Destructive: Irreversible -->
<button class="btn btn-destructive">Delete</button>

<!-- Success: Positive feedback -->
<button class="btn btn-success">Confirm</button>

<!-- Sizes -->
<button class="btn btn-sm">Small</button>
<button class="btn">Regular (28px)</button>
<button class="btn btn-lg">Large</button>

<!-- Icon button -->
<button class="btn btn-icon btn-secondary">⚙️</button>
```

### Forms

```html
<form class="form">
  <div class="form-group">
    <label class="form-label required">Username</label>
    <input type="text" class="form-input" placeholder="...">
    <span class="form-help">Helper text</span>
  </div>

  <div class="form-row">
    <div class="form-group">
      <label class="form-label">Email</label>
      <input type="email" class="form-input">
    </div>
    <div class="form-group">
      <label class="form-label">Phone</label>
      <input type="tel" class="form-input">
    </div>
  </div>

  <div class="form-footer">
    <button type="reset" class="btn btn-secondary">Reset</button>
    <button type="submit" class="btn btn-primary">Submit</button>
  </div>
</form>
```

### Cards

```html
<!-- Simple card -->
<div class="card">
  <div class="card-body">Content</div>
</div>

<!-- Card with header -->
<div class="card">
  <div class="card-header">
    <h3 class="card-title">Title</h3>
    <button class="btn btn-secondary btn-icon">✕</button>
  </div>
  <div class="card-body">Content</div>
</div>

<!-- Card with footer -->
<div class="card">
  <div class="card-header"><h3 class="card-title">Title</h3></div>
  <div class="card-body">Content</div>
  <div class="card-footer">
    <button class="btn btn-secondary">Cancel</button>
    <button class="btn btn-primary">Save</button>
  </div>
</div>
```

### Tables

```html
<!-- Standard table -->
<table class="table">
  <thead>
    <tr>
      <th>Column 1</th>
      <th>Column 2</th>
      <th>Action</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>Value 1</td>
      <td>Value 2</td>
      <td><button class="btn btn-secondary btn-sm">Edit</button></td>
    </tr>
  </tbody>
</table>

<!-- Dense table (for data-heavy views) -->
<table class="table table-dense">
  <!-- ... -->
</table>
```

### Alerts

```html
<!-- Info alert -->
<div class="alert alert-info">
  <div class="alert-title">Information</div>
  <div class="alert-message">This is an informational message.</div>
</div>

<!-- Success alert -->
<div class="alert alert-success">
  <div class="alert-title">Success</div>
  <div class="alert-message">Operation completed successfully.</div>
</div>

<!-- Warning alert -->
<div class="alert alert-warning">
  <div class="alert-title">Warning</div>
  <div class="alert-message">This requires caution.</div>
</div>

<!-- Error alert -->
<div class="alert alert-destructive">
  <div class="alert-title">Error</div>
  <div class="alert-message">Something went wrong.</div>
</div>
```

### Status Indicators

```html
<!-- Healthy -->
<span class="status-indicator connected"></span> Healthy

<!-- Warning -->
<span class="status-indicator pending"></span> Pending

<!-- Error -->
<span class="status-indicator disconnected"></span> Disconnected
```

### Badges

```html
<!-- Filled -->
<span class="badge badge-primary">Primary</span>
<span class="badge badge-success">Success</span>
<span class="badge badge-warning">Warning</span>
<span class="badge badge-destructive">Error</span>

<!-- Outline -->
<span class="badge badge-outline badge-primary">Primary</span>
```

### Metrics Dashboard

```html
<div class="metric-row">
  <div class="metric">
    <div class="metric-label">Requests</div>
    <div class="metric-value">12.3K</div>
  </div>
  <div class="metric">
    <div class="metric-label">Error Rate</div>
    <div class="metric-value status-warning">2.1%</div>
  </div>
  <div class="metric">
    <div class="metric-label">Uptime</div>
    <div class="metric-value status-healthy">99.9%</div>
  </div>
</div>
```

### Stat Cards

```html
<div class="stat-card">
  <div class="stat-label">Total Users</div>
  <div class="stat-value">1,234</div>
  <div class="stat-change positive">↑ 12% this week</div>
</div>
```

---

## Spacing Cheat Sheet

```
space-xs: 4px    (tight, within components)
space-sm: 8px    (small gaps)
space-md: 12px   (normal grouping)
space-lg: 16px   (standard section spacing)
space-xl: 24px   (generous spacing)
space-2xl: 32px  (large breaks)
```

**Rule**: Use `gap` for sibling spacing (flexbox), `padding` for internal, avoid margins on
boundaries.

---

## Color Tokens

### Backgrounds

- `--color-bg-primary`: Main background
- `--color-bg-secondary`: Cards, panels
- `--color-bg-tertiary`: Hover states, subtle contrast

### Text

- `--color-text-primary`: Main text
- `--color-text-secondary`: Labels, captions
- `--color-text-tertiary`: Subtle hints

### Actions

- `--color-accent`: Primary actions
- `--color-success`: Positive outcomes
- `--color-warning`: Caution
- `--color-destructive`: Dangerous/irreversible
- `--color-info`: Informational

### Structural

- `--separator-color`: Standard borders
- `--separator-color-secondary`: Subtle borders

---

## Utility Classes

### Display

```
.d-flex / .d-flex-col / .d-flex-row
.d-block / .d-inline-block / .d-none
.d-grid / .d-inline-flex
```

### Flexbox

```
.gap-xs / .gap-sm / .gap-md / .gap-lg
.align-items-center / .align-items-start / .align-items-end
.justify-content-between / .justify-content-center / .justify-content-end
.flex-1 / .flex-wrap
```

### Text

```
.text-xs / .text-sm / .text-base / .text-lg / .text-xl / .text-2xl
.text-primary / .text-secondary / .text-tertiary
.font-medium / .font-semibold / .font-bold
.text-center / .text-left / .text-right
.uppercase / .lowercase / .capitalize
```

### Spacing

```
.m-0 / .m-xs / .m-sm / .m-md / .m-lg / .m-xl
.mt-lg / .mb-lg / .mx-auto
.p-lg / .px-md / .py-lg
```

### Borders & Shadows

```
.border / .border-top / .border-bottom
.rounded / .rounded-sm / .rounded-lg / .rounded-full
.shadow-sm / .shadow-md / .shadow-lg
```

### State

```
.is-active / .is-inactive / .is-loading / .is-disabled
.is-error / .is-success / .is-warning
```

---

## Layout Patterns

### Full-Screen App

```html
<div class="app-shell">
  <header class="toolbar">
    <div class="toolbar-section">Brand</div>
    <div class="toolbar-section">Navigation</div>
    <div class="toolbar-section">User Menu</div>
  </header>

  <div class="app-layout">
    <aside class="sidebar"><!-- Navigation --></aside>

    <main role="main">
      <div class="content-area">
        <div class="content-pane"><!-- Content --></div>
      </div>
      <div class="inspector-pane"><!-- Inspector/Details --></div>
    </main>
  </div>

  <footer role="contentinfo" class="status-bar">
    <!-- Status info -->
  </footer>
</div>
```

### Card-Based Page

```html
<div class="content-pane">
  <div class="content-header">
    <h1 class="content-title">Page Title</h1>
    <p class="content-subtitle">Subtitle</p>
  </div>

  <div class="stack-lg">
    <div class="card"><!-- Card 1 --></div>
    <div class="card"><!-- Card 2 --></div>
  </div>
</div>
```

---

## Responsive Breakpoints

```css
/* Default: Desktop (1024px+) */
/* Tablet: 768px - 1023px */
@media (max-width: 768px) {
  /* Sidebar becomes drawer, inspector hides, grid becomes single column */
}

/* Mobile: < 480px */
@media (max-width: 480px) {
  /* Full-width buttons, stacked forms, card view tables */
}
```

---

## Accessibility Checklist

- [ ] All interactive elements have `focus` states (2px outline)
- [ ] Color not used as only indicator (pair with text/icon)
- [ ] Text contrast ≥ 7:1 (WCAG AAA)
- [ ] Images have alt text
- [ ] Form inputs have associated labels
- [ ] Modals trap focus
- [ ] Keyboard navigation works (Tab, Enter, Escape)
- [ ] Respects `prefers-reduced-motion` (skip animations)

---

## Dark Mode

Add this to `<head>` to test dark mode in dev:

```html
<meta name="color-scheme" content="light dark">
```

Or force via CSS:

```css
:root {
  color-scheme: dark;
}
```

All tokens automatically adjust via `@media (prefers-color-scheme: dark)`.

---

## Performance Tips

1. **Use CSS variables** — Changes in one place
2. **Minimize repaints** — Use `transform` / `opacity` for animations
3. **Lazy load** — Images, modals, heavy components
4. **Cache static** — CSS, fonts, icons in `/css/`, `/js/`, `/img/`
5. **GZIP** — Server should compress CSS/JS

---

## Debugging

### Check Color Contrast

DevTools → Accessibility panel → Check text/background ratios

### Keyboard Navigation

- Tab through all elements
- Tab + Shift to go backward
- Enter/Space to activate
- Escape to close modals

### Mobile Testing

DevTools → Device Toolbar → Test at 375px, 768px, 1024px

### Dark Mode

DevTools → Rendering → Emulate CSS media feature prefers-color-scheme

---

## Demo & Showcase

Visit `/admin/demo` to see:

- All components and variants
- Color palette swatches
- Typography scale
- Interactive patterns
- Live code examples

---

## Resources

- **Full Design System**: See `DESIGN_SYSTEM.md`
- **Component Library**: `/admin/demo` (interactive)
- **CSS Variables**: `tokens.css`
- **Icons**: Use system emoji or replace with icon library (e.g., Feather, Heroicons)

---

**Last Updated**: May 2026\
**Theme**: AppKit-native, light/dark mode, OKLCH colors, 4pt grid

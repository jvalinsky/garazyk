# AdminUI Architecture

> **Historical architecture input (2026-07-12):** This document describes the
> pre-`AdminUIServer` layout and is not an implementation map for the current
> service. The rewrite is tracked in
> `docs/plans/workstreams/04-web-and-admin-ui.md`. Use
> `Garazyk/Sources/AdminUIServer/` and its tests as source truth until then.

## System Overview

The AdminUI is an admin panel for the AT Protocol PDS (Personal Data Server). It
provides a unified interface for managing multiple services:

- **PDS** (Personal Data Server)
- **PLC** (DID Registry)
- **Relay** (BGS - Firehose Aggregator)
- **AppView** (Indexed Feed Service)
- **Chat** (Future)

## Technology Stack

- **Frontend**: HTML5 + CSS3 + HTMX 1.9.10
- **Design System**: Desktop-oriented aesthetic
- **Backend**: Objective-C (NSString templates + rendering)
- **Protocol**: HTTP/HTTPS with XRPC endpoints
- **Real-time**: Server-Sent Events (SSE) for updates

## Directory Structure

```
AdminUI/
├── Assets/
│   ├── index.html                  # Main entry point
│   ├── css/
│   │   ├── system.css              # Design tokens, colors, typography
│   │   ├── layout.css              # Header, sidebar, main content structure
│   │   ├── components.css          # Buttons, cards, tables, forms, badges
│   │   └── utilities.css           # Flexbox, spacing, text, sizing helpers
│   └── js/
│       └── app.js                  # Client-side interactivity
├── Handlers/
│   ├── AdminUIHandler.h/m          # Routes requests and serves assets
│   └── AdminUITemplateRenderer.h/m # Template engine ({{}} substitution)
└── Templates/
    ├── sections/
    │   ├── pds/
    │   │   ├── users.html
    │   │   ├── invites.html
    │   │   ├── blobs.html
    │   │   ├── identity.html
    │   │   └── health.html
    │   ├── plc/
    │   │   ├── did-lookup.html
    │   │   ├── export.html
    │   │   └── metrics.html
    │   ├── relay/
    │   │   ├── upstreams.html
    │   │   ├── events.html
    │   │   └── crawl.html
    │   └── appview/
    │       ├── backfill.html
    │       ├── index.html
    │       └── metrics.html
    └── partials/
        ├── _user-row.html
        ├── _invite-row.html
        ├── _empty-state.html
        └── users-search-response.html
```

## Data Flow

### Initial Page Load

```
User Browser
     ↓
GET /admin/ui
     ↓
AdminUIHandler (serves index.html)
     ↓
Browser renders HTML + loads CSS + executes JS
```

### Sidebar Navigation (HTMX)

```
User clicks "Users" in sidebar
     ↓
HTMX GET /admin/partials/users
     ↓
PDSAdminHandler (checks auth)
     ↓
AdminUIHandler.renderUsersPartial()
     ↓
Returns partial HTML
     ↓
HTMX swaps content in #content-pane
```

### Form Submission

```
User submits search form
     ↓
HTMX POST /admin/partials/users/search?q=search_term
     ↓
PDSAdminHandler (validates auth)
     ↓
AdminUIHandler.renderUsersSearchWithQuery()
     ↓
Returns HTML with search results
     ↓
HTMX swaps table rows in #users-list
```

### Real-time Events (SSE)

```
User loads Events section
     ↓
HTMX SSE hx-ext="sse" sse-connect="/xrpc/com.atproto.sync.subscribeRepos"
     ↓
PDSAdminHandler routes to XRPC handler
     ↓
XRPC handler opens WebSocket/SSE connection
     ↓
Events stream to browser and HTMX appends to list
```

## CSS System

### Color Tokens

```
Light Mode:
--color-bg-primary: #f5f5f7 (lightest background)
--color-bg-secondary: #ffffff (white)
--color-bg-tertiary: #efefef (darker background)
--color-text-primary: #1d1d1d (black text)
--color-text-secondary: #666666 (gray text)
--color-accent: #0071e3 (Apple blue)
--color-destructive: #ff453a (Apple red)
--color-success: #34c759 (Apple green)
--color-warning: #ff9500 (Apple orange)

Dark Mode:
Auto-switches via @media (prefers-color-scheme: dark)
```

### Spacing Scale

```
--space-xs: 4px
--space-sm: 8px
--space-md: 16px
--space-lg: 24px
--space-xl: 32px
--space-2xl: 48px
```

### Semantic Layout

```
┌─────────────────────────────────────┐
│ Header/Toolbar (52px)               │
├──────────┬──────────────────────────┤
│ Sidebar  │ Content Pane             │
│ (220px)  │ (flexible)               │
│          │                          │
│          │                          │
├──────────┴──────────────────────────┤
│ Status Bar (44px)                   │
└─────────────────────────────────────┘
```

## JavaScript Interactivity

### Service Switching

- Cmd/Ctrl+1 through Cmd/Ctrl+5 switch services
- Saves preference to localStorage
- Toggles sidebar section visibility

### Sidebar Sections

- Click title to collapse/expand
- Collapse state persists in localStorage
- Auto-scrolls to active item

### HTMX Integration

- Automatic loading indicators
- Error handling and notifications
- Form validation
- Table row interactions
- Modal dialogs
- Debounced search (500ms)

### Keyboard Navigation

- Tab navigation through all interactive elements
- Focus indicators on all buttons
- Escape to close modals
- Enter to submit forms

## Component Patterns

### Card

```html
<div class="card">
  <div class="card-header">
    <h3 class="card-title">Title</h3>
  </div>
  <div class="card-body">
    Content
  </div>
  <div class="card-footer">
    Actions
  </div>
</div>
```

### Table with Actions

```html
<table class="table">
  <thead>
    <tr>
      <th>Column</th>
      <th>Actions</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>Data</td>
      <td>
        <button hx-get="..." hx-target="...">Action</button>
      </td>
    </tr>
  </tbody>
</table>
```

### Form

```html
<form class="form" hx-post="/admin/endpoint" hx-swap="swap:outerHTML">
  <div class="form-group">
    <label class="form-label required">Field</label>
    <input type="text" class="form-input" required>
    <div class="form-help">Help text</div>
  </div>
  <button type="submit" class="btn btn-primary">Submit</button>
</form>
```

## Template Engine

### Features

- **Variable substitution**: `{{key}}` → value
- **Conditionals**: `{{#if key}}...{{/if}}`
- **Loops**: `{{#each array}}...{{/each}}`
- **HTML escaping**: Automatic XSS prevention
- **Nesting**: Conditionals and loops can nest

### Example

```html
<table>
  <tbody>
    {{#each users}}
    <tr>
      <td>{{name}}</td>
      <td>
        {{#if active}}
        <span class="badge badge-success">Active</span>
        {{else}}
        <span class="badge badge-secondary">Inactive</span>
        {{/if}}
      </td>
    </tr>
    {{/each}} {{#if !users}}
    <tr>
      <td colspan="2">No users found</td>
    </tr>
    {{/if}}
  </tbody>
</table>
```

## Security Considerations

1. **Authentication**: All `/admin/partials/*` routes require auth via
   PDSAdminAuth
2. **CSRF Protection**: HTMX requests use POST, which is CSRF-safe by default
3. **XSS Prevention**: Template engine auto-escapes all variables
4. **SQL Injection**: Backend uses parameterized queries (not shown here)
5. **Session Management**: Tokens expire based on PDSAdminAuth configuration

## Performance

### Bundle Size

- HTML entry point: ~12 KB
- CSS (all files): ~35 KB
- JavaScript: ~8 KB
- HTMX library (CDN): ~45 KB
- **Total**: ~100 KB (cached)

### Load Time

- Initial page load: ~500ms (gzipped)
- Partial loads: ~100-200ms (over network)
- Asset caching: Browser cache + CDN cache

### Real-time Updates

- SSE connections are lightweight
- Automatic reconnection on disconnect
- Backpressure handling for high-volume events

## Accessibility

### WCAG 2.1 AA Compliance

- ✅ Semantic HTML (header, nav, main, aside, footer)
- ✅ ARIA labels on all interactive elements
- ✅ Focus visible outlines (2px)
- ✅ Color contrast ratios meet WCAG standards
- ✅ Keyboard navigation support
- ✅ Screen reader support

### Focus Management

- Focus trapped in modals (Escape to close)
- Auto-focus on error/notification alerts
- Tab order follows DOM structure
- Skip links not yet implemented (future)

### Dark Mode

- Automatic detection via `prefers-color-scheme`
- All colors have dark mode variants
- Contrast ratios maintained in both modes

## Responsive Design

### Breakpoints

- Desktop: 1024px+ (full layout)
- Tablet: 768px-1023px (collapsible sidebar)
- Mobile: <768px (mobile-optimized, limited)

### Mobile Considerations

- Sidebar collapses with hamburger menu
- Touch targets minimum 44px
- Single-column layout on mobile
- Horizontal scrolling for tables

## Future Enhancements

1. **Data Integration**
   - Wire AdminUIHandler to real database queries
   - Implement search, filtering, pagination
   - Real-time metrics updates

2. **Advanced Features**
   - Bulk operations (select multiple users)
   - Export/import (CSV, JSON)
   - Advanced search filters
   - Audit trail viewer

3. **Mobile App**
   - React Native app using same XRPC APIs
   - Push notifications for alerts
   - Offline mode

4. **Performance**
   - Code splitting for service modules
   - Image optimization
   - Service worker for offline support
   - GraphQL API alternative

## Development Workflow

### Adding a New Section

1. Create template at `Templates/sections/{service}/{section}.html`
2. Create partial responses in `Templates/partials/`
3. Add rendering method to `AdminUIHandler.m`
4. Add route in `handlePartialPath:statusCode:contentType:`
5. Add sidebar item to `index.html`
6. Test with browser DevTools

### Styling Changes

1. Modify CSS in `Assets/css/`
2. Use CSS variables (--space-md, --color-accent, etc.)
3. Test in both light and dark modes
4. Verify responsive design at breakpoints

### JavaScript Enhancements

1. Add event listener in `Assets/js/app.js`
2. Use HTMX event handlers (htmx:beforeRequest, etc.)
3. Test keyboard navigation
4. Verify accessibility with screen reader

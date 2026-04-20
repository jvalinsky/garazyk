# Phase 1: Fix AI Slop Patterns

## Decision Node: 9

## Issues to Fix

### Issue 1: Alert Border-Left (BAN 1)
**Location**: `components.css` line 439
**Pattern**: `border-left: 4px solid` 
**Fix**: Replace with full border or background tint

### Issue 2: Generic Sidebar Active State
**Location**: `layout.css` line 176
**Pattern**: `.sidebar-item.active` uses blue background
**Fix**: Make more distinctive (macOS source list style)

## Implementation Notes

### Alert Fix Options
Option A: Use full border (not left-stripe)
```css
.alert {
  border: 1px solid <color>;
  border-left: none; /* remove */
}
```

Option B: Use background tint only
```css
.alert {
  border: none;
  background: rgba(color, 0.1);
}
```

Decision: Use Option A (full border) - maintains information density

### Sidebar Fix
Current:
```css
.sidebar-item.active {
  background: var(--color-accent);
  color: white;
}
```

New (AppKit source list style):
```css
.sidebar-item.active {
  background: var(--color-accent);
  color: white;
  font-weight: 500;
  /* Add subtle left accent bar */
}
```

Or use selection indicator like NSTableView
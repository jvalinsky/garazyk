# Swagger UI Theming Plan

This document outlines the comprehensive theming applied to Swagger UI to match the ATProto PDS Explorer's Classic Apple Developer Documentation style.

## Theme Overview

The Explorer uses a retro Apple Developer Documentation theme (2005-2007 era) characterized by:
- Gray gradient headers
- Blue gradient section titles
- Aqua-style buttons
- Lucida Grande typography
- Subtle shadows and borders

## Implementation Status

### ✅ Phase 1: Core Infrastructure (COMPLETED)
- [x] Download and bundle Swagger UI locally (v5.11.0)
- [x] Create `/vendor/` route handler
- [x] Update docs.html with Apple-style header
- [x] Create `swagger-ui-custom.css` theme file

### ✅ Phase 2: Header & Navigation (COMPLETED)
- [x] Gray gradient header (matches main app)
- [x] Apple-style navigation buttons
- [x] Aqua-style "Download YAML" button
- [x] Hide default Swagger topbar

### ✅ Phase 3: Section Headers (COMPLETED)
- [x] Blue gradient tag headers (#7ca7d8 → #5b8bc0)
- [x] White text with shadow
- [x] Matching expand/collapse icons

### ✅ Phase 4: Operation Styling (COMPLETED)
- [x] HTTP method badges with coordinated colors:
  - GET: Blue (#5b8bc0)
  - POST: Green (#68b368)
  - PUT: Orange (#e8a849)
  - DELETE: Red (#c95050)
  - PATCH: Purple (#8b72c9)
- [x] Subtle background tints for each method type
- [x] Monospace paths with Apple code styling

### ✅ Phase 5: Forms & Inputs (COMPLETED)
- [x] Apple-style text inputs with inset shadow
- [x] Focus states with blue glow
- [x] Parameters table with alternating rows
- [x] Required field indicators

### ✅ Phase 6: Buttons (COMPLETED)
- [x] "Try it out" button with Aqua gradient
- [x] "Execute" button with primary blue style
- [x] "Cancel" button with muted red style
- [x] Hover and active states

### ✅ Phase 7: Response Display (COMPLETED)
- [x] Code blocks with inset shadow
- [x] Response status code styling
- [x] JSON/YAML syntax in monospace
- [x] Copy-to-clipboard button styling

### ✅ Phase 8: Models Section (COMPLETED)
- [x] Blue gradient header for "Schemas"
- [x] Model expand/collapse styling
- [x] Property type highlighting

### ✅ Phase 9: Polish (COMPLETED)
- [x] Custom scrollbar styling (WebKit)
- [x] Print styles
- [x] Loading indicators
- [x] Error message styling

## Future Enhancements

### Potential Phase 10: Dark Mode Support
- [ ] CSS custom properties for color schemes
- [ ] Media query for `prefers-color-scheme: dark`
- [ ] Dark Apple-inspired palette

### Potential Phase 11: Enhanced Interactivity
- [ ] Animated transitions for expand/collapse
- [ ] Enhanced tooltip styling
- [ ] Better mobile responsiveness

### Potential Phase 12: Integration Features
- [ ] Link to Explorer for response DIDs
- [ ] Auto-populate parameters from current selection
- [ ] Bookmark/favorite endpoints

## CSS Architecture

```
Assets/
├── vendor/
│   └── swagger-ui/
│       ├── swagger-ui-bundle.js      # Core Swagger UI JS
│       ├── swagger-ui-standalone-preset.js
│       ├── swagger-ui.css            # Default Swagger styles
│       └── swagger-ui-custom.css     # Our Apple theme overrides
└── docs.html                          # Host page with inline header styles
```

## Color Reference

| Variable | Value | Usage |
|----------|-------|-------|
| `--apple-section-header-start` | #7ca7d8 | Section header gradient start |
| `--apple-section-header-end` | #5b8bc0 | Section header gradient end |
| `--apple-selection-bg` | #3d80df | Selected items background |
| `--apple-link-color` | #0066cc | Link text color |
| `--apple-border-light` | #cccccc | Light borders |
| `--apple-bg-code` | #f4f4f4 | Code block background |
| `--method-get` | #5b8bc0 | GET badge |
| `--method-post` | #68b368 | POST badge |
| `--method-put` | #e8a849 | PUT badge |
| `--method-delete` | #c95050 | DELETE badge |
| `--method-patch` | #8b72c9 | PATCH badge |

## Testing Checklist

- [x] Header displays correctly
- [x] Section headers expand/collapse
- [x] Endpoints list with correct styling
- [x] Parameter inputs work
- [x] "Try it out" functionality works
- [x] Response display renders correctly
- [x] Models section expands correctly
- [x] Links navigate properly
- [x] Download YAML button works
- [x] Explorer link returns to main app

## Related Files

- `/ATProtoPDS/Sources/App/Explore/Assets/docs.html` - Host page
- `/ATProtoPDS/Sources/App/Explore/Assets/vendor/swagger-ui/swagger-ui-custom.css` - Theme CSS
- `/ATProtoPDS/Sources/App/Explore/ExploreHandler.m` - Serves vendor files
- `/ATProtoPDS/Sources/CLI/PDSCLIServeCommand.m` - Route registration

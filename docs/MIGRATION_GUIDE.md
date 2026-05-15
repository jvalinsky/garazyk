---
title: Documentation Migration
---

# Documentation Migration Guide

The Garazyk documentation has migrated from Jekyll to VitePress. This guide details URL mapping and new features.

## URL Mapping

VitePress uses extensionless URLs. While automatic redirects handle legacy `.html` paths, update your bookmarks and internal links to the new format.

| Content | Legacy URL (Jekyll) | New URL (VitePress) |
|---------|--------------------|---------------------|
| Index | `/docs/index.html` | `/docs/` |
| Overview | `/docs/01-getting-started/overview.html` | `/docs/01-getting-started/overview` |
| Tutorials | `/docs/10-tutorials/tutorial-1.html` | `/docs/10-tutorials/tutorial-1` |

### Automatic Redirects
VitePress handles the following automatically:
1. **Extension removal:** `/docs/page.html` → `/docs/page`
2. **Trailing slashes:** `/docs/page/` → `/docs/page`
3. **Index files:** `/docs/section/` → `/docs/section/index`

## New Features

### Full-Text Search
- **Shortcut:** `Cmd+K` (Mac) or `Ctrl+K` (Linux/Windows).
- Fuzzy matching across all prose and code blocks.

### Code Blocks
- Native syntax highlighting for Objective-C, Go, and Shell.
- Integrated copy-to-clipboard buttons and tabbed code groups.

### Navigation
- Collapsible sidebar with persistent scroll state.
- Breadcrumbs for path tracing.

## Related
- [URL Mapping (Legacy)](URL_MAPPING)
- [Maintenance Guide](MAINTENANCE)

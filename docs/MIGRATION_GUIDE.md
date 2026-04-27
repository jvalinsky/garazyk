---
title: Documentation Migration
---

# Documentation Migration Guide

The Garazyk PDS documentation has moved from Jekyll to VitePress. This guide details URL changes and new features.

## URL Structure Changes

VitePress uses extensionless URLs. While automatic redirects are in place for legacy `.html` paths, bookmarks and internal links should be updated to the new format.

| Content | Legacy URL (Jekyll) | New URL (VitePress) |
|---------|--------------------|---------------------|
| Index | `/docs/index.html` | `/docs/` |
| Overview | `/docs/01-getting-started/overview.html` | `/docs/01-getting-started/overview` |
| Tutorials | `/docs/10-tutorials/tutorial-1.html` | `/docs/10-tutorials/tutorial-1` |

Anchor links (e.g., `#prerequisites`) remain unchanged.

## New Features

### Search
- **Shortcut**: `Cmd+K` (Mac) or `Ctrl+K` (Linux/Windows).
- **Function**: Full-text indexing across prose and code blocks with fuzzy matching.

### Code Blocks
- **Syntax Highlighting**: Native support for Objective-C, Go, and Shell.
- **Interactivity**: Copy-to-clipboard buttons and code group tabs for platform-specific examples.

### Navigation
- **Sidebar**: Collapsible section management and persistent scroll state.
- **Breadcrumbs**: Path tracing for the current document.

## Frequently Asked Questions

- **Will old links work?**: Yes, server-side redirects handle legacy paths.
- **How do I report broken links?**: Open an issue on GitHub with the source page and the broken destination.
- **Is the old site available?**: The Jekyll site is archived. All content has been migrated and enhanced in the VitePress version.

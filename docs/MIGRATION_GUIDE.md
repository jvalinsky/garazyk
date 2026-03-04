---
title: Documentation Migration Guide
---

# Documentation Migration Guide

**September PDS Documentation has migrated from Jekyll to VitePress!**

This guide helps you navigate the changes and update your bookmarks and references.

## What Changed

### New Documentation System

We've migrated from Jekyll to VitePress, bringing significant improvements:

✅ **Faster performance** - Built with Vite for instant page loads  
✅ **Better search** - Full-text search with instant results  
✅ **Enhanced code blocks** - Syntax highlighting, line numbers, copy buttons  
✅ **Improved navigation** - Sidebar, breadcrumbs, and table of contents  
✅ **Dark mode** - Native dark/light theme support  
✅ **Mobile-friendly** - Responsive design for all devices  

### What Stayed the Same

✅ **Same URL** - Still at `https://pds.garazyk.xyz/docs`  
✅ **Same structure** - 12 sections organized the same way  
✅ **Same content** - All documentation preserved and enhanced  
✅ **Same diagrams** - All SVG diagrams included  

## URL Changes

### URL Format Changes

Jekyll and VitePress handle URLs slightly differently:

**Jekyll format** (old):
```

https://pds.garazyk.xyz/docs/01-getting-started/overview.html
```

**VitePress format** (new):
```

https://pds.garazyk.xyz/docs/01-getting-started/overview
```

**Key differences**:
- ✅ No `.html` extension in VitePress URLs
- ✅ Cleaner, more modern URL structure
- ✅ Automatic redirects handle old URLs

### URL Mapping

Most URLs follow a simple pattern - just remove `.html`:

| Old Jekyll URL | New VitePress URL |
|----------------|-------------------|
| `/docs/index.html` | `/docs/` or `/docs/index` |
| `/docs/01-getting-started/overview.html` | `/docs/01-getting-started/overview` |
| `/docs/02-core-concepts/atproto-basics.html` | `/docs/02-core-concepts/atproto-basics` |
| `/docs/10-tutorials/tutorial-1-hello-pds.html` | `/docs/10-tutorials/tutorial-1-hello-pds` |

### Anchor Links

Anchor links (links to specific sections) work the same way:

**Old**: `https://pds.garazyk.xyz/docs/01-getting-started/overview.html#prerequisites`  
**New**: `https://pds.garazyk.xyz/docs/01-getting-started/overview#prerequisites`

## Updating Your Bookmarks

### Browser Bookmarks

If you have bookmarked documentation pages:

1. **Option 1: Let redirects handle it** - Old URLs automatically redirect to new ones
2. **Option 2: Update manually** - Remove `.html` from your bookmark URLs

### External References

If you've linked to our documentation from:
- Blog posts
- README files
- Other documentation
- Stack Overflow answers
- Social media posts

**Good news**: Old URLs will redirect automatically! But for best practices, update links to the new format.

### Code Comments

If you have links in code comments:

```objc
// Old (still works, but update when convenient):
// See: https://pds.garazyk.xyz/docs/02-core-concepts/cbor-and-car.html

// New (preferred):
// See: https://pds.garazyk.xyz/docs/02-core-concepts/cbor-and-car
```

## Complete URL Mapping Reference

### Section 01: Getting Started

| Old URL | New URL |
|---------|---------|
| `/docs/01-getting-started/overview.html` | `/docs/01-getting-started/overview` |
| `/docs/01-getting-started/architecture-overview.html` | `/docs/01-getting-started/architecture-overview` |
| `/docs/01-getting-started/setup.html` | `/docs/01-getting-started/setup` |

### Section 02: Core Concepts

| Old URL | New URL |
|---------|---------|
| `/docs/02-core-concepts/atproto-basics.html` | `/docs/02-core-concepts/atproto-basics` |
| `/docs/02-core-concepts/cbor-and-car.html` | `/docs/02-core-concepts/cbor-and-car` |
| `/docs/02-core-concepts/mst-trees.html` | `/docs/02-core-concepts/mst-trees` |
| `/docs/02-core-concepts/cryptography.html` | `/docs/02-core-concepts/cryptography` |
| `/docs/02-core-concepts/plc-directory.html` | `/docs/02-core-concepts/plc-directory` |
| `/docs/02-core-concepts/did-document-updates.html` | `/docs/02-core-concepts/did-document-updates` |

### Section 03: Application Layer

| Old URL | New URL |
|---------|---------|
| `/docs/03-application-layer/pds-application.html` | `/docs/03-application-layer/pds-application` |
| `/docs/03-application-layer/services-overview.html` | `/docs/03-application-layer/services-overview` |
| `/docs/03-application-layer/account-service.html` | `/docs/03-application-layer/account-service` |
| `/docs/03-application-layer/record-service.html` | `/docs/03-application-layer/record-service` |
| `/docs/03-application-layer/blob-service.html` | `/docs/03-application-layer/blob-service` |
| `/docs/03-application-layer/repository-service.html` | `/docs/03-application-layer/repository-service` |
| `/docs/03-application-layer/relay-service.html` | `/docs/03-application-layer/relay-service` |
| `/docs/03-application-layer/admin-service.html` | `/docs/03-application-layer/admin-service` |

### Section 04: Network Layer

| Old URL | New URL |
|---------|---------|
| `/docs/04-network-layer/http-server.html` | `/docs/04-network-layer/http-server` |
| `/docs/04-network-layer/xrpc-dispatch.html` | `/docs/04-network-layer/xrpc-dispatch` |
| `/docs/04-network-layer/method-registry.html` | `/docs/04-network-layer/method-registry` |
| `/docs/04-network-layer/domain-methods.html` | `/docs/04-network-layer/domain-methods` |
| `/docs/04-network-layer/auth-helpers.html` | `/docs/04-network-layer/auth-helpers` |
| `/docs/04-network-layer/error-handling.html` | `/docs/04-network-layer/error-handling` |
| `/docs/04-network-layer/rate-limiting.html` | `/docs/04-network-layer/rate-limiting` |
| `/docs/04-network-layer/dos-protection.html` | `/docs/04-network-layer/dos-protection` |
| `/docs/04-network-layer/request-throttling.html` | `/docs/04-network-layer/request-throttling` |
| `/docs/04-network-layer/input-validation.html` | `/docs/04-network-layer/input-validation` |

### Section 05: Database Layer

| Old URL | New URL |
|---------|---------|
| `/docs/05-database-layer/sqlite-architecture.html` | `/docs/05-database-layer/sqlite-architecture` |
| `/docs/05-database-layer/actor-databases.html` | `/docs/05-database-layer/actor-databases` |
| `/docs/05-database-layer/service-databases.html` | `/docs/05-database-layer/service-databases` |
| `/docs/05-database-layer/migrations.html` | `/docs/05-database-layer/migrations` |
| `/docs/05-database-layer/wal-mode.html` | `/docs/05-database-layer/wal-mode` |
| `/docs/05-database-layer/migration-strategy.html` | `/docs/05-database-layer/migration-strategy` |
| `/docs/05-database-layer/data-integrity.html` | `/docs/05-database-layer/data-integrity` |
| `/docs/05-database-layer/migration-rollback.html` | `/docs/05-database-layer/migration-rollback` |
| `/docs/05-database-layer/zero-downtime-migrations.html` | `/docs/05-database-layer/zero-downtime-migrations` |

### Section 06: Authentication

| Old URL | New URL |
|---------|---------|
| `/docs/06-authentication/jwt-tokens.html` | `/docs/06-authentication/jwt-tokens` |
| `/docs/06-authentication/oauth2-dpop.html` | `/docs/06-authentication/oauth2-dpop` |
| `/docs/06-authentication/totp-webauthn.html` | `/docs/06-authentication/totp-webauthn` |
| `/docs/06-authentication/key-rotation.html` | `/docs/06-authentication/key-rotation` |
| `/docs/06-authentication/secrets-management.html` | `/docs/06-authentication/secrets-management` |
| `/docs/06-authentication/security-best-practices.html` | `/docs/06-authentication/security-best-practices` |

### Section 07: Repository Protocol

| Old URL | New URL |
|---------|---------|
| `/docs/07-repository-protocol/repository-basics.html` | `/docs/07-repository-protocol/repository-basics` |
| `/docs/07-repository-protocol/cbor-serialization.html` | `/docs/07-repository-protocol/cbor-serialization` |
| `/docs/07-repository-protocol/cid-and-hashing.html` | `/docs/07-repository-protocol/cid-and-hashing` |
| `/docs/07-repository-protocol/car-format.html` | `/docs/07-repository-protocol/car-format` |
| `/docs/07-repository-protocol/blob-storage.html` | `/docs/07-repository-protocol/blob-storage` |
| `/docs/07-repository-protocol/blob-lifecycle.html` | `/docs/07-repository-protocol/blob-lifecycle` |
| `/docs/07-repository-protocol/blob-optimization.html` | `/docs/07-repository-protocol/blob-optimization` |
| `/docs/07-repository-protocol/blob-garbage-collection.html` | `/docs/07-repository-protocol/blob-garbage-collection` |
| `/docs/07-repository-protocol/blob-quotas.html` | `/docs/07-repository-protocol/blob-quotas` |

### Section 08: Sync & Firehose

| Old URL | New URL |
|---------|---------|
| `/docs/08-sync-firehose/firehose-overview.html` | `/docs/08-sync-firehose/firehose-overview` |
| `/docs/08-sync-firehose/websocket-server.html` | `/docs/08-sync-firehose/websocket-server` |
| `/docs/08-sync-firehose/commit-broadcasting.html` | `/docs/08-sync-firehose/commit-broadcasting` |
| `/docs/08-sync-firehose/backpressure.html` | `/docs/08-sync-firehose/backpressure` |
| `/docs/08-sync-firehose/reliability-guarantees.html` | `/docs/08-sync-firehose/reliability-guarantees` |
| `/docs/08-sync-firehose/event-replay.html` | `/docs/08-sync-firehose/event-replay` |
| `/docs/08-sync-firehose/reconnection-strategy.html` | `/docs/08-sync-firehose/reconnection-strategy` |
| `/docs/08-sync-firehose/event-ordering.html` | `/docs/08-sync-firehose/event-ordering` |
| `/docs/08-sync-firehose/firehose-rate-limiting.html` | `/docs/08-sync-firehose/firehose-rate-limiting` |

### Section 09: Platform Compatibility

| Old URL | New URL |
|---------|---------|
| `/docs/09-platform-compatibility/macos-linux.html` | `/docs/09-platform-compatibility/macos-linux` |
| `/docs/09-platform-compatibility/compatibility-layer.html` | `/docs/09-platform-compatibility/compatibility-layer` |
| `/docs/09-platform-compatibility/network-transport.html` | `/docs/09-platform-compatibility/network-transport` |
| `/docs/09-platform-compatibility/arc-runtime.html` | `/docs/09-platform-compatibility/arc-runtime` |

### Section 10: Tutorials

| Old URL | New URL |
|---------|---------|
| `/docs/10-tutorials/tutorial-1-hello-pds.html` | `/docs/10-tutorials/tutorial-1-hello-pds` |
| `/docs/10-tutorials/tutorial-2-accounts.html` | `/docs/10-tutorials/tutorial-2-accounts` |
| `/docs/10-tutorials/tutorial-3-records.html` | `/docs/10-tutorials/tutorial-3-records` |
| `/docs/10-tutorials/tutorial-4-auth.html` | `/docs/10-tutorials/tutorial-4-auth` |
| `/docs/10-tutorials/tutorial-5-firehose.html` | `/docs/10-tutorials/tutorial-5-firehose` |
| `/docs/10-tutorials/tutorial-6-deployment.html` | `/docs/10-tutorials/tutorial-6-deployment` |

### Section 11: Reference

| Old URL | New URL |
|---------|---------|
| `/docs/11-reference/api-reference.html` | `/docs/11-reference/api-reference` |
| `/docs/11-reference/cli-reference.html` | `/docs/11-reference/cli-reference` |
| `/docs/11-reference/config-reference.html` | `/docs/11-reference/config-reference` |
| `/docs/11-reference/troubleshooting.html` | `/docs/11-reference/troubleshooting` |
| `/docs/11-reference/test-organization.html` | `/docs/11-reference/test-organization` |
| `/docs/11-reference/e2e-testing.html` | `/docs/11-reference/e2e-testing` |
| `/docs/11-reference/property-based-testing.html` | `/docs/11-reference/property-based-testing` |
| `/docs/11-reference/test-coverage-goals.html` | `/docs/11-reference/test-coverage-goals` |
| `/docs/11-reference/security-audit-guide.html` | `/docs/11-reference/security-audit-guide` |
| `/docs/11-reference/plc-server-operations.html` | `/docs/11-reference/plc-server-operations` |
| `/docs/11-reference/plc-failover.html` | `/docs/11-reference/plc-failover` |
| `/docs/11-reference/metrics-collection.html` | `/docs/11-reference/metrics-collection` |
| `/docs/11-reference/alerting.html` | `/docs/11-reference/alerting` |
| `/docs/11-reference/performance-monitoring.html` | `/docs/11-reference/performance-monitoring` |
| `/docs/11-reference/logging-strategy.html` | `/docs/11-reference/logging-strategy` |

### Section 12: Diagrams

| Old URL | New URL |
|---------|---------|
| `/docs/12-diagrams/index.html` | `/docs/12-diagrams/` or `/docs/12-diagrams/index` |

### Special Pages

| Old URL | New URL |
|---------|---------|
| `/docs/index.html` | `/docs/` or `/docs/index` |
| `/docs/GLOSSARY.html` | `/docs/GLOSSARY` |
| `/docs/SUMMARY.html` | `/docs/SUMMARY` |

## New Features You'll Love

### Enhanced Search

Press `Cmd+K` (Mac) or `Ctrl+K` (Windows/Linux) to open search:
- Instant results as you type
- Search through all content including code
- Keyboard navigation (arrow keys, Enter)
- Fuzzy matching for typos

### Better Code Blocks

Code examples now have:
- Syntax highlighting for Objective-C and other languages
- Line numbers for easy reference
- Copy-to-clipboard buttons
- Line highlighting for emphasis
- Code group tabs for platform-specific examples

### Improved Navigation

- **Sidebar**: Collapsible sections, current page highlighting
- **Breadcrumbs**: See where you are in the documentation
- **Table of Contents**: Auto-generated for each page
- **Previous/Next**: Navigate sequentially through sections
- **Mobile-friendly**: Hamburger menu on small screens

### Dark Mode

Click the theme toggle in the navbar to switch between light and dark modes. Your preference is saved automatically.

### Interactive Diagrams

All SVG diagrams are now:
- Properly sized and scaled
- Accessible with alt text
- Zoomable (click to enlarge)
- Listed in the diagram index

## Frequently Asked Questions

### Will old links still work?

Yes! We've configured automatic redirects from old Jekyll URLs to new VitePress URLs. Your existing bookmarks and external links will continue to work.

### Do I need to update my code comments?

Not immediately, but we recommend updating links to the new format when convenient. Old URLs will redirect, but new URLs are cleaner and more future-proof.

### What if I find a broken link?

Please report it! Create an issue on GitHub with:
- The page where you found the broken link
- The link that's broken
- What you expected to find

### Can I still access the old Jekyll site?

The old Jekyll site has been archived. All content has been migrated to VitePress with enhancements. If you need to reference the old site for any reason, contact the maintainers.

### How do I report issues with the new documentation?

Create an issue on GitHub:
1. Go to the repository
2. Click "Issues" → "New Issue"
3. Describe the problem
4. Tag with `documentation` label

### Where can I learn more about VitePress?

- **VitePress Documentation**: https://vitepress.dev/
- **Our Maintenance Guide**: See `docs/MAINTENANCE.md`
- **GitHub Repository**: Check the README

## Migration Timeline

- **Planning**: December 2024
- **Development**: January 2025
- **Testing**: February 2025
- **Migration Complete**: March 2025
- **Old URLs Redirect**: Indefinitely (no planned removal)

## Feedback

We'd love to hear your thoughts on the new documentation system!

**What's better?**
- Faster performance?
- Better search?
- Improved navigation?
- Enhanced code blocks?

**What needs improvement?**
- Missing features?
- Confusing navigation?
- Broken links?
- Accessibility issues?

Please share your feedback by:
- Creating a GitHub issue
- Commenting on the migration announcement
- Contacting the maintainers directly

## Thank You

Thank you for using September PDS documentation! We hope the new VitePress system provides a better experience for learning and reference.

Happy coding! 🚀

---
title: "URL Mapping: Jekyll to VitePress"
---

# URL Mapping: Jekyll to VitePress

This document tracks URL changes during the migration from Jekyll to VitePress.

For the most up-to-date mapping and redirection logic, see the [Migration Guide](MIGRATION_GUIDE).

## Key Changes
- **Extensionless URLs:** `.html` extensions are no longer required in the browser.
- **Base Path:** All documentation remains under the `/docs/` path.
- **Structure:** The directory structure is preserved from the original Jekyll site.

## Testing Redirects
To verify that legacy URLs are still handled correctly:
```bash
# Verify that .html extension redirects work
curl -I https://pds.garazyk.xyz/docs/01-getting-started/overview.html
```

## Related
- [Migration Guide](MIGRATION_GUIDE)
- [Deployment Guide](DEPLOYMENT_GUIDE)

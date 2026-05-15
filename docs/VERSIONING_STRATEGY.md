---
title: Documentation Versioning Strategy
---

# Documentation Versioning Strategy

This document defines how documentation is synchronized with Garazyk PDS releases.

## Approach

We follow semantic versioning (**Major.Minor.Patch**) for both code and documentation.

### Branching Model
- **`main` branch:** Matches the latest stable release.
- **`develop` branch:** In-progress documentation for the next release.
- **Tags:** Versions are pinned using Git tags (e.g., `v1.0.0`).

## Documentation Workflow

### New Releases
1. **Develop:** Update docs alongside code changes.
2. **Review:** Verify examples compile and diagrams reflect architectural changes.
3. **Release:** Merge `develop` to `main`, tag the release, and deploy to the docs site.

### Indicators & Callouts
Use version-specific callouts for clarity:

> **New in v1.1.0:** Description of the new feature.

> **Deprecated in v2.0.0:** This method is replaced by `newMethod`.

## Archiving

Major version releases may require archiving the previous documentation to maintain accessibility for users on older versions.

- **Location:** `docs/archive/vX.Y/`
- **Policy:** Archives are read-only and include a banner pointing to the latest version.

## Related
- [Update Checklist](DOCUMENTATION_UPDATE_CHECKLIST)
- [Maintenance Guide](MAINTENANCE)
- [Deployment Guide](DEPLOYMENT_GUIDE)

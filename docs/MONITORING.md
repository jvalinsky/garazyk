---
title: Documentation Monitoring Guide
---

# Documentation Monitoring Guide

This guide describes the monitoring and health-check infrastructure for the Garazyk documentation system.

## Build Monitoring

### GitHub Actions
The documentation build is tracked via the `Build Documentation` workflow in `.github/workflows/build-docs.yml`.

**Monitored Metrics:**
- **Build Status:** Success or failure of the VitePress build.
- **Validation:** Link integrity, diagram references, and code block syntax.
- **Performance:** Build duration (typically < 5 minutes).
- **Deployment:** Success of the push to the `gh-pages` branch.

### Alerts
Automatic notifications are triggered on workflow failure.
- **Maintainers:** Notified via GitHub web/email notifications.
- **Slack/Discord:** Optional webhooks can be configured in the workflow YAML for real-time channel alerts.

## Link Validation

### Automated Checks
Validation runs on every push and pull request.
- **Internal Links:** Immediate failure on broken cross-references.
- **Diagrams:** Verifies all SVG references in `12-diagrams/` exist.
- **External Links:** Periodic validation with rate-limiting to avoid false positives.

### Scheduled Maintenance
A daily cron job in GitHub Actions runs a comprehensive link check to identify bit-rot in external references.

## Analytics (Optional)

VitePress supports privacy-focused analytics. Configuration is managed in `docs/.vitepress/config.ts`.

### Plausible (Recommended)
Add the following to the `head` section for GDPR-compliant tracking:
```typescript
[
  'script',
  {
    defer: '',
    'data-domain': 'pds.garazyk.xyz',
    src: 'https://plausible.io/js/script.js'
  }
]
```

### Metrics of Interest
- **Popular Pages:** Identifies high-traffic documentation areas.
- **Search Queries:** Reveals missing content or unclear terminology.
- **404 Errors:** Pinpoints broken external inbound links.

## Incident Response

If a documentation build fails:

1. **Check Logs:** Inspect the GitHub Actions console for the specific validation error.
2. **Reproduce Locally:**
   ```bash
   cd docs
   npm run docs:build
   ```
3. **Fix & Verify:** Resolve the broken link or syntax error and run `npm run validate:all`.
4. **Push:** Commit the fix to trigger a new build.

## Related

- [Deployment Guide](DEPLOYMENT_GUIDE)
- [Maintenance Guide](MAINTENANCE)
- [Update Checklist](DOCUMENTATION_UPDATE_CHECKLIST)

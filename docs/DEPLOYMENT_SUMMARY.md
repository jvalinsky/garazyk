---
title: Documentation Deployment Summary
---

# Documentation Deployment Summary

This document summarizes the deployment state, verification steps, and access information for the Garazyk PDS documentation site.

## Overview

The documentation site is built with VitePress and serves as the primary technical reference for the Garazyk PDS. It is automatically synchronized with the repository.

## Deployment Details

### Build Information
- **Build Directory:** `docs/.vitepress/dist/`
- **Build Engine:** VitePress (Node.js)
- **CI/CD:** GitHub Actions (`.github/workflows/build-docs.yml`)
- **Host:** GitHub Pages (via `gh-pages` branch) or internal PDS documentation container.

### Primary Access Points

- **Internal PDS Route:** `https://pds.garazyk.xyz/docs/`
- **GitHub Pages:** `https://garazyk.github.io/atproto-pds/`

## Verification Steps

The following checks ensure documentation integrity during deployment:

### 1. Build Integrity
- Validates that `docs/.vitepress/dist/` contains all generated HTML.
- Ensures the entry `index.html` and section subdirectories are correctly structured.

### 2. Content & Navigation
- Verifies all sidebar links are functional.
- Ensures the search index is correctly generated for full-text search.
- Validates that diagrams and SVGs are correctly rendered.

### 3. Automated Validation
- Broken link detection across all markdown files.
- Code example syntax verification.
- SVG optimization and reference checks.

## Maintenance Workflow

### Automatic Updates
Pushing to the `main` branch triggers a GitHub Actions workflow that builds and redeploys the site automatically.

### Manual Local Preview
To test changes before committing:

```bash
cd docs
npm install
npm run docs:dev    # Hot-reloading development server
npm run docs:build  # Full production build
npm run docs:preview # Preview the production build locally
```

## Rollback Procedure

If a deployment introduces issues, you can revert to a previous stable state:

1. Identify the last known good commit in the `main` branch.
2. Revert the problematic changes or force-push the `gh-pages` branch to the previous stable build commit.
3. Verify the site status at the primary access points.

## Related

- [Deployment Guide](DEPLOYMENT_GUIDE)
- [Monitoring](MONITORING)
- [Maintenance](MAINTENANCE)
- [Versioning Strategy](VERSIONING_STRATEGY)

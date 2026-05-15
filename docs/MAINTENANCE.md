---
title: Documentation Maintenance
---

# Documentation Maintenance Guide

This guide describes the workflow for updating the Garazyk PDS documentation.

## Content Update Workflow

1. **Local Development:**
   ```bash
   cd docs
   npm run docs:dev
   ```
   Access the preview at `http://localhost:5173/docs/`.

2. **Editing:**
   - Files are located in the `docs/` directory, organized by section.
   - VitePress supports hot-reloading for Markdown changes.

3. **Validation:**
   ```bash
   npm run validate:all
   ```
   This script checks for broken links, missing diagrams, and code block formatting.

4. **Committing:**
   Use the `docs: [section] - [description]` format for commit messages.

## Content Standards

- **Directness:** Explain technical concepts directly before providing code examples.
- **Front Matter:** Every page requires a `title` and `description`.
- **Cross-References:** Use extensionless URLs for internal links (e.g., `[Title](path/to/page)`).

## Diagrams

- **Source:** SVGs are in `docs/12-diagrams/`. 
- **Optimization:** Run `npm run optimize:svg` before committing new diagrams.
- **Index:** Register new diagrams in the [Diagram Reference](12-diagrams/index).

## Deployment

The site is automatically deployed to `pds.garazyk.xyz/docs` via GitHub Actions upon pushing to the `main` branch. See the [Deployment Guide](DEPLOYMENT_GUIDE) for details.

## Troubleshooting

- **Server Failures:** Ensure Node.js 18+ is installed and clear the cache at `docs/.vitepress/cache`.
- **Broken Links:** Use `npm run validate:links` to identify incorrect relative paths.

## Related
- [Monitoring Guide](MONITORING)
- [Deployment Guide](DEPLOYMENT_GUIDE)
- [Update Checklist](DOCUMENTATION_UPDATE_CHECKLIST)

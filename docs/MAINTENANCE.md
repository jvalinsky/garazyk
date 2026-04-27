---
title: Documentation Maintenance
---

# Documentation Maintenance Guide

This guide describes the workflow for updating the VitePress documentation for the Garazyk PDS.

## Content Update Workflow

1. **Local Development**:
   ```bash
   cd docs
   npm run docs:dev
   ```
   Access the preview at `http://localhost:5173/docs/`.

2. **Editing**:
   - Files are located in the `docs/` directory, organized by section (e.g., `01-getting-started`).
   - VitePress supports hot-reloading for Markdown changes.

3. **Validation**:
   ```bash
   npm run validate:all
   ```
   This script checks for broken links, missing diagrams, and code block formatting.

4. **Committing**:
   Use the `docs: [section] - [description]` message format for commits.

## Content Standards

- **Clarity**: Explain technical concepts directly before providing code examples.
- **Front Matter**: Every page requires a title and description.
- **Cross-References**: Use extensionless URLs for internal links (e.g., `[Title](/path/to/page)`).

## Adding Pages

1. **Create File**: Add a new `.md` file in the appropriate section directory.
2. **Configure Sidebar**: Add the new page to `docs/.vitepress/sidebar.ts`.
3. **Verify**: Check navigation and search in the local development server.

## Diagrams

- **Storage**: Source SVGs are in `docs/12-diagrams/`. Optimized SVGs for the public site are in `docs/public/diagrams/`.
- **Optimization**: Run `npm run optimize:svg` before committing new diagrams.

## Build and Deployment

### Local Build
```bash
npm run docs:build
```
Built files are stored in `docs/.vitepress/dist/`.

### Production Deployment
The site is automatically deployed to `pds.garazyk.xyz/docs` via GitHub Actions upon pushing to the `main` branch. 

## Troubleshooting

- **Server Failures**: Ensure Node.js 18+ is installed and clear the cache at `docs/.vitepress/cache`.
- **Search Issues**: The search index is only generated during the build process; it is not available in development mode.
- **Broken Links**: Use `npm run validate:links` to identify incorrect relative paths or legacy `.html` extensions.

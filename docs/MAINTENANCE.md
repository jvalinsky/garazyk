---
title: VitePress Documentation Maintenance Guide
---

# VitePress Documentation Maintenance Guide

This guide provides comprehensive instructions for maintaining and updating the Garazyk PDS VitePress documentation.

## Table of Contents

- [Content Update Workflow](#content-update-workflow)
- [Adding New Documentation Pages](#adding-new-documentation-pages)
- [Updating Diagrams](#updating-diagrams)
- [Build and Deployment Process](#build-and-deployment-process)
- [Troubleshooting Guide](#troubleshooting-guide)

## Content Update Workflow

### Making Content Changes

1. **Navigate to the docs directory**:
   ```bash
   cd docs
   ```text

2. **Start the development server**:
   ```bash
   npm run docs:dev
   ```text
   The site will be available at `http://localhost:5173/docs/`

3. **Edit Markdown files**:
   - All documentation files are in the `docs/` directory
   - Files are organized by section (01-getting-started through 12-diagrams)
   - Changes are hot-reloaded automatically in the browser

4. **Preview your changes**:
   - Check formatting, code blocks, and links in the browser
   - Verify dark/light theme appearance
   - Test navigation and search

5. **Run validation**:
   ```bash
   npm run validate:all
   ```text
   This checks for broken links, missing diagrams, and code block issues

6. **Commit and push**:
   ```bash
   git add docs/
   git commit -m "docs: update [section] - [brief description]"
   git push
   ```text

### Content Guidelines

- **Use clear, conversational technical writing**
- **Explain concepts before showing code**
- **Include "Why this matters" sections for important concepts**
- **Add troubleshooting sections for common issues**
- **Cross-reference related documentation**
- **Use consistent terminology from GLOSSARY.md**

### Front Matter

Every documentation page should have front matter:

```yaml
---
title: Page Title
description: Brief description for SEO and search
outline: deep
---
```

- `title`: Required - appears in browser tab and search results
- `description`: Optional but recommended - used for SEO
- `outline`: Controls table of contents depth (`deep`, `[2,3]`, or `false`)

## Adding New Documentation Pages

### Step 1: Create the Markdown File

Create a new `.md` file in the appropriate section directory:

```bash
# Example: Adding a new page to core concepts
touch docs/02-core-concepts/new-topic.md
```

## Step 2: Add Front Matter

```markdown
---
title: New Topic Title
description: Brief description of the topic
outline: deep
---

# New Topic Title

Introduction paragraph explaining what this topic covers...

## Section 1

Content here...
```

### Step 3: Update Sidebar Navigation

Edit `docs/.vitepress/sidebar.ts` to add your new page:

```typescript
{
  text: '02 Core Concepts',
  collapsed: false,
  items: [
    { text: 'AT Protocol Basics', link: '/02-core-concepts/atproto-basics' },
    // ... existing items ...
    { text: 'New Topic Title', link: '/02-core-concepts/new-topic' }, // Add here
  ]
}
```

### Step 4: Test Navigation

1. Start dev server: `npm run docs:dev`
2. Verify the new page appears in the sidebar
3. Click the link to ensure it works
4. Check that the page is searchable

### Step 5: Add Cross-References

Link to your new page from related documentation:

```markdown
For more information, see <!-- Link placeholder: New Topic Title -->.
```

### Using Templates

Templates are available in `docs/templates/`:

- `SERVICE_TEMPLATE.md` - For service layer documentation
- `XRPC_ENDPOINT_TEMPLATE.md` - For XRPC endpoint documentation
- `TUTORIAL_TEMPLATE.md` - For tutorial pages

Copy a template and fill in the sections:

```bash
cp docs/templates/SERVICE_TEMPLATE.md docs/03-application-layer/new-service.md
```

## Updating Diagrams

### Diagram Location

- Source SVG files: `docs/12-diagrams/*.svg`
- Public directory: `docs/public/diagrams/*.svg` (copied during build)

### Adding a New Diagram

1. **Create or export the SVG file**:
   - Use a tool like draw.io, Figma, or Inkscape
   - Export as SVG with embedded fonts
   - Optimize the SVG: `npm run optimize:svg`

2. **Add to both locations**:
   ```bash
   cp new-diagram.svg docs/12-diagrams/
   cp new-diagram.svg docs/public/diagrams/
   ```text

3. **Embed in documentation**:
   ```markdown
   ![Diagram Title](# Diagram not found: new-diagram.svg)
   
   *Figure: Description of what the diagram shows*
   ```text

4. **Add to diagram index**:
   Edit `docs/12-diagrams/index.md` to include your new diagram:
   ```markdown
   ## New Diagram Title
   
   ![New Diagram](# Diagram not found: new-diagram.svg)
   
   **Description**: What this diagram illustrates
   
   **Used in**: <!-- Link placeholder: Page Name -->
   ```text

### Updating Existing Diagrams

1. **Edit the source SVG** in `docs/12-diagrams/`
2. **Copy to public directory**:
   ```bash
   cp docs/12-diagrams/updated-diagram.svg docs/public/diagrams/
   ```text
3. **Verify in browser** - diagrams are cached, so hard refresh (Cmd+Shift+R)

### Diagram Best Practices

- **Use consistent colors** matching the site theme
- **Include alt text** for accessibility
- **Keep file sizes small** (< 100KB if possible)
- **Test in both light and dark modes**
- **Use clear labels** and readable font sizes

## Build and Deployment Process

### Local Build

Build the static site locally:

```bash
cd docs
npm run docs:build
```

Output is in `docs/.vitepress/dist/`

### Preview Production Build

Preview the built site locally:

```bash
npm run docs:preview
```

This serves the production build at `http://localhost:4173/docs/`

### Validation Before Deployment

Always run validation before deploying:

```bash
# Validate links
npm run validate:links

# Validate diagrams
npm run validate:diagrams

# Validate code blocks
npm run validate:code-blocks

# Run all validations
npm run validate:all
```

## Deployment to Production

The documentation is deployed to `pds.garazyk.xyz/docs` via GitHub Actions.

**Automatic Deployment**:
1. Push to `main` branch
2. GitHub Actions runs `.github/workflows/build-docs.yml`
3. Validation checks run automatically
4. If validation passes, site is built and deployed
5. Changes appear at `https://pds.garazyk.xyz/docs` within minutes

**Manual Deployment** (if needed):

```bash
# Build the site
cd docs
npm run docs:build

# Deploy to server (adjust for your setup)
rsync -avz .vitepress/dist/ user@pds.garazyk.xyz:/var/www/docs/
```

## Deployment Verification

After deployment, verify:

```bash
# Run deployment verification script
npm run verify:deployment

# Or manually check:
curl -I https://pds.garazyk.xyz/docs/
curl https://pds.garazyk.xyz/docs/index.html | grep "Garazyk PDS"
```

## Troubleshooting Guide

### Common Issues and Solutions

#### Issue: Dev server won't start

**Symptoms**: `npm run docs:dev` fails with errors

**Solutions**:
1. Check Node.js version: `node --version` (requires 18+)
2. Reinstall dependencies: `rm -rf node_modules package-lock.json && npm install`
3. Clear VitePress cache: `rm -rf docs/.vitepress/cache`
4. Check for port conflicts: `lsof -i :5173`

#### Issue: Broken links in documentation

**Symptoms**: Validation reports broken internal links

**Solutions**:
1. Run link validation: `npm run validate:links`
2. Check the validation report for specific broken links
3. Common causes:
   - File was moved or renamed
   - Link uses `.md` extension (should be extensionless)
   - Incorrect relative path
4. Fix links and re-validate

#### Issue: Diagrams not displaying

**Symptoms**: Diagram shows broken image icon

**Solutions**:
1. Verify file exists in `docs/public/diagrams/`
2. Check file path in markdown (should start with `/diagrams/`)
3. Verify SVG is valid: open in browser directly
4. Check browser console for 404 errors
5. Hard refresh browser (Cmd+Shift+R)

#### Issue: Code blocks not highlighting correctly

**Symptoms**: Code appears as plain text without syntax highlighting

**Solutions**:
1. Verify language identifier is specified:
   ````markdown
   ```objc
   // code here
   ```text
   ````text
2. Check supported languages in `docs/.vitepress/config.ts`
3. For Objective-C, use `objc` or `objective-c`
4. Clear browser cache and reload

#### Issue: Search not finding content

**Symptoms**: Search returns no results for known content

**Solutions**:
1. Rebuild the site: `npm run docs:build`
2. Search index is built at build time, not in dev mode
3. Check that content is in markdown body (not just code comments)
4. Verify page has proper front matter with title

#### Issue: Build fails with "out of memory"

**Symptoms**: Build process crashes with heap memory error

**Solutions**:
1. Increase Node.js memory: `NODE_OPTIONS="--max-old-space-size=4096" npm run docs:build`
2. Check for circular imports in custom components
3. Reduce number of large images/diagrams
4. Optimize SVG files: `npm run optimize:svg`

#### Issue: Navigation sidebar not updating

**Symptoms**: New pages don't appear in sidebar

**Solutions**:
1. Verify page is added to `docs/.vitepress/sidebar.ts`
2. Check for syntax errors in sidebar config
3. Restart dev server
4. Clear VitePress cache: `rm -rf docs/.vitepress/cache`

#### Issue: Dark mode styling issues

**Symptoms**: Content unreadable in dark mode

**Solutions**:
1. Test both themes: click theme toggle in navbar
2. Check custom CSS in `docs/.vitepress/theme/style.css`
3. Use CSS variables for colors (defined in theme)
4. Avoid hardcoded colors in markdown

#### Issue: Slow build times

**Symptoms**: Build takes several minutes

**Solutions**:
1. Check for large files in `docs/public/`
2. Optimize images: `npm run optimize:images`
3. Reduce number of pages built (if testing)
4. Use `npm run docs:dev` for development (faster)

### Getting Help

If you encounter issues not covered here:

1. **Check VitePress documentation**: https://vitepress.dev/
2. **Review build logs**: Look for specific error messages
3. **Check GitHub Issues**: Search for similar problems
4. **Ask for help**: Create an issue with:
   - What you were trying to do
   - What happened instead
   - Error messages (full text)
   - Steps to reproduce

### Maintenance Checklist

Regular maintenance tasks:

**Weekly**:
- [ ] Run link validation: `npm run validate:links`
- [ ] Check for outdated dependencies: `npm outdated`
- [ ] Review and close resolved issues

**Monthly**:
- [ ] Update dependencies: `npm update`
- [ ] Review and update documentation for accuracy
- [ ] Check external links: `npm run validate:external-links`
- [ ] Review analytics (if enabled) for popular pages

**Quarterly**:
- [ ] Major dependency updates: `npm upgrade`
- [ ] Comprehensive content review
- [ ] Accessibility audit: `npm run validate:accessibility`
- [ ] Performance audit: `npm run validate:performance`

### Emergency Rollback

If a deployment breaks the site:

1. **Revert the commit**:
   ```bash
   git revert HEAD
   git push
   ```text

2. **Or rollback to previous version**:
   ```bash
   git reset --hard <previous-commit-hash>
   git push --force
   ```text

3. **Verify rollback**:
   ```bash
   curl -I https://pds.garazyk.xyz/docs/
   ```text

4. **Investigate the issue** before redeploying

## Additional Resources

- **VitePress Documentation**: https://vitepress.dev/
- **Markdown Guide**: https://www.markdownguide.org/
- **Vue 3 Documentation**: https://vuejs.org/ (for custom components)
- **Shiki Themes**: https://shiki.style/themes (syntax highlighting)

## Contact

For questions or issues with the documentation system:
- Create an issue in the GitHub repository
- Tag with `documentation` label
- Provide detailed description and steps to reproduce

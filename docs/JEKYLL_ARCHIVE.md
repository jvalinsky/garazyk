---
title: Jekyll Documentation Archive
---

# Jekyll Documentation Archive

This document describes the archival of the original Jekyll-based documentation system.

## Archive Information

**Archive Date**: March 2025  
**Original System**: Jekyll static site generator  
**New System**: VitePress static site generator  
**Migration Completion**: March 2025  

## What Was Archived

### Jekyll Configuration Files

The following Jekyll configuration files have been archived:

- `docs/_config.yml` - Jekyll site configuration
- `docs/Gemfile` - Ruby dependencies (if present)
- `docs/Gemfile.lock` - Locked Ruby dependencies (if present)
- Jekyll-specific front matter in Markdown files (converted to VitePress format)

### Jekyll-Specific Files

Files that were specific to Jekyll and no longer needed:

- `_layouts/` directory (if present) - Jekyll layout templates
- `_includes/` directory (if present) - Jekyll partial templates
- `_sass/` directory (if present) - Jekyll Sass stylesheets
- `.jekyll-cache/` directory - Jekyll build cache
- `_site/` directory - Jekyll build output

## Archive Location

**Backup created**: `docs-jekyll-backup/` (local backup, not committed)

To create a backup before removing Jekyll files:

```bash
# Create backup directory
mkdir -p docs-jekyll-backup

# Copy Jekyll-specific files
cp docs/_config.yml docs-jekyll-backup/ 2>/dev/null || true
cp docs/Gemfile docs-jekyll-backup/ 2>/dev/null || true
cp docs/Gemfile.lock docs-jekyll-backup/ 2>/dev/null || true

# Archive with timestamp
tar -czf docs-jekyll-backup-$(date +%Y%m%d).tar.gz docs-jekyll-backup/

echo "Jekyll documentation archived to docs-jekyll-backup-$(date +%Y%m%d).tar.gz"
```

## What Was Preserved

All content was preserved and migrated to VitePress:

✅ **All Markdown files** - Converted to VitePress format  
✅ **All code examples** - Preserved without modification  
✅ **All SVG diagrams** - Copied to VitePress public directory  
✅ **All documentation sections** - 12 sections maintained  
✅ **Navigation structure** - Converted to VitePress sidebar  
✅ **GLOSSARY.md** - Preserved as-is  
✅ **SUMMARY.md** - Preserved for reference  

## Migration Changes

### Front Matter Conversion

**Jekyll format** (old):
```yaml
---
layout: default
title: Page Title
---
```

**VitePress format** (new):
```yaml
---
title: Page Title
description: Brief description
outline: deep
---
```

### URL Format Changes

**Jekyll URLs**:
```

https://pds.garazyk.xyz/docs/page.html
```

**VitePress URLs**:
```

https://pds.garazyk.xyz/docs/page
```

Automatic redirects handle old URLs.

### Build System Changes

**Jekyll build** (old):
```bash
bundle exec jekyll build
```

**VitePress build** (new):
```bash
npm run docs:build
```

## Removed Dependencies

The following Jekyll/Ruby dependencies are no longer needed:

### Ruby Gems (if present)

- `jekyll` - Static site generator
- `jekyll-theme-*` - Jekyll themes
- `kramdown` - Markdown parser
- `rouge` - Syntax highlighting
- Other Jekyll plugins

### System Dependencies

- Ruby runtime (no longer required for documentation)
- Bundler (Ruby package manager)
- Jekyll gem dependencies

**Note**: Ruby may still be needed for other parts of the project, but not for documentation.

## Cleanup Steps

### Step 1: Verify VitePress Migration

Before removing Jekyll files, verify the VitePress migration is complete:

```bash
# Build VitePress site
cd docs
npm run docs:build

# Verify build output
ls -la .vitepress/dist/

# Test locally
npm run docs:preview
```

## Step 2: Create Backup

Create a backup of Jekyll configuration:

```bash
# Run the backup script above
mkdir -p docs-jekyll-backup
cp docs/_config.yml docs-jekyll-backup/ 2>/dev/null || true
tar -czf docs-jekyll-backup-$(date +%Y%m%d).tar.gz docs-jekyll-backup/
```

## Step 3: Remove Jekyll Files

Remove Jekyll-specific files (after backup):

```bash
# Remove Jekyll configuration
rm -f docs/_config.yml
rm -f docs/Gemfile
rm -f docs/Gemfile.lock

# Remove Jekyll directories (if present)
rm -rf docs/_layouts
rm -rf docs/_includes
rm -rf docs/_sass
rm -rf docs/.jekyll-cache
rm -rf docs/_site

# Commit changes
git add docs/
git commit -m "docs: remove Jekyll configuration files after VitePress migration"
```

## Step 4: Update README

Update the main README to reflect the new documentation system:

**Old reference** (remove):
```markdown
## Documentation

Documentation is built with Jekyll. To build locally:

\```bash
cd docs
bundle install
bundle exec jekyll serve
\```text
```

**New reference** (add):
```markdown
## Documentation

Documentation is built with VitePress. To build locally:

\```bash
cd docs
npm install
npm run docs:dev
\```text

Visit https://pds.garazyk.xyz/docs for the live documentation.
```

### Step 5: Update Build Scripts

Update any build scripts that reference Jekyll:

**Check for Jekyll references**:
```bash
grep -r "jekyll" scripts/
grep -r "bundle exec" scripts/
```

**Update to VitePress**:
- Replace `bundle exec jekyll build` with `npm run docs:build`
- Replace `bundle exec jekyll serve` with `npm run docs:dev`
- Update paths from `_site/` to `.vitepress/dist/`

### Step 6: Update CI/CD

Update GitHub Actions workflows:

**Old Jekyll workflow** (remove or update):
```yaml
- name: Build Jekyll site
  run: |
    cd docs
    bundle install
    bundle exec jekyll build
```

**New VitePress workflow** (already in place):
```yaml
- name: Build VitePress site
  run: |
    cd docs
    npm install
    npm run docs:build
```

## Rollback Procedure

If you need to rollback to Jekyll (not recommended):

### Step 1: Restore Backup

```bash
# Extract backup
tar -xzf docs-jekyll-backup-YYYYMMDD.tar.gz

# Restore files
cp docs-jekyll-backup/_config.yml docs/
cp docs-jekyll-backup/Gemfile docs/ 2>/dev/null || true
cp docs-jekyll-backup/Gemfile.lock docs/ 2>/dev/null || true
```

## Step 2: Revert Front Matter

Revert VitePress front matter back to Jekyll format in all Markdown files.

### Step 3: Rebuild with Jekyll

```bash
cd docs
bundle install
bundle exec jekyll build
```

**Note**: This is a complex process and not recommended. The VitePress migration is one-way by design.

## Migration Verification

Verify the migration was successful:

### Content Verification

```bash
# Run migration verification
cd docs
npm run verify:migration
```

## Link Verification

```bash
# Check all links
npm run validate:links
```

## Visual Verification

1. Visit https://pds.garazyk.xyz/docs
2. Navigate through all sections
3. Verify diagrams display correctly
4. Test search functionality
5. Check dark/light theme modes
6. Test on mobile devices

## Historical Reference

### Jekyll Site Structure

The original Jekyll site had this structure:

```

docs/
├── _config.yml           # Jekyll configuration
├── _layouts/             # Layout templates (if present)
├── _includes/            # Partial templates (if present)
├── _sass/                # Sass stylesheets (if present)
├── 01-getting-started/   # Content sections
├── 02-core-concepts/
├── ...
├── 12-diagrams/
├── index.md              # Home page
└── GLOSSARY.md           # Glossary
```

### Jekyll Build Process

1. Jekyll reads `_config.yml`
2. Processes Markdown files with Kramdown
3. Applies layouts from `_layouts/`
4. Generates static HTML in `_site/`
5. Serves with built-in server or deploys to hosting

### Why We Migrated

**Performance**: VitePress is significantly faster than Jekyll
- Jekyll build: ~30-60 seconds
- VitePress build: ~5-10 seconds

**Developer Experience**: Better tooling and hot reload
- Jekyll: Slow rebuild on changes
- VitePress: Instant hot module replacement

**Features**: Modern features out of the box
- Jekyll: Requires plugins for search, dark mode, etc.
- VitePress: Built-in search, dark mode, Vue components

**Maintenance**: Simpler dependency management
- Jekyll: Ruby gems, Bundler, system dependencies
- VitePress: npm packages only

**Ecosystem**: Active development and community
- Jekyll: Mature but slower development
- VitePress: Active development, modern features

## Support

### Questions About the Archive

If you have questions about the Jekyll archive:
- Check this document first
- Review the migration guide: `docs/MIGRATION_GUIDE.md`
- Create a GitHub issue with `documentation` label

### Accessing Old Documentation

If you need to access the old Jekyll documentation:
- Restore from backup (see Rollback Procedure)
- Check git history: `git log --all -- docs/_config.yml`
- Contact maintainers for archived copies

### Migration Issues

If you discover issues with the migration:
- Create a GitHub issue with `documentation` and `migration` labels
- Include specific pages or content affected
- Provide screenshots or examples if possible

## Timeline

- **December 2024**: Migration planning
- **January 2025**: VitePress setup and migration tool development
- **February 2025**: Content migration and enhancement
- **March 2025**: Testing, validation, and deployment
- **March 2025**: Jekyll archive and cleanup

## Acknowledgments

Thank you to the Jekyll project for providing a solid foundation for our documentation. The migration to VitePress builds on that foundation with modern tooling and enhanced features.

## References

- **Jekyll Documentation**: https://jekyllrb.com/docs/
- **VitePress Documentation**: https://vitepress.dev/
- **Migration Guide**: `docs/MIGRATION_GUIDE.md`
- **Maintenance Guide**: `docs/MAINTENANCE.md`

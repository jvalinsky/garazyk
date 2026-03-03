# Documentation Deployment Guide

This guide explains how to deploy and maintain the PDS Objective-C Implementation Guide documentation.

## Quick Start

### Automatic Deployment (Recommended)

The documentation is automatically deployed when you push to the `main` branch:

```bash
# Make changes to documentation
vim docs/01-getting-started/overview.md

# Commit and push
git add docs/
git commit -m "Update documentation"
git push origin main

# GitHub Actions automatically builds and deploys
# Site updates within 1-2 minutes
```

### Manual Local Build

To build and test locally:

```bash
# Build the site
./scripts/build-docs.sh

# Serve locally
cd docs
jekyll serve

# Open http://localhost:4000 in browser
```

## Deployment Architecture

### GitHub Pages Setup

The documentation uses GitHub Pages with the following configuration:

1. **Source Branch:** `gh-pages`
2. **Build Tool:** Jekyll
3. **Trigger:** Push to `main` branch
4. **Workflow:** `.github/workflows/build-docs.yml`

### Build Process

```
Source Files (docs/*.md)
    ↓
GitHub Actions Workflow
    ↓
Jekyll Build (docs/_site/)
    ↓
Deploy to gh-pages Branch
    ↓
GitHub Pages Serves Site
```

## Deployment Verification

### Check Build Status

```bash
# View GitHub Actions workflow
# Go to: https://github.com/<owner>/<repo>/actions

# Or check via CLI
gh run list --workflow=build-docs.yml
```

### Test Site Accessibility

```bash
# Test main page
curl -I https://<owner>.github.io/<repo>/

# Test specific page
curl https://<owner>.github.io/<repo>/01-getting-started/overview.html | head -20
```

### Verify Content

1. Navigate to the site URL
2. Check main index page loads
3. Test navigation links
4. Verify diagrams display
5. Check code examples render correctly

## Troubleshooting

### Build Fails in GitHub Actions

**Check logs:**
1. Go to Actions tab in repository
2. Click on failed workflow run
3. Expand "Build Documentation" step
4. Review error messages

**Common issues:**
- Missing Ruby dependencies: Check `docs/Gemfile`
- Markdown syntax errors: Validate markdown files
- Missing images: Verify image paths are correct

### Site Not Updating

**Possible causes:**
1. Changes not pushed to `main` branch
2. Workflow not triggered (check branch protection rules)
3. Build failed (check Actions tab)
4. GitHub Pages not configured (check Settings → Pages)

**Resolution:**
```bash
# Force rebuild
git commit --allow-empty -m "Trigger documentation rebuild"
git push origin main
```

### Local Build Issues

**Jekyll not installed:**
```bash
# Install Ruby and Jekyll
brew install ruby
gem install jekyll bundler

# Or use Python fallback
python3 scripts/build-docs-python.py
```

**Dependencies missing:**
```bash
cd docs
bundle install
jekyll build
```

## Maintenance Tasks

### Regular Updates

Keep documentation synchronized with code:

1. **After code changes:** Update relevant documentation
2. **After releases:** Update version numbers and examples
3. **Quarterly review:** Check for outdated information

### Adding New Pages

To add a new documentation page:

1. Create markdown file in appropriate directory
2. Add entry to `docs/SUMMARY.md`
3. Update navigation if needed
4. Commit and push to `main`

Example:
```bash
# Create new page
cat > docs/03-application-layer/new-service.md << 'EOF'
# New Service Documentation

Content here...
EOF

# Update table of contents
vim docs/SUMMARY.md

# Commit and push
git add docs/
git commit -m "Add new service documentation"
git push origin main
```

### Updating Diagrams

To update diagrams:

1. Edit SVG files in `docs/12-diagrams/`
2. Or regenerate from source
3. Commit and push
4. Site updates automatically

### Monitoring Performance

Check site performance:

```bash
# Check build time
# View in GitHub Actions workflow logs

# Monitor site size
du -sh docs/_site/

# Check page load times
# Use browser developer tools or tools like WebPageTest
```

## Advanced Configuration

### Custom Domain

To use a custom domain:

1. Go to repository Settings → Pages
2. Under "Custom domain", enter your domain
3. Add DNS records as instructed
4. GitHub Pages will handle SSL certificate

### Custom Theme

To customize the site appearance:

1. Edit `docs/_config.yml`
2. Modify Jekyll theme settings
3. Add custom CSS in `docs/assets/`
4. Commit and push

### Search Functionality

To add search:

1. Install Jekyll search plugin
2. Configure in `_config.yml`
3. Add search UI to layout
4. Rebuild and deploy

## Deployment Checklist

Before deploying documentation updates:

- [ ] Content is accurate and complete
- [ ] Links are working (internal and external)
- [ ] Code examples are tested
- [ ] Diagrams are clear and accurate
- [ ] Markdown syntax is valid
- [ ] No broken image references
- [ ] Changes committed with clear message
- [ ] Pushed to `main` branch
- [ ] GitHub Actions workflow completed successfully
- [ ] Site is accessible and updated

## Rollback Procedure

If you need to revert documentation:

```bash
# Find the commit to revert to
git log --oneline docs/

# Revert specific commit
git revert <commit-hash>
git push origin main

# Or reset to previous state
git reset --hard <commit-hash>
git push origin main --force
```

## Performance Optimization

### Reduce Build Time

1. Minimize image sizes
2. Optimize SVG diagrams
3. Use efficient markdown
4. Avoid large code blocks

### Reduce Site Size

1. Compress images
2. Minify CSS/JavaScript
3. Remove unused assets
4. Archive old content

## Security Considerations

### Sensitive Information

Never commit:
- API keys or secrets
- Private URLs or IPs
- Personal information
- Internal configuration

### Access Control

1. Restrict who can push to `main`
2. Require pull request reviews
3. Use branch protection rules
4. Enable status checks

## Support and Resources

### Documentation Tools

- [Jekyll Documentation](https://jekyllrb.com/docs/)
- [GitHub Pages Guide](https://docs.github.com/en/pages)
- [Markdown Guide](https://www.markdownguide.org/)

### Troubleshooting Resources

- [GitHub Pages Troubleshooting](https://docs.github.com/en/pages/getting-started-with-github-pages/troubleshooting-common-issues-with-github-pages)
- [Jekyll Troubleshooting](https://jekyllrb.com/docs/troubleshooting/)

### Getting Help

1. Check GitHub Actions logs for build errors
2. Review Jekyll documentation
3. Check GitHub Pages status page
4. Open an issue in the repository

---

**Last Updated:** 2026-03-02  
**Maintained By:** Development Team

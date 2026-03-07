---
title: VitePress Documentation Deployment Guide
---

# VitePress Documentation Deployment Guide

This guide covers deploying the VitePress documentation to staging and production environments.

## Prerequisites

- Node.js 20+ installed
- Docker and Docker Compose (for containerized deployment)
- Access to production server (crimson-comet.exe.xyz) for production deployment
- npm dependencies installed (`cd docs && npm ci`)

## Deployment Environments

### 1. Local Preview

For local testing before deployment:

```bash
cd docs
npm run docs:build
npm run docs:preview
```

Visit: http://localhost:4173/docs

### 2. Staging (Docker)

Deploy to local Docker container for staging tests:

```bash
# Build and deploy
./docs/scripts/deploy-docs.sh staging

# Verify deployment
./docs/scripts/verify-deployment.sh http://localhost:8080
```

Visit: http://localhost:8080/docs

## 3. Production (pds.garazyk.xyz)

**CRITICAL**: Production deployment must be done from the production server.

### On Production Server (crimson-comet.exe.xyz)

```bash
# SSH to production server
ssh exedev@crimson-comet.exe.xyz

# Navigate to repository
cd /home/exedev/objpds

# Pull latest changes
git pull origin main

# Build documentation
cd docs
npm ci
npm run docs:build

# Deploy (from docker/docs directory)
cd ../docker/docs
docker compose down
docker compose up -d --build

# Verify deployment
curl -I https://pds.garazyk.xyz/docs/
```

## Verify Production Deployment

```bash
# From any machine
./docs/scripts/verify-deployment.sh https://pds.garazyk.xyz
```

## Deployment Scripts

### deploy-docs.sh

Main deployment script supporting multiple environments:

```bash
# Preview (local dev server)
./docs/scripts/deploy-docs.sh preview

# Staging (Docker container)
./docs/scripts/deploy-docs.sh staging

# Production (on production server only)
./docs/scripts/deploy-docs.sh production
```

## verify-deployment.sh

Comprehensive deployment verification:

```bash
# Verify staging
./docs/scripts/verify-deployment.sh http://localhost:8080

# Verify production
./docs/scripts/verify-deployment.sh https://pds.garazyk.xyz
```

Tests:
- Core page accessibility
- 404 handling
- Static asset loading
- HTTPS configuration
- Caching headers
- Security headers
- Search functionality
- Navigation
- Performance (page load time)

## test-redirects.sh

Test URL redirects and routing:

```bash
# Test local preview
./docs/scripts/test-redirects.sh http://localhost:4173

# Test staging
./docs/scripts/test-redirects.sh http://localhost:8080

# Test production
./docs/scripts/test-redirects.sh https://pds.garazyk.xyz
```

## Docker Configuration

### Dockerfile

Located at `docker/docs/Dockerfile`:
- Based on nginx:alpine
- Copies built documentation to `/var/www/docs/`
- Includes health check
- Exposes port 80

### docker-compose.yml

Located at `docker/docs/docker-compose.yml`:
- Service name: `september-docs`
- Container name: `september-docs`
- Port mapping: `8080:80`
- Volume mount: `docs/.vitepress/dist` → `/var/www/docs` (read-only)

### nginx.conf

Located at `docker/docs/nginx.conf`:
- Serves documentation at `/docs` path
- SPA routing with try_files fallback
- Aggressive caching for static assets (1 year)
- No-cache for HTML files
- Security headers (X-Frame-Options, X-Content-Type-Options, etc.)
- HTTPS configuration (for production)
- Custom 404 page

### Host nginx route for `/docs`

The docs container only exposes the site on `localhost:8080`. Public
`https://pds.garazyk.xyz/docs/` access also requires the host nginx reverse
proxy to forward `/docs` to that container.

Without this route, `/docs` falls through to the PDS backend and returns the
API server's JSON `404` response instead of the docs site.

Example host nginx snippet:

```nginx
location = /docs {
    return 301 /docs/;
}

location /docs/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Connection "";
}
```

## GitHub Actions CI/CD

### Workflow: build-docs.yml

Triggers:
- Push to main/develop (docs/** or source code changes)
- Pull requests
- Manual workflow dispatch

Jobs:

1. **build-docs**: Build VitePress documentation
   - Install Node.js dependencies
   - Run validation checks
   - Build VitePress site
   - Upload artifact

2. **deploy-docs**: Deploy to gh-pages (main branch only)
   - Download build artifact
   - Deploy to gh-pages branch

3. **preview-deployment**: Comment on PR with preview instructions
   - Download build artifact
   - Post comment with preview instructions

## Production Architecture

```

Internet
   ↓
exe.dev HTTPS (port 443)
   ↓
nginx reverse proxy (port 3000)
   ↓
Documentation container (port 80)
   ↓
/var/www/docs (VitePress static files)
```

## Deployment Checklist

### Pre-Deployment

- [ ] All validation checks pass (`npm run validate:all`)
- [ ] Build succeeds locally (`npm run docs:build`)
- [ ] Preview looks correct (`npm run docs:preview`)
- [ ] All tests pass
- [ ] Changes committed and pushed to main

### Staging Deployment

- [ ] Deploy to staging (`./docs/scripts/deploy-docs.sh staging`)
- [ ] Verify staging deployment (`./docs/scripts/verify-deployment.sh http://localhost:8080`)
- [ ] Test all major pages manually
- [ ] Test search functionality
- [ ] Test mobile responsiveness
- [ ] Test redirects (`./docs/scripts/test-redirects.sh http://localhost:8080`)

### Production Deployment

- [ ] SSH to production server
- [ ] Pull latest changes
- [ ] Build documentation
- [ ] Deploy with Docker Compose
- [ ] Verify host nginx forwards `/docs` to `127.0.0.1:8080`
- [ ] Verify production deployment (`./docs/scripts/verify-deployment.sh https://pds.garazyk.xyz`)
- [ ] Test critical pages manually
- [ ] Monitor for errors (check Docker logs)
- [ ] Verify HTTPS certificate
- [ ] Test from external network

### Post-Deployment

- [ ] Update URL mapping if needed
- [ ] Notify users of any URL changes
- [ ] Monitor analytics (if enabled)
- [ ] Check for 404 errors in logs
- [ ] Verify search index updated

## Troubleshooting

### Build Fails

```bash
# Clean and rebuild
cd docs
rm -rf node_modules .vitepress/dist .vitepress/cache
npm ci
npm run docs:build
```

## Docker Container Won't Start

```bash
# Check logs
docker compose logs september-docs

# Rebuild from scratch
docker compose down
docker compose build --no-cache
docker compose up -d
```

## 404 Errors After Deployment

1. Check nginx configuration is correct
2. Verify base URL in `.vitepress/config.ts` is `/docs`
3. Check file permissions in container
4. Verify try_files directive in nginx.conf

### Caching Issues

```bash
# Clear browser cache
# Or use incognito/private browsing

# Verify cache headers
curl -I https://pds.garazyk.xyz/docs/

# Force reload in browser: Cmd+Shift+R (Mac) or Ctrl+Shift+R (Windows/Linux)
```

## Search Not Working

1. Verify search index built during build
2. Check browser console for errors
3. Verify MiniSearch configuration in `.vitepress/config.ts`
4. Rebuild documentation

## Rollback Procedure

If deployment fails or causes issues:

```bash
# On production server
cd /home/exedev/objpds/docker/docs

# Stop current deployment
docker compose down

# Checkout previous version
cd /home/exedev/objpds
git log --oneline  # Find previous commit
git checkout <previous-commit-hash>

# Rebuild and deploy
cd docs
npm ci
npm run docs:build
cd ../docker/docs
docker compose up -d --build

# Verify rollback
curl -I https://pds.garazyk.xyz/docs/
```

## Monitoring

### Health Check

```bash
# Docker health check (automatic)
docker ps  # Check STATUS column for "healthy"

# Manual health check
curl -f http://localhost:8080/docs/ || echo "Health check failed"
```

## Logs

```bash
# View Docker logs
docker compose logs -f september-docs

# View nginx access logs
docker exec september-docs tail -f /var/log/nginx/access.log

# View nginx error logs
docker exec september-docs tail -f /var/log/nginx/error.log
```

## Security Considerations

1. **HTTPS Only**: Production must use HTTPS (handled by exe.dev reverse proxy)
2. **Security Headers**: nginx.conf includes security headers
3. **No Secrets**: Documentation is public, no secrets in content
4. **Read-Only Mount**: Docker volume mounted read-only
5. **Minimal Container**: Alpine-based nginx image for small attack surface

## Performance Optimization

1. **Asset Caching**: Static assets cached for 1 year
2. **Gzip Compression**: Enabled in nginx.conf
3. **Code Splitting**: VitePress automatically splits code
4. **Lazy Loading**: Images and diagrams lazy loaded
5. **Prefetching**: VitePress prefetches linked pages

## Support

For issues or questions:
- Check troubleshooting section above
- Review GitHub Actions logs
- Check Docker logs
- File issue on GitHub repository

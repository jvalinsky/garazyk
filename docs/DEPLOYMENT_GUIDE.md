---
title: Documentation Deployment Guide
---

# Documentation Deployment Guide

This guide covers building and deploying the Garazyk VitePress documentation.

## Prerequisites

- Node.js 20+
- Docker and Docker Compose (for containerized deployment)
- Production server access (`DEPLOY_HOST`)
- Local dependencies: `cd docs && npm ci`

## Environments

### 1. Local Preview
Test changes locally before pushing:
```bash
cd docs
npm run docs:build
npm run docs:preview
```
Site available at: `http://localhost:4173/docs`

### 2. Staging (Docker)
Deploy to a local Docker container for verification:
```bash
./docs/scripts/deploy-docs.sh staging
./docs/scripts/verify-deployment.sh http://localhost:8080
```
Site available at: `http://localhost:8080/docs`

### 3. Production (pds.garazyk.xyz)
Production deployment occurs on the `DEPLOY_HOST` server.

```bash
ssh DEPLOY_USER@DEPLOY_HOST
cd DEPLOY_DIR/objpds
git pull origin main

cd docs
npm ci
npm run docs:build

cd ../docker/docs
docker compose down
docker compose up -d --build
```

## Verification

Use the `verify-deployment.sh` script to validate health after any deployment:
```bash
./docs/scripts/verify-deployment.sh https://pds.garazyk.xyz
```

Checks include:
- Page accessibility and 404 handling.
- Asset loading and search functionality.
- Security headers and caching configuration.
- Performance metrics.

## Docker Infrastructure

The documentation is served by Nginx in a minimal Alpine-based container.

- **Dockerfile:** `docker/docs/Dockerfile`
- **Compose:** `docker/docs/docker-compose.yml` (Maps port 8080 to 80)
- **Nginx Config:** `docker/docs/nginx.conf` (Handles SPA routing and caching)

### Host Reverse Proxy
The production Nginx must forward `/docs` traffic to the documentation container:

```nginx
location /docs/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

## Troubleshooting

### Build Failures
Clear the VitePress cache and re-run the build:
```bash
cd docs
rm -rf .vitepress/dist .vitepress/cache
npm run docs:build
```

### Routing Issues (404s)
1. Verify the `base` URL in `.vitepress/config.ts` is set to `/docs/`.
2. Check the Nginx `try_files` directive in the container's `nginx.conf`.

## Related

- [Monitoring Guide](MONITORING)
- [Maintenance Guide](MAINTENANCE)
- [Deployment Summary](DEPLOYMENT_SUMMARY)

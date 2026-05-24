---
name: garazyk-skylab
description: "Fresh/Preact web portal for Skylab. Covers routes, backend service integrations, Docker image creation, and standard development commands."
---

# Garazyk Skylab — Web Portal

Skylab is a standalone Fresh/Preact-based operator web portal designed to manage AT Protocol resources, view system metrics, and coordinate telemetry. It is compiled and deployed inside isolated Docker containers.

## When to Use

- Maintain or extend the Skylab visual web interface
- Modify routes, Preact islands, or custom components under `skylab/`
- Audit and extend backend service connections in `services/`
- Configure or troubleshoot Skylab Docker container setup (`Dockerfile`)

## Architecture Overview

Location: `skylab/`

```
routes/          — File-system based router (dashboard, settings, telemetry pages)
services/        — Integration client calls for PDS, PLC, and AppView services
static/          — Frontend styles, assets, and icons
Dockerfile       — Production-ready container multi-stage build recipe
deno.json        — Local configuration, workspace imports, and Deno task shortcuts
dev.ts           — Development server entry point
fresh.gen.ts     — Automatically generated Fresh route registry
main.ts          — Production entry point serving the Fresh application
```

## Quick Start (Development)

Run Skylab commands within the `skylab/` directory:

```bash
# Start local development server with live reload
cd skylab && deno task dev

# Compile assets and build production pack
cd skylab && deno task build

# Start production server locally
cd skylab && deno task start

# Preview build locally
cd skylab && deno task preview
```

## Docker Integration & Deployment

Skylab is packaged into an optimized, distroless Docker image using its localized `Dockerfile`.

```dockerfile
# Multi-stage build compilation
FROM denoland/deno:alpine AS builder
WORKDIR /app
COPY . .
RUN deno task build

# Final lightweight distribution
FROM denoland/deno:bin AS runner
WORKDIR /app
COPY --from=builder /app .
EXPOSE 8000
CMD ["run", "-A", "main.ts"]
```

Build the container image:
```bash
docker build -t garazyk-skylab:latest ./skylab
```

## Related Skills

- **garazyk-admin-ui** — Shared visual styling patterns and HTMX conventions
- **garazyk-laweta** — Docker container orchestration used to deploy Skylab
- **garazyk-schemat** — Allocates ports and resolves hostnames for Skylab
- **web-ui-audit** — Accessibility and secure cookie practices for operator dashboards

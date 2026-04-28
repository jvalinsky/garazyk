---
title: "Tutorial 13: Admin UI Internals & Instrumentation"
---

# Tutorial 13: Admin UI Internals & Instrumentation

## Overview

The Garazyk Admin UI runs as `garazyk-ui`, a standalone Objective-C service that renders operator workflows and calls the backing PDS, PLC, Relay, AppView, and Chat APIs.

**Learning Objectives:**
- Understand the UI session flow through `/admin/login`.
- Trace how `UIBackendClient` calls admin and service endpoints.
- Map Admin UI features to `com.atproto.admin.*` XRPC methods.
- Analyze how the PDS collects and exposes server-wide instrumentation.

**Estimated Time:** 45-55 minutes

## Prerequisites

- Complete [Tutorial 7b: Admin UI Architecture](./tutorial-7b-admin-ui).
- Familiarity with Objective-C protocols and services.
- `deciduous` CLI tool installed.

---

## Step 1: Track the Goal with Deciduous

Record your intent to study the management and monitoring layer:

```bash
deciduous add goal "Audit Admin Internals and Metrics" -c 95
# Track your analysis
deciduous add action "Traced admin login to token issuance" -c 90
```

---

## Step 2: Administrative Authentication

Access to the Admin UI is protected by `GARAZYK_UI_ADMIN_PASSWORD`. Backend admin calls still depend on the tokens configured for each service.

### The `/admin/login` Flow
Unlike user sessions, UI access uses a local service session:
1. The client sends `POST /admin/login` to `garazyk-ui`.
2. `UIAuthManager` validates the password against `GARAZYK_UI_ADMIN_PASSWORD`.
3. The UI service sets a `ui_admin_token` cookie. It also accepts the same token as a bearer token for API-style requests.

The UI session only gates access to `garazyk-ui`. Calls from the UI service to the PDS or other backends use the configured `GARAZYK_UI_PDS_TOKEN`, `GARAZYK_UI_PLC_TOKEN`, `GARAZYK_UI_RELAY_TOKEN`, `GARAZYK_UI_APPVIEW_TOKEN`, and `GARAZYK_UI_CHAT_TOKEN` values when those services require bearer auth.

---

## Step 3: The `UIBackendClient` Bridge

`UIBackendClient` is the Admin UI service bridge. It builds backend URLs from `UIServiceConfig`, attaches bearer tokens when present, and normalizes failures into dashboard-friendly response dictionaries.

### Core Responsibilities
- Account search, invite management, sessions, and app-password operations through PDS admin XRPC.
- PLC status, DID lookup, and log export.
- Relay crawl, upstream, and health checks.
- AppView ingest, backfill, and metrics views.
- Ozone and Chat moderation workflows.

---

## Step 4: Instrumentation and Metrics

Garazyk provides real-time visibility into its performance and health.

### Server Statistics
The `com.atproto.admin.getServerStats` method aggregates data from across the system:
- Total account counts.
- Active session counts.
- Disk usage (via the `data/` directory).
- Database health status.

### Prometheus Metrics
For external monitoring, the PDS exposes a raw metrics endpoint at `/_metrics`. This is where `PLCMetrics`, `RelayMetrics`, and `HttpServer` stats are exported in a standard format.

**Technical Detail:**
Check `PLCMetrics.m` to see how it increments counters for requests, errors, and database operations.

---

## Step 5: Verification and Debugging

### Perform an Admin Login (CLI)
You can verify the UI login endpoint with `curl`:

```bash
GARAZYK_UI_ADMIN_PASSWORD=dev-admin ./build/bin/garazyk-ui serve

curl -i -sS -X POST http://127.0.0.1:2590/admin/login \
  -H "Content-Type: application/json" \
  -d '{"password":"dev-admin"}'
```

### Query Server Stats
Use the PDS admin bearer token to query the server's internal state:

```bash
# Query server stats
curl -sS http://127.0.0.1:2583/xrpc/com.atproto.admin.getServerStats \
  -H "Authorization: Bearer <your-admin-token>" | jq .
```

### Inspect the Audit Log
Verify that your actions are being recorded:

```bash
# Query the admin audit log
curl -sS http://127.0.0.1:2583/xrpc/com.atproto.admin.queryAuditLog \
  -H "Authorization: Bearer <your-admin-token>" | jq .
```

---

## Troubleshooting

| Failure Mode | Symptom | Mitigation |
| --- | --- | --- |
| **Invalid UI Session** | Status 401 on `garazyk-ui` routes. | Re-run `/admin/login` or check `GARAZYK_UI_ADMIN_PASSWORD`. |
| **Backend Auth Failure** | UI loads, but a panel shows backend errors. | Check the relevant `GARAZYK_UI_*_TOKEN` and `GARAZYK_UI_*_URL` values. |
| **Takedown Bypass** | User can still post after takedown. | Check if the `PDSRecordService` correctly queries `isAccountTakedownActive:` before writes. |
| **Audit Log Overflow** | Slow database queries on large logs. | Implement log rotation or pruning for the `admin_audit_log` table. |
| **Metrics Latency** | `/_metrics` takes too long to respond. | Ensure metrics collection doesn't perform blocking database reads on every request. |

## Next Steps

1. Move to [Tutorial 14: Advanced Firehose (Filtering & Backfill)](./tutorial-14-advanced-firehose).
2. Review [Admin UI Documentation](../11-reference/admin-ui-documentation) for component maps.
3. Check [Performance Monitoring](../11-reference/performance-monitoring) for deeper observability.

## Summary

The Admin UI combines a local UI session, backend bearer-token configuration, and service-specific admin endpoints. When you change an operator workflow, trace all three pieces before assuming the bug lives in the HTML.

Always use `deciduous` to document changes to the admin surface or new instrumentation hooks.

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

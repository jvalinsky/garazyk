---
title: "Tutorial 13: Admin UI Internals"
---

# Tutorial 13: Admin UI Internals

The Admin UI (`garazyk-ui`) is a standalone service that provides operator workflows by calling the admin and service endpoints of the PDS, PLC, and other infrastructure components.

## Administrative Authentication

Access to the Admin UI is gated by the `GARAZYK_UI_ADMIN_PASSWORD` environment variable.

### Login Flow
1. The client sends `POST /admin/login` with the password.
2. `UIAuthManager` validates the password.
3. The UI service sets a `ui_admin_token` cookie for subsequent session-gated requests.

Communication between the UI service and the PDS backends uses the configured service tokens (e.g., `GARAZYK_UI_PDS_TOKEN`).

## The `UIBackendClient` Bridge

`UIBackendClient` acts as the bridge between the UI and the various service APIs. It normalizes responses from different backends into a consistent format for the dashboard.

### Core Responsibilities
- **Account Management:** Search, invites, and session overrides via PDS admin XRPC.
- **Identity:** PLC status, DID lookups, and audit log exports.
- **Federation:** Relay health, crawl status, and upstream monitoring.
- **AppView:** Ingest status and specialized indexing views.
- **Moderation:** Takedown and content review workflows.

## Instrumentation and Metrics

Garazyk exposes its internal state through two primary mechanisms:

### Server Statistics
The `com.atproto.admin.getServerStats` method aggregates system-wide data, including account totals, active sessions, and disk usage.

### Prometheus Metrics
The PDS exports raw metrics at `/_metrics`. Components like `PLCMetrics` and `RelayMetrics` use this endpoint to provide real-time performance data to external monitoring systems.

## Verification

### Test Admin Login
Verify the UI login endpoint manually:
```bash
curl -i -X POST http://127.0.0.1:2590/admin/login \
  -H "Content-Type: application/json" \
  -d '{"password":"your-admin-password"}'
```

### Query Server Stats
Use the PDS admin token to inspect the server state directly:
```bash
curl -sS http://127.0.0.1:2583/xrpc/com.atproto.admin.getServerStats \
  -H "Authorization: Bearer <admin-token>" | jq .
```

## Troubleshooting

| Symptom | Cause | Resolution |
| --- | --- | --- |
| 401 Unauthorized (UI) | Password mismatch | Verify `GARAZYK_UI_ADMIN_PASSWORD`. |
| 401 Unauthorized (Backend) | Token mismatch | Check service-specific tokens like `GARAZYK_UI_PDS_TOKEN`. |
| Stale Metrics | Blocking reads | Ensure metrics collection is not performing expensive database queries. |
| Audit Log Latency | Large log table | Consider log rotation or pruning for the `admin_audit_log` table. |

## See Also

- [Admin UI Documentation](../11-reference/admin-ui-documentation)
- [Performance Monitoring](../11-reference/performance-monitoring)
- [Tutorial 8: Endpoint Workflow](./tutorial-8-endpoint-workflow)

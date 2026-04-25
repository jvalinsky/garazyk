---
title: "Tutorial 13: Admin UI Internals & Instrumentation"
---

# Tutorial 13: Admin UI Internals & Instrumentation

## Overview

The Garazyk Admin UI is more than just a dashboard; it is a window into the PDS's operational state. This tutorial explains how the Objective-J frontend communicates with the backend Admin services to manage accounts, monitor health, and audit actions.

**Learning Objectives:**
- Understand the administrative authentication flow via `/admin/login`.
- Explore the `PDSAdminController` and its role as a service bridge.
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

Access to the Admin UI and the `com.atproto.admin` namespace is protected by a dedicated administrative password.

### The `/admin/login` Flow
Unlike user sessions, admin access uses a specialized endpoint.
1.  **Request**: The client sends a `POST /admin/login` with the admin password.
2.  **Validation**: The PDS validates the password against the `PDS_ADMIN_PASSWORD` environment variable.
3.  **Token**: If successful, the server issues a **Bearer Token**. This token must be included in the `Authorization` header for all subsequent admin requests.

---

## Step 3: The `PDSAdminController` Bridge

The `PDSAdminController` is the central entry point for all administrative logic. It follows the "Thin Controller" pattern, delegating actual work to the `PDSAdminService`.

### Core Responsibilities
- **Account Takedowns**: Managing the `admin_takedowns` table to block malicious actors.
- **Invite Management**: Enabling/disabling invite codes for specific accounts.
- **Diagnostic Jobs**: Triggering background tasks like **Blob Audits** (checking CID consistency) or **Repository Repairs**.
- **Audit Logging**: Every action taken by an admin is recorded in the `admin_audit_log` table via `logAdminAction:subjectType:subjectId:details:ipAddress:adminDid:error:`.

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
You can manually obtain an admin token using `curl`:

```bash
# Obtain the admin token
curl -sS -X POST http://127.0.0.1:2583/admin/login \
  -H "Content-Type: application/json" \
  -d '{"password":"your-admin-password"}' | jq .token
```

### Query Server Stats
Use your admin token to query the server's internal state:

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

## Failure Modes to Watch For

| Failure Mode | Symptom | Mitigation |
| --- | --- | --- |
| **Invalid Admin Token** | Status 401 (Unauthorized) on admin routes. | Re-run `/admin/login` or check if `PDS_ADMIN_PASSWORD` was changed. |
| **Takedown Bypass** | User can still post after takedown. | Check if the `PDSRecordService` correctly queries `isAccountTakedownActive:` before writes. |
| **Audit Log Overflow** | Slow database queries on large logs. | Implement log rotation or pruning for the `admin_audit_log` table. |
| **Metrics Latency** | `/_metrics` takes too long to respond. | Ensure metrics collection doesn't perform blocking database reads on every request. |

---

## Summary

The Admin UI and its backend internals provide the "control tower" for your PDS. By understanding the authentication, service bridging, and instrumentation layers, you can build tools that make Garazyk easier to operate at scale.

Always use `deciduous` to document changes to the admin surface or new instrumentation hooks.

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

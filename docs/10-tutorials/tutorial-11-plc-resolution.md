---
title: "Tutorial 11: PLC Failover and Resolution"
---

# Tutorial 11: PLC Failover and Resolution

## Overview

Identity in the AT Protocol is grounded in DIDs (Decentralized Identifiers). Most users use `did:plc`, which relies on a PLC (Placeholder) directory to map their identity to a rotation key and a PDS endpoint. This tutorial explains how Garazyk resolves these identities and maintains availability through failover mechanisms.

**Learning Objectives:**
- Trace a DID resolution request from the PDS to a PLC directory.
- Understand the retry and timeout policies in `DIDPLCResolver.m`.
- Explore the internal implementation of a PLC directory in `PLCServer.m`.
- Configure and verify PLC failover scenarios.

**Estimated Time:** 35-45 minutes

## Prerequisites

- Complete [Tutorial 1: Hello PDS](./tutorial-1-hello-pds).
- Familiarity with JSON-LD and DID documents.
- `deciduous` CLI tool installed.

---

## Step 1: Track the Goal with Deciduous

Record your intent to study the identity resolution layer:

```bash
deciduous add goal "Audit PLC Resolution and Failover" -c 95
# Track your analysis
deciduous add action "Traced DID resolution retry logic" -c 90
```

---

## Step 2: The DID Resolution Path

When the PDS needs to verify a signature or find another user's server, it must resolve their DID. For `did:plc`, this means making an HTTP request to a PLC directory.

### `DIDPLCResolver.m`
The `DIDPLCResolver` is the core component for this task. It:
1.  **Validates** the DID format.
2.  **Checks a local cache** (to avoid redundant network calls).
3.  **Executes an HTTP GET** to `<plc_url>/<did>`.

**Technical Detail:**
Look at `executeRequest:attempt:transform:completion:` in `Garazyk/Sources/PLC/DIDPLCResolver.m`. It uses an `HttpRetryPolicy` to handle transient network errors. If the primary PLC directory is slow or returns a 5xx error, the resolver will retry based on the configured policy.

---

## Step 3: Hosting a PLC Directory

Garazyk is not just a PDS; it also contains a complete implementation of a PLC directory.

### `PLCServer.m`
The `PLCServer` manages a history of operations for each DID.
- **Operations**: Clients submit `plc_operation` (to update keys/services) or `plc_tombstone` (to delete an identity).
- **Validation**: Every incoming operation is strictly validated for size, signature, and structure (`PLCValidateIncomingOperation`).
- **Audit Log**: The server maintains a full audit log (`/log/audit`), allowing anyone to verify the history of an identity.

---

## Step 4: Configuring Failover

In a production environment, relying on a single PLC directory is a risk. Garazyk allows you to configure primary and fallback PLC URLs.

### Failover Logic
While the `DIDPLCResolver` itself targets a single URL, the higher-level `PDSPLCClient` (or equivalent service coordinator) can be configured with multiple resolvers.
- **Primary**: The main directory (e.g., `https://plc.directory`).
- **Fallback**: A local replica or a secondary community directory.

If the primary resolver returns a terminal network error, the system switches to the fallback to ensure identity resolution continues.

---

## Step 5: Verification and Monitoring

### Manual DID Resolution
You can simulate the resolver's work using `curl`:

```bash
# Resolve a known DID from the official directory
curl -sS https://plc.directory/did:plc:l37j664qzpjk3hlh4mbuvbmh | jq .
```

### Check PLC Server Health
If you are running a local PLC replica:

```bash
curl -sS http://127.0.0.1:2582/_health | jq .
```

### Inspect Metrics
Garazyk's PLC implementation exports Prometheus-compatible metrics:

```bash
curl -sS http://127.0.0.1:2582/_metrics
```

---

## Troubleshooting

| Failure Mode | Symptom | Mitigation |
| --- | --- | --- |
| **PLC Timeout** | `Synchronous DID resolution timed out`. | Increase the `timeout` in `DIDPLCResolver` or check PLC server latency. |
| **Invalid Signature** | `Audit failed: Invalid signature`. | The submitted operation was not signed by a valid rotation key. |
| **Tombstoned DID** | Status 410 (Gone). | The identity has been permanently deleted from the PLC directory. |
| **Cache Staleness** | Stale DID document. | The `DIDPLCResolver` cache might need a lower TTL or manual invalidation during updates. |

## Next Steps

1. Move to [Tutorial 12: Federation & Sync](./tutorial-12-federation-sync).
2. Review [PLC Failover](../11-reference/plc-failover) for production topology advice.
3. Check [PLC Server Operations](../11-reference/plc-server-operations) for admin commands.

## Summary

Identity resolution enables AT Protocol interoperability. `DIDPLCResolver` retry policies and `PLCServer` keep your PDS connected to the network during outages.

Use `deciduous` to document changes to identity resolution or PLC configuration.

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

---
title: "Tutorial 11: PLC Failover and Resolution"
---

# Tutorial 11: PLC Failover and Resolution

Identity in the AT Protocol is grounded in DIDs (Decentralized Identifiers). Most users rely on `did:plc`, which uses a PLC (Placeholder) directory to map their identity to a rotation key and a PDS endpoint.

## The DID Resolution Path

When the PDS needs to verify a signature or locate another user's server, it must resolve their DID. For `did:plc`, this involves querying a PLC directory.

### `DIDPLCResolver.m`
The resolver handles the network-level details:
1. **Validation:** Ensures the DID format is correct.
2. **Caching:** Checks a local cache to avoid redundant network calls.
3. **Execution:** Performs an HTTP GET to `<plc_url>/<did>`.

The resolver uses an `HttpRetryPolicy` to handle transient network errors. If the primary PLC directory is unavailable, the system can be configured to retry or fail over to a secondary directory.

## Hosting a PLC Directory

Garazyk includes a full implementation of a PLC directory in `PLCServer.m`.

### Operations and Audit Logs
- **Operations:** Clients submit `plc_operation` (to update keys or services) or `plc_tombstone` (to delete an identity).
- **Validation:** Every operation is validated for structure and signature.
- **Audit Log:** The server maintains a verifiable history of all identity operations at `/log/audit`.

## Failover Configuration

In production, relying on a single PLC directory is a single point of failure. Garazyk supports primary and fallback PLC URLs.

### Failover Logic
The `PDSPLCClient` manages multiple resolvers:
- **Primary:** The main network directory (e.g., `https://plc.directory`).
- **Fallback:** A local replica or secondary community directory.

If the primary resolver returns a terminal network error, the system switches to the fallback to ensure identity resolution remains available.

## Verification

### Manual Resolution
Test resolution using `curl`:
```bash
curl -sS https://plc.directory/did:plc:l37j664qzpjk3hlh4mbuvbmh | jq .
```

### Health and Metrics
If running a local PLC server, check its health and performance:
```bash
curl -sS http://127.0.0.1:2582/_health
curl -sS http://127.0.0.1:2582/_metrics
```

## Troubleshooting

| Symptom | Cause | Resolution |
| --- | --- | --- |
| Resolution Timeout | High latency or server down | Increase the resolver timeout or check PLC server health. |
| Invalid Signature | Auth failure | The operation was not signed by a valid rotation key. |
| 410 Gone | Tombstoned DID | The identity has been permanently deleted from the directory. |
| Stale Data | Cache staleness | Lower the TTL or manually invalidate the resolver cache. |

## See Also

- [PLC Failover Reference](../11-reference/plc-failover)
- [PLC Server Operations](../11-reference/plc-server-operations)
- [Tutorial 1: Hello PDS](./tutorial-1-hello-pds)

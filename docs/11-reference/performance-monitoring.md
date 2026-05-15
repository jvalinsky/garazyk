---
title: Performance Monitoring
---

# Performance Monitoring

Performance analysis in Garazyk relies on exported runtime signals. Profiling the entire system is inefficient for debugging regressions. Use this sequence to investigate slowdowns:

1. Identify the slow surface.
2. Read metrics for that surface.
3. Check logs for the owning component.
4. Inspect the service or database path that the endpoint calls.

## Monitoring Surfaces

The PDS and PLC server expose operational signals through distinct endpoints.

| Surface | Description |
| --- | --- |
| `/metrics` | Prometheus counters for HTTP, blobs, repos, auth, firehose, and rate limiting. |
| `/admin/metrics` | Authenticated controller metrics. |
| `/admin/health` | Authenticated health summary from `PDSHealthCheck`. |
| `PLC GET /_health` | PLC server health status. |
| `PLC GET /_metrics` | PLC-specific operational metrics. |

## PDS Metrics

The implementation tracks primary operational signals:

- Request counts by method, endpoint, and status.
- Request latency histograms.
- Active connection counts.
- Repository and commit counts.
- Blob counts and storage volume.
- Database size and connection pool state.
- Firehose subscriber count, event counts, and sequence.
- Rate-limit rejection counts.
- Auth failure reasons and session counts.

These signals typically locate regressions without requiring external profiling tools.

## Metric Sources

The runtime path updates metrics directly:

- **HTTP Server**: Request counts, statuses, latency, and active connections.
- **Rate Limiter**: Rejected request counts.
- **Auth**: Failure reasons and session counts.
- **Sync**: Firehose and repository commit metrics via `subscribeRepos`.

Check `/metrics` first to observe actual process behavior.

## Storage and Database Pressure

Performance issues often manifest as storage pressure before request failures occur. Monitor these metrics together:

- Request latency for the affected endpoint.
- `pds_database_size_bytes`
- Blob count and storage bytes.
- Controller-backed database pool metrics from `/admin/metrics`.

Correlation distinguishes route-local issues from global capacity or database-bound pressure.

## Correlating Logs and Metrics

Metrics identify that a slowdown exists. Logs identify the responsible component. Use the [Logging Strategy](./logging-strategy) to interpret latency spikes. Narrow `Database`, `Service`, `Sync`, or `Blob` component logs to the failing path.

## Debugging Workflow

1. Locate the slow endpoint or workflow.
2. Inspect matching request and latency metrics.
3. Check for correlated auth, rate-limit, or storage metrics.
4. Narrow component logging if the owner remains unclear.
5. Review service code before employing external profiling.

## Related Resources

- [Metrics Collection](./metrics-collection)
- [Logging Strategy](./logging-strategy)
- [Troubleshooting](./troubleshooting)
- [Services Overview](../03-application-layer/services-overview)
- [Documentation Map](documentation-map.md)

## Appendix: Runtime Checks

```bash
# PDS metrics
curl -sS http://127.0.0.1:2583/metrics | grep '^pds_'

# PLC metrics
curl -sS http://127.0.0.1:2582/_metrics | head
```

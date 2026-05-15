---
title: Metrics Collection
---

# Metrics Collection

Garazyk exports Prometheus-style metrics to track server health and performance.

## Metrics Model

The `PDSMetrics` singleton collects counters, gauges, and histograms from across the runtime. This unified model allows correlation between subsystem events, such as request latency and database pool usage.

## Metric Families

- **HTTP:** Request totals by method, endpoint, and status code.
- **Repository:** Commit counts and total record counts.
- **Storage:** Blob counts and total bytes stored.
- **Database:** SQLite database sizes and active connection counts.
- **Auth:** Authentication failure reasons and active session counts.
- **Sync:** Firehose subscriber counts and event sequences.

## Export Surfaces

| Service | Endpoint | Purpose |
| --- | --- | --- |
| PDS | `/metrics` | Public and operational metrics. |
| PDS | `/admin/metrics` | Authenticated controller-backed metrics. |
| PLC | `/_metrics` | Identity directory metrics. |

## Querying Metrics

Use `curl` to inspect the raw Prometheus output:

```bash
# Check auth failures
curl -sS http://127.0.0.1:2583/metrics | grep '^pds_auth_failures_total'

# Check request latency
curl -sS http://127.0.0.1:2583/metrics | grep '^pds_request_latency_seconds'
```

## Related

- [Performance Monitoring](./performance-monitoring)
- [Logging Strategy](./logging-strategy)
- [Explorer, OpenAPI & UI](./explorer-openapi-ui)
- [Documentation Map](./documentation-map)


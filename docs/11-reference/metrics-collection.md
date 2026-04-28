---
title: Metrics Collection
---

# Metrics Collection

## Overview

Garazyk collects Prometheus-style metrics across its request path. This page describes the metrics model and how to interpret the available data.

## Metrics Model

`PDSMetrics` is a singleton that collects counters, gauges, and latency histograms. This common model helps debug requests that cross subsystem boundaries (e.g., an endpoint touching auth, rate limiting, and storage).

## Metric Families

The PDS exports metrics for:

- HTTP request totals by method and status.
- Per-endpoint request totals and latency.
- Repository and blob counts/sizes.
- Database size.
- Active connections.
- Firehose subscribers, events, and sequence numbers.
- Rate-limit rejections and auth failures.
- OAuth grants and active sessions.

## Update Points

The metrics system is integrated directly into the runtime:

- `HttpServer`: request counts, status, latency, and connections.
- `RateLimiter`: rejection types.
- `AuthVerifier`: auth failure reasons.
- `OAuth2`: grants and session activity.
- `SubscribeReposHandler`: firehose and repository commit activity.

## Export Surfaces

- PDS: `GET /metrics` and `GET /admin/metrics`.
- PLC: `GET /_metrics`.

PDS metrics explain application behavior, while PLC metrics explain DID directory behavior.

## Interpretation Guidelines

- Latency requires endpoint context to be actionable.
- Read blob growth alongside request rates.
- Group auth failures by reason before drawing conclusions.
- Pair firehose metrics with sync or relay activity.

## Limitations

Metrics provide the first diagnostic surface but do not replace:
- Detailed logs for failure context.
- Code analysis for control flow truth.
- Manual verification of UI behavior.

## Related Reading

- [Performance Monitoring](./performance-monitoring)
- [Logging Strategy](./logging-strategy)
- [Explorer, OpenAPI & UI](./explorer-openapi-ui)

## Appendix

### Minimal scrape checks

```bash
curl -sS http://127.0.0.1:2583/metrics | rg '^pds_auth_failures_total'
```

```bash
curl -sS http://127.0.0.1:2583/metrics | rg '^pds_request_latency_seconds'
```

## Related

- [Documentation Map](documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)


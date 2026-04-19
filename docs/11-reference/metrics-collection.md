---
title: Metrics Collection
---

# Metrics Collection

## Overview

Metrics collection in Garazyk is implemented, integrated, and worth trusting.
Older versions of this page treated metrics as partial scaffolding. That is no
longer an accurate description of the tree.

The main contributor question is: which metrics are already part of the request
path, and how should you interpret them?

## The Metrics Model

`PDSMetrics` is a singleton that collects Prometheus-style counters, gauges, and
latency histograms. It is designed to answer operational questions without
forcing every subsystem to invent its own export format.

That common model matters because request debugging almost always crosses
subsystem boundaries. A single endpoint can touch auth, rate limiting, storage,
and sync behavior in one request.

## PDS Metric Families

The current PDS metrics surface includes:

- HTTP request totals by method
- HTTP response totals by status
- per-endpoint request totals
- request latency histograms
- repository count
- blob count
- blob storage bytes
- database size bytes
- active connections
- repository commit totals
- firehose subscriber, event, and sequence metrics
- rate-limit rejection metrics
- auth failure metrics
- OAuth grant and active session metrics

This is already enough to support alerting, dashboards, and targeted debugging.

## Where The Counters Are Updated

The most important fact about the metrics system is that it is wired into the
runtime:

- `HttpServer` records request counts, statuses, latency, and active
  connections
- `RateLimiter` records rejection types
- `AuthVerifier` records auth failure reasons
- `OAuth2` records grant and session activity
- `SubscribeReposHandler` records firehose and repository commit activity

That integration is what separates a useful metrics system from a decorative
one.

## Export Surfaces

The PDS exports metrics at:

- `GET /metrics`
- `GET /admin/metrics` for the authenticated admin view

The standalone PLC server exports its own metrics at:

- `GET /_metrics`

Do not merge those mentally. PDS metrics explain application behavior. PLC
metrics explain DID directory behavior.

## Reading The Numbers Correctly

Some guidelines matter more than the raw metric names:

- latency without endpoint context is rarely actionable
- blob growth is more meaningful when read alongside request rates
- auth failures should be grouped by reason before drawing conclusions
- firehose metrics matter most when paired with sync or relay work

The "why" here is simple: almost every metric family becomes misleading if you
read it in isolation.

## What Metrics Do Not Replace

Metrics do not replace:

- component logs for detailed failure context
- service and repository code as the source of control flow truth
- targeted manual verification of explorer or browser UI behavior

They are the first diagnostic surface, not the only one.

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
```\n\n## Related\n\n- [Documentation Map](documentation-map.md)\n- [Contributor Guide](../index.md)\n- [Repository Documentation Index](../repo-index/index.md)\n\n
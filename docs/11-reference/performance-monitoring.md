---
title: Performance Monitoring
---

# Performance Monitoring

## Overview

Performance work in Garazyk starts with the runtime signals the server already
exports. This codebase has enough moving parts that
"profile everything" is usually the slowest way to debug a regression.

The useful order is:

1. identify the slow surface
2. read the metrics for that surface
3. check logs for the owning component
4. inspect the service or database path that the endpoint calls

## The Main Monitoring Surfaces

The PDS exposes three practical monitoring surfaces:

| Surface | Why it matters |
| --- | --- |
| `/metrics` | Prometheus-style counters and gauges for HTTP, blobs, repos, auth, firehose, and rate limiting |
| `/admin/metrics` | authenticated operational view backed by controller metrics |
| `/admin/health` | authenticated health summary backed by `PDSHealthCheck` |

The PLC server has its own operational surfaces:

- `GET /_health`
- `GET /_metrics`

Treat the PDS and PLC metrics as related but separate systems. They answer
different operational questions.

## What The PDS Already Measures

The current metrics implementation covers the signals contributors usually need
first:

- request count by method, endpoint, and status
- request latency histogram
- active connection count
- repository count and commit count
- blob count and blob storage bytes
- database size
- firehose subscriber count, event counts, and sequence
- rate-limit rejection counts
- auth failure reasons
- OAuth grant counts and active auth sessions

That is enough to locate most regressions before you need a profiler.

## Where Those Signals Come From

The metrics are not theoretical. They are updated in the runtime path:

- the HTTP server records request counts, statuses, latency, and active
  connections
- the rate limiter records rejected requests
- auth verification records failure reasons
- OAuth flows record grant and session metrics
- subscribeRepos updates firehose and repository commit metrics

That integration is why `/metrics` should be your first stop. It describes the
behavior the running process is actually executing.

## Database And Storage Pressure

Performance problems in this codebase often become visible as storage pressure
before they become visible as request failures.

Watch these together:

- request latency for the affected endpoint
- `pds_database_size_bytes`
- blob count and blob storage bytes
- controller-backed database pool metrics from `/admin/metrics`

This combination usually tells you whether the problem is route-local,
database-bound, or global capacity pressure.

## Logging Complements Metrics

Metrics tell you that something is slow. Logs tell you which component is
responsible.

Use [Logging Strategy](./logging-strategy) alongside this page. A latency spike
on a repository endpoint is much easier to interpret when the `Database`,
`Service`, `Sync`, or `Blob` component logs are narrowed to the failing path.

## A Practical Debugging Loop

When performance degrades, use this loop:

1. find the endpoint or workflow that feels slow
2. inspect the matching request and latency metrics
3. look for correlated auth, rate-limit, blob, or firehose metrics
4. enable or narrow component logging if the owner is still unclear
5. read the owning service code before reaching for external profiling tools

This order keeps debugging grounded in the architecture the application already
has.

## What This Page Does Not Promise

Garazyk does not currently ship a full tracing stack or a built-in distributed
performance analysis system. The observability model today is metrics plus
component logs plus targeted code inspection.

That is a limitation, but it is also an honest one. The docs should not imply a
more elaborate monitoring platform than the repository provides.

## Related Reading

- [Metrics Collection](./metrics-collection)
- [Logging Strategy](./logging-strategy)
- [Troubleshooting](./troubleshooting)
- [Services Overview](../03-application-layer/services-overview)

## Appendix

### Minimal runtime checks

```bash
curl -sS http://127.0.0.1:2583/metrics | rg '^pds_(http|blob|repo|firehose)'
```

```bash
curl -sS http://127.0.0.1:2582/_metrics | head
```

## Related

- [Documentation Map](documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)


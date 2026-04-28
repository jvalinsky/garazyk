---
title: Logging Strategy
---

# Logging Strategy

## Overview

Garazyk uses a centralized logger because the server has enough cross-cutting
behavior that ad hoc `NSLog` debugging stops scaling quickly. Auth, sync,
storage, and admin code all need to emit messages that can be filtered,
formatted, and correlated consistently.

The current logging strategy is practical rather than elaborate:

- one shared logger
- level-based filtering
- optional component filtering
- text or JSON output
- stdout and optional file output
- correlation IDs for request-level tracing

## Why Central Logging Matters Here

The application is composed from services that share infrastructure but own
different failure modes. Without component-aware logging, a slow auth path and
a slow repository export both collapse into the same stream of messages.

Central logging answers questions like "is this an HTTP problem, an auth problem, or a database problem?" from one runtime.

## Supported Log Dimensions

The logger currently supports:

- log levels: `DEBUG`, `INFO`, `WARN`, `ERROR`
- output formats: text, JSON, or both
- optional file rotation
- stdout printing
- optional async file buffering
- component tags
- thread-local correlation IDs
- `os_log` integration on Apple platforms

The standard component tags include `Database`, `Auth`, `HTTP`, `Admin`,
`Service`, `Core`, `Blob`, `Sync`, `Explore`, and `CLI`.

## Configuration Flow

`PDSApplication` configures the shared logger from `PDSConfiguration` during
startup. The application-configured runtime state matters more than the bare logger defaults.

A few defaults are still worth knowing because older docs often got them wrong:

- the raw logger starts at `DEBUG`
- stdout is enabled
- the default format is text
- async logging is currently disabled by default

If you expect background log buffering, confirm the configuration rather than assuming it.

## Choosing Text Or JSON

Use text logs when you are iterating locally and reading failures in a terminal.
Use JSON logs when you need machine parsing or external ingestion.

The logger supports both
because local debugging and operational collection require different formats.

## Correlation IDs And Request Work

Correlation IDs are the lightweight tracing mechanism already present in the
tree. They are cheaper than a full tracing stack and still good enough to tie
together related log messages during one request or workflow.

When a page feels hard to debug, adding or propagating a correlation ID is
often a better improvement than adding more generic log lines.

## Logging And Security

The docs should not imply that logging magically sanitizes every value. The
real guarantee is narrower: there is one place to control format, level, and
component filtering.

If you are changing auth, admin, or token-handling code, review the emitted log
messages directly rather than assuming the shared logger alone makes them safe.

## When To Reach For Logs

Use logs when:

- metrics show a problem but not the owning subsystem
- an endpoint is failing intermittently
- a request path crosses auth, service, and database code
- you need per-component context that metrics do not expose

Use metrics first, then logs, then code. That order usually minimizes noise.

## Related Reading

- [Performance Monitoring](./performance-monitoring)
- [Metrics Collection](./metrics-collection)
- [Troubleshooting](./troubleshooting)

## Appendix

### Example component-focused config

```json
{
  "logging": {
    "level": "info",
    "format": "json",
    "components": ["HTTP", "Auth", "Database"]
  }
}
```

## Related

- [Documentation Map](documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)


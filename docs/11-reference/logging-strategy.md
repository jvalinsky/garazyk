---
title: Logging Strategy
---

# Logging Strategy

## Overview

Garazyk uses a centralized logger because the server has enough cross-cutting
behavior that ad hoc `NSLog` debugging stops scaling quickly. Auth, sync,
storage, and admin code all need to emit messages that can be filtered,
formatted, and correlated consistently.

The system was recently migrated from the legacy `PDSLogger` to the unified `GZLogger` framework.

- one shared logger
- level-based filtering via `GZ_LOG_LEVEL`
- optional component filtering
- text or JSON output via `GZ_LOG_FORMAT`
- stdout and optional file output
- correlation IDs for request-level tracing
- automatic PII redaction via `GZLogRedactor`

## Why Central Logging Matters Here

The application is composed from services that share infrastructure but own
different failure modes. Without component-aware logging, a slow auth path and
a slow repository export both collapse into the same stream of messages.

Central logging answers questions like "is this an HTTP problem, an auth problem, or a database problem?" from one runtime.

## Supported Log Dimensions

The `GZLogger` currently supports:

- log levels: `DEBUG`, `INFO`, `WARN`, `ERROR`
- output formats: `text`, `json`, or `both`
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

### Environment Overrides

You can override logging behavior globally using these environment variables:

| Variable | Values | Description |
| --- | --- | --- |
| `GZ_LOG_LEVEL` | `debug`, `info`, `warn`, `error` | Minimum level to emit |
| `GZ_LOG_FORMAT` | `text`, `json`, `both` | Output format |
| `GZ_LOG_ASYNC` | `0` or `1` | Enable background buffering |

A few defaults are still worth knowing:

- the raw logger starts at `INFO` (unless changed via `GZ_LOG_LEVEL`)
- stdout is enabled
- the default format is text

## Redaction and Security

The `GZLogRedactor` automatically filters sensitive values from logs. When writing code that logs potentially sensitive information (emails, tokens, keys), use the redaction macros:

```objective-c
GZ_LOG_INFO(@"Auth", @"User logged in: %@", GZ_REDACT_EMAIL(userEmail));
```

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


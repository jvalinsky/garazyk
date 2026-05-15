---
title: Logging Strategy
---

# Logging Strategy

Garazyk uses a centralized logging framework, `GZLogger`, to provide consistent filtering, formatting, and correlation across all subsystems.

## Framework Features

- **Levels:** `DEBUG`, `INFO`, `WARN`, `ERROR`.
- **Formats:** `text`, `json`, or `both`.
- **Redaction:** Automatic PII filtering via `GZLogRedactor`.
- **Correlation:** Thread-local IDs for tracing requests.
- **Filtering:** Optional component-based filtering (e.g., `Auth`, `Database`, `Sync`).

## Component Tags

Use tags to categorize log messages:
- `Database`, `Auth`, `HTTP`, `Admin`, `Service`, `Core`, `Blob`, `Sync`, `Explore`, `CLI`.

## Configuration

`PDSApplication` configures the shared logger during startup using `PDSConfiguration`.

### Environment Variables

| Variable | Values | Purpose |
| --- | --- | --- |
| `GZ_LOG_LEVEL` | `debug`, `info`, `warn`, `error` | Minimum level to emit. |
| `GZ_LOG_FORMAT` | `text`, `json`, `both` | Output format. |
| `GZ_LOG_ASYNC` | `0`, `1` | Enable background buffering. |

### Redaction

Use the redaction macros when logging sensitive data like emails or tokens:

```objective-c
GZ_LOG_INFO(@"Auth", @"User logged in: %@", GZ_REDACT_EMAIL(userEmail));
```

The `GZLogRedactor` handles the masking logic, but developers must still ensure they are using the correct macros for sensitive fields.

## Usage Guidelines

Log messages should be used to:
- Trace intermittent endpoint failures.
- Correlate events across auth, service, and database layers.
- Provide per-component context not visible in metrics.

Use metrics to identify bottlenecks and logs to diagnose the cause.

## Related

- [Performance Monitoring](./performance-monitoring)
- [Metrics Collection](./metrics-collection)
- [Troubleshooting](./troubleshooting)
- [Documentation Map](./documentation-map)


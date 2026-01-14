# PDS Logging System

The ATProto PDS uses a unified, production-ready logging system based on `PDSLogger`. This system supports multiple output formats, component-based filtering, asynchronous I/O, log rotation, and request correlation.

## Configuration

Logging can be configured via `config.json` or environment variables.

### Config File Settings

```json
{
  "logging": {
    "file": "logs/pds.log",
    "level": "info",
    "format": "json",
    "maxSize": 10485760,
    "maxFiles": 5,
    "async": true,
    "components": ["HTTP", "Auth", "Database"]
  }
}
```

- `file`: Path to the log file.
- `level`: Minimum log level (`debug`, `info`, `warn`, `error`).
- `format`: Output format (`text`, `json`, `both`).
- `maxSize`: Max size of a single log file in bytes before rotation.
- `maxFiles`: Maximum number of rotated log files to keep.
- `async`: Enable asynchronous logging to minimize I/O impact on the main loop.
- `components`: Optional list of enabled components. If omitted, all components are enabled.

### CLI Overrides

The `pds serve` command supports overrides:

- `--log-level <level>`: Set the minimum log level.
- `--log-components <c1,c2>`: Comma-separated list of components to enable.

## Log Components

Standard component tags used throughout the codebase:

- `Database`: Database operations and migrations.
- `Auth`: Authentication, JWT, and session management.
- `HTTP`: HTTP server operations and XRPC routing.
- `Admin`: Administrative actions and middleware.
- `Service`: Core app services.
- `Core`: Low-level utilities and entry points.
- `Blob`: Blob storage operations.
- `Sync`: Repository sync and subscription streaming.
- `Explore`: Web interface and directory service.
- `CLI`: Command-line interface dispatcher.

## Request Correlation

Every HTTP request is assigned a unique `correlationID`. This ID is included in every log message generated during the processing of that request, making it easy to trace a single request's flow through the system.

- If the client provides an `X-Correlation-ID` or `X-Request-ID` header, it is used.
- Otherwise, a new UUID is generated.

In JSON logs, this is available as the `correlation_id` field. In text logs, it appears in brackets at the end of the line: `[UUID]`.

## Usage in Code

Always use the `PDS_LOG` macros defined in `PDSLogger.h`:

```objectivec
// Simple message
PDS_LOG_INFO(@"Server started");

// Component-specific message
PDS_LOG_HTTP_DEBUG(@"Request received: %@", request.path);

// Generic component message
PDS_LOG_INFO_C(PDSLogComponentSync, @"Syncing repo: %@", did);

// Error with formatting
PDS_LOG_ERROR(@"Failed to open database: %@", error);
```

## Performance Considerations

- **Async Logging**: High-volume logs are buffered and written to disk on a background queue.
- **Filtering**: Logs below the configured level or outside enabled components are discarded immediately with minimal overhead.
- **Rotation**: Logs are automatically rotated based on size to prevent disk fill-up.

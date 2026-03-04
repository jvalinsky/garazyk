---
title: Logging Strategy
---

# Logging Strategy

This guide covers the logging system in September PDS, including log levels, structured logging, component-based filtering, and sensitive data redaction.

## Overview

September PDS uses a custom `PDSLogger` class that provides:

- **Multiple log levels**: DEBUG, INFO, WARN, ERROR
- **Structured logging**: Text and JSON output formats
- **Component-based filtering**: Tag logs by subsystem
- **Correlation IDs**: Track related log messages across requests
- **Log rotation**: Automatic file rotation based on size
- **Async logging**: Optional background logging for performance
- **Platform integration**: Uses `os_log` on macOS when available

### Logging Pipeline Diagram

The following diagram illustrates the complete logging pipeline from log statement macros through formatters to output destinations and aggregation systems:

<!-- Image placeholder: Logging Pipeline -->

The pipeline consists of seven phases:

1. **Log Statement Macros**: Basic, component-tagged, and shorthand macros that auto-capture context
2. **Data Sanitization**: Helpers that remove sensitive data before logging
3. **PDSLogger Singleton**: Central logger that filters by level and component
4. **Log Formatting**: Text format for development, JSON format for production
5. **Output Destinations**: stdout, log files, os_log (macOS), NSLog (Linux)
6. **Log Rotation**: Automatic rotation based on file size with configurable retention
7. **Log Aggregation**: Integration with log shippers, aggregators, and alerting systems

## Log Levels

The logging system supports four severity levels:

```objc
typedef NS_ENUM(NSInteger, PDSLogLevel) {
    PDSLogLevelDebug = 0,  // Most verbose
    PDSLogLevelInfo,       // Informational messages
    PDSLogLevelWarn,       // Warning messages
    PDSLogLevelError       // Least verbose, errors only
};
```

*Reference: `../../ATProtoPDS/Sources/Debug/PDSLogger.h`*

### Setting the Log Level

```objc
PDSLogger *logger = [PDSLogger sharedLogger];
logger.logLevel = PDSLogLevelInfo;  // Only INFO, WARN, and ERROR will be logged
```

### When to Use Each Level

- **DEBUG**: Detailed diagnostic information for development
  - Variable values, state transitions, algorithm steps
  - Should not be enabled in production
  
- **INFO**: General informational messages
  - Server startup/shutdown, configuration loaded
  - Request processing milestones
  - Background task completion
  
- **WARN**: Warning conditions that don't prevent operation
  - Deprecated API usage, fallback behavior
  - Recoverable errors, retry attempts
  - Performance degradation
  
- **ERROR**: Error conditions requiring attention
  - Failed operations, exceptions
  - Data integrity issues
  - Authentication/authorization failures

## Logging Macros

The logging system provides convenient macros for common use cases:

### Basic Logging

```objc
PDS_LOG_DEBUG(@"Processing request with ID: %@", requestID);
PDS_LOG_INFO(@"Server started on port %d", port);
PDS_LOG_WARN(@"Deprecated API called: %@", apiName);
PDS_LOG_ERROR(@"Failed to connect to database: %@", error);
```

*Reference: `../../ATProtoPDS/Sources/Debug/PDSLogger.h`*

### Macro Definitions

The basic logging macros are defined as follows:

```objc
#define PDS_LOG_DEBUG(FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelDebug file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

#define PDS_LOG_INFO(FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelInfo file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

#define PDS_LOG_WARN(FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelWarn file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

#define PDS_LOG_ERROR(FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelError file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]
```

*Reference: `../../ATProtoPDS/Sources/Debug/PDSLogger.h`*

These macros automatically capture the file name and line number for debugging context.

### Component-Tagged Logging

Use component tags to categorize logs by subsystem:

```objc
PDS_LOG_DEBUG_C(PDSLogComponentDatabase, @"Executing query: %@", sql);
PDS_LOG_INFO_C(PDSLogComponentAuth, @"User authenticated: %@", did);
PDS_LOG_WARN_C(PDSLogComponentHTTP, @"Slow request: %0.2fs", duration);
PDS_LOG_ERROR_C(PDSLogComponentSync, @"Firehose connection lost: %@", error);
```

*Source: <!-- `../../ATProtoPDS/Sources/Debug/PDSLogger.h` -->*

### Macro Definitions for Component Logging

```objc
#define PDS_LOG_DEBUG_C(COMPONENT, FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelDebug component:COMPONENT file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

#define PDS_LOG_INFO_C(COMPONENT, FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelInfo component:COMPONENT file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

#define PDS_LOG_WARN_C(COMPONENT, FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelWarn component:COMPONENT file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

#define PDS_LOG_ERROR_C(COMPONENT, FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelError component:COMPONENT file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]
```

*Reference: `../../ATProtoPDS/Sources/Debug/PDSLogger.h`*

### Component-Specific Shortcuts

Convenience macros for common components:

```objc
// Database logging
PDS_LOG_DB_ERROR(@"Query failed: %@", error);
PDS_LOG_DB_INFO(@"Migration completed: v%d", version);

// Authentication logging
PDS_LOG_AUTH_ERROR(@"Invalid token: %@", token);
PDS_LOG_AUTH_INFO(@"Session created for: %@", did);

// HTTP logging
PDS_LOG_HTTP_ERROR(@"Request failed: %@", error);
PDS_LOG_HTTP_INFO(@"Request completed: %@ %@", method, path);

// Sync/Firehose logging
PDS_LOG_SYNC_ERROR(@"Broadcast failed: %@", error);
PDS_LOG_SYNC_INFO(@"Subscriber connected: %@", subscriberID);
```

*Reference: `../../ATProtoPDS/Sources/Debug/PDSLogger.h`*

### Complete Component Shorthand Macro Definitions

The following shorthand macros are available for all log levels and components:

```objc
// Database component shortcuts
#define PDS_LOG_DB_ERROR(FORMAT, ...)   PDS_LOG_ERROR_C(PDSLogComponentDatabase, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_DB_WARN(FORMAT, ...)    PDS_LOG_WARN_C(PDSLogComponentDatabase, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_DB_INFO(FORMAT, ...)    PDS_LOG_INFO_C(PDSLogComponentDatabase, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_DB_DEBUG(FORMAT, ...)   PDS_LOG_DEBUG_C(PDSLogComponentDatabase, FORMAT, ##__VA_ARGS__)

// Authentication component shortcuts
#define PDS_LOG_AUTH_ERROR(FORMAT, ...) PDS_LOG_ERROR_C(PDSLogComponentAuth, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_AUTH_WARN(FORMAT, ...)  PDS_LOG_WARN_C(PDSLogComponentAuth, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_AUTH_INFO(FORMAT, ...)  PDS_LOG_INFO_C(PDSLogComponentAuth, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_AUTH_DEBUG(FORMAT, ...) PDS_LOG_DEBUG_C(PDSLogComponentAuth, FORMAT, ##__VA_ARGS__)

// HTTP component shortcuts
#define PDS_LOG_HTTP_ERROR(FORMAT, ...) PDS_LOG_ERROR_C(PDSLogComponentHTTP, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_HTTP_WARN(FORMAT, ...)  PDS_LOG_WARN_C(PDSLogComponentHTTP, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_HTTP_INFO(FORMAT, ...)  PDS_LOG_INFO_C(PDSLogComponentHTTP, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_HTTP_DEBUG(FORMAT, ...) PDS_LOG_DEBUG_C(PDSLogComponentHTTP, FORMAT, ##__VA_ARGS__)

// Admin component shortcuts
#define PDS_LOG_ADMIN_ERROR(FORMAT, ...) PDS_LOG_ERROR_C(PDSLogComponentAdmin, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_ADMIN_WARN(FORMAT, ...)  PDS_LOG_WARN_C(PDSLogComponentAdmin, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_ADMIN_INFO(FORMAT, ...)  PDS_LOG_INFO_C(PDSLogComponentAdmin, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_ADMIN_DEBUG(FORMAT, ...) PDS_LOG_DEBUG_C(PDSLogComponentAdmin, FORMAT, ##__VA_ARGS__)

// Service component shortcuts
#define PDS_LOG_SERVICE_ERROR(FORMAT, ...) PDS_LOG_ERROR_C(PDSLogComponentService, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_SERVICE_WARN(FORMAT, ...)  PDS_LOG_WARN_C(PDSLogComponentService, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_SERVICE_INFO(FORMAT, ...)  PDS_LOG_INFO_C(PDSLogComponentService, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_SERVICE_DEBUG(FORMAT, ...) PDS_LOG_DEBUG_C(PDSLogComponentService, FORMAT, ##__VA_ARGS__)

// Sync/Firehose component shortcuts
#define PDS_LOG_SYNC_ERROR(FORMAT, ...) PDS_LOG_ERROR_C(PDSLogComponentSync, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_SYNC_WARN(FORMAT, ...)  PDS_LOG_WARN_C(PDSLogComponentSync, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_SYNC_INFO(FORMAT, ...)  PDS_LOG_INFO_C(PDSLogComponentSync, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_SYNC_DEBUG(FORMAT, ...) PDS_LOG_DEBUG_C(PDSLogComponentSync, FORMAT, ##__VA_ARGS__)

// Core component shortcuts
#define PDS_LOG_CORE_ERROR(FORMAT, ...) PDS_LOG_ERROR_C(PDSLogComponentCore, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_CORE_WARN(FORMAT, ...)  PDS_LOG_WARN_C(PDSLogComponentCore, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_CORE_INFO(FORMAT, ...)  PDS_LOG_INFO_C(PDSLogComponentCore, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_CORE_DEBUG(FORMAT, ...) PDS_LOG_DEBUG_C(PDSLogComponentCore, FORMAT, ##__VA_ARGS__)

// Blob component shortcuts
#define PDS_LOG_BLOB_ERROR(FORMAT, ...) PDS_LOG_ERROR_C(PDSLogComponentBlob, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_BLOB_WARN(FORMAT, ...)  PDS_LOG_WARN_C(PDSLogComponentBlob, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_BLOB_INFO(FORMAT, ...)  PDS_LOG_INFO_C(PDSLogComponentBlob, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_BLOB_DEBUG(FORMAT, ...) PDS_LOG_DEBUG_C(PDSLogComponentBlob, FORMAT, ##__VA_ARGS__)

// Explore UI component shortcuts
#define PDS_LOG_EXPLORE_ERROR(FORMAT, ...) PDS_LOG_ERROR_C(PDSLogComponentExplore, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_EXPLORE_WARN(FORMAT, ...)  PDS_LOG_WARN_C(PDSLogComponentExplore, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_EXPLORE_INFO(FORMAT, ...)  PDS_LOG_INFO_C(PDSLogComponentExplore, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_EXPLORE_DEBUG(FORMAT, ...) PDS_LOG_DEBUG_C(PDSLogComponentExplore, FORMAT, ##__VA_ARGS__)

// CLI component shortcuts
#define PDS_LOG_CLI_ERROR(FORMAT, ...) PDS_LOG_ERROR_C(PDSLogComponentCLI, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_CLI_WARN(FORMAT, ...)  PDS_LOG_WARN_C(PDSLogComponentCLI, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_CLI_INFO(FORMAT, ...)  PDS_LOG_INFO_C(PDSLogComponentCLI, FORMAT, ##__VA_ARGS__)
#define PDS_LOG_CLI_DEBUG(FORMAT, ...) PDS_LOG_DEBUG_C(PDSLogComponentCLI, FORMAT, ##__VA_ARGS__)
```

*Reference: `../../ATProtoPDS/Sources/Debug/PDSLogger.h`*

## Real-World Usage Examples

### Error Logging Patterns

#### Database Errors

```objc
// From PDSAdminService.m
PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:&error];
if (!db) {
    PDS_LOG_ERROR(@"Failed to get service database: %@", error);
    return nil;
}
```

*Reference: `../../ATProtoPDS/Sources/Services/PDSAdminService.m`*

#### Network/Proxy Errors

```objc
// From XrpcProxyHandler.m
NSString *token = [self.minter signPayload:payload error:&mintError];
if (!token) {
    PDS_LOG_ERROR(@"Failed to mint proxy token: %@", mintError);
    response.statusCode = HttpStatusInternalServerError;
    [response setJsonBody:@{@"error": @"InternalError", 
                            @"message": @"Failed to create service token"}];
    return;
}
```

*Reference: `../../ATProtoPDS/Sources/Network/XrpcProxyHandler.m`*

#### Repository Initialization Errors

```objc
// From XrpcServerMethods.m
NSError *initError = nil;
if (![repositoryService initializeRepoForDid:createdDid error:&initError]) {
    PDS_LOG_ERROR(@"Failed to initialize repo for DID %@: %@", createdDid, initError);
}
```

*Reference: `../../ATProtoPDS/Sources/Network/XrpcServerMethods.m`*

### Info Logging Patterns

#### Service Initialization

```objc
// From PDSRelayService.m
PDS_LOG_INFO(@"PDSRelayService started with %lu relays",
             (unsigned long)self.relays.count);
```

*Reference: `../../ATProtoPDS/Sources/App/Services/PDSRelayService.m`*

#### Email Provider Configuration

```objc
// From PDSController.m
PDS_LOG_INFO(@"Initialized Resend email provider (source: %@, from: %@)",
             source, config.resendFromAddress);
```

*Reference: `../../ATProtoPDS/Sources/App/PDSController.m`*

#### Lexicon Loading

```objc
// From ATProtoLexiconRegistry.m
PDS_LOG_INFO(@"[LexiconRegistry] Loaded %lu lexicons (%lu errors) from %@",
             (unsigned long)loadedCount, (unsigned long)errorCount, path);
```

*Reference: `../../ATProtoPDS/Sources/Lexicon/ATProtoLexiconRegistry.m`*

#### Account Operations

```objc
// From PDSAdminService.m
PDS_LOG_INFO(@"Taking down account: %@ reason: %@", did, reason);
return [_database takeDownAccount:did reason:reason takedownRef:nil error:error];
```

*Reference: `../../ATProtoPDS/Sources/Services/PDSAdminService.m`*

### Component-Specific Logging Examples

#### Authentication Logging (PDS_LOG_AUTH_*)

```objc
// From XrpcAuthHelper.m - Warning about missing DPoP header
NSString *dpopProof = [request headerForKey:@"DPoP"];
if (dpopProof.length == 0) {
    PDS_LOG_AUTH_WARN(@"Missing DPoP header for DPoP authorization");
    return nil;
}
```

*Reference: `../../ATProtoPDS/Sources/Network/XrpcAuthHelper.m`*

```objc
// From XrpcAuthHelper.m - JWT verification failure
BOOL isValid = [verifier verifyJWT:jwt error:&verifyError];
if (!isValid || verifyError) {
    PDS_LOG_AUTH_WARN(@"JWT verification failed for request from IP: %@", 
                      request.remoteAddress ?: @"unknown");
    return nil;
}
```

*Reference: `../../ATProtoPDS/Sources/Network/XrpcAuthHelper.m`*

```objc
// From XrpcAuthHelper.m - Suspended account detection
if (isTakedown) {
    PDS_LOG_AUTH_WARN(@"Rejected request for suspended account %@", did);
    return nil;
}
```

*Reference: `../../ATProtoPDS/Sources/Network/XrpcAuthHelper.m`*

```objc
// From OAuthProvider.m - Debug logging for token issuance
PDS_LOG_AUTH_DEBUG(@"Tokens issued: sub=%@ client_id=%@", sub, clientID);
completion(response, nil);
```

*Source: <!-- `../../ATProtoPDS/Sources/OAuthProvider/OAuthProvider.m` -->*

#### CLI Logging

```objc
// From PDSCLIServeCommand.m - Server startup information
if (context.verbose) {
    PDS_LOG_INFO(@"Starting PDS server on port %ld", (long)port);
    PDS_LOG_INFO(@"Data directory: %@", context.dataDir);
    PDS_LOG_INFO(@"Config path: %@", context.configPath);
    PDS_LOG_INFO(@"Log level: %@", logLevel);
    if (logComponents) {
        PDS_LOG_INFO(@"Enabled components: %@", logComponents);
    }
}
```

*Reference: `../../ATProtoPDS/Sources/CLI/PDSCLIServeCommand.m`*

### Structured Logging with Context

#### Exception Handling with Stack Traces

```objc
// From XrpcHandler.m - Logging unhandled exceptions
NSString *name = exception.name ?: @"(null)";
NSString *reason = exception.reason ?: @"(null)";
NSArray<NSString *> *stack = exception.callStackSymbols ?: @[];
PDS_LOG_ERROR(@"[XRPC] Unhandled exception in %@: %@ (%@)\n%@",
              methodId, name, reason, [stack componentsJoinedByString:@"\n"]);
```

*Reference: `../../ATProtoPDS/Sources/Network/XrpcHandler.m`*

This pattern provides comprehensive debugging information including the full stack trace.

## Standard Components

The following component tags are defined:

- **`PDSLogComponentDatabase`**: Database operations, queries, migrations
- **`PDSLogComponentAuth`**: Authentication, authorization, token handling
- **`PDSLogComponentHTTP`**: HTTP server, request handling, routing
- **`PDSLogComponentAdmin`**: Admin operations, moderation, takedowns
- **`PDSLogComponentService`**: Service layer operations
- **`PDSLogComponentCore`**: Core application lifecycle
- **`PDSLogComponentBlob`**: Blob storage and retrieval
- **`PDSLogComponentSync`**: Firehose, WebSocket, event streaming
- **`PDSLogComponentExplore`**: Explorer UI
- **`PDSLogComponentCLI`**: CLI commands

*Reference: `../../ATProtoPDS/Sources/Debug/PDSLogger.h`*

## Structured Logging

The logger supports both text and JSON output formats.

### Text Format (Default)

Human-readable format for development:

```

[2025-01-15 14:32:45.123] [INFO] [Auth] [XrpcAuthHelper.m:224] User authenticated: did:plc:abc123
[2025-01-15 14:32:45.456] [ERROR] [Database] [PDSDatabase.m:89] Query failed: table not found
```

### JSON Format

Machine-parseable format for log aggregation:

```json
{
  "timestamp": "2025-01-15T14:32:45.123Z",
  "level": "INFO",
  "component": "Auth",
  "message": "User authenticated: did:plc:abc123",
  "file": "XrpcAuthHelper.m",
  "line": 224,
  "thread_id": "0x1a2b3c4d",
  "pid": 12345,
  "correlation_id": "req-abc-123"
}
```

*Reference: `../../ATProtoPDS/Sources/Debug/PDSLogger.m`*

### Configuring Output Format

```objc
PDSLogger *logger = [PDSLogger sharedLogger];

// Text format only (default)
logger.logFormat = PDSLogFormatText;

// JSON format only
logger.logFormat = PDSLogFormatJSON;

// Both formats
logger.logFormat = PDSLogFormatBoth;
```

*Reference: `../../ATProtoPDS/Sources/Debug/PDSLogger.h`*

## Correlation IDs

Use correlation IDs to track related log messages across a request lifecycle:

```objc
// Set correlation ID at request start
NSString *requestID = [[NSUUID UUID] UUIDString];
[[PDSLogger sharedLogger] setCorrelationID:requestID];

// All subsequent logs will include this ID
PDS_LOG_INFO(@"Processing request");
PDS_LOG_DEBUG(@"Validating parameters");

// Clear correlation ID when done
[[PDSLogger sharedLogger] clearCorrelationID];
```

*Reference: `../../ATProtoPDS/Sources/Debug/PDSLogger.h`*

Correlation IDs are stored in thread-local storage, so they're automatically isolated per-thread.

*Reference: `../../ATProtoPDS/Sources/Debug/PDSLogger.m`*

## Log File Management

### Configuring Log Files

```objc
PDSLogger *logger = [PDSLogger sharedLogger];

// Set log file path
logger.logFilePath = @"/var/log/pds/server.log";

// Configure rotation
logger.maxLogFileSize = 10 * 1024 * 1024;  // 10MB
logger.maxLogFiles = 5;  // Keep 5 rotated files

// Enable stdout output
logger.printToStdout = YES;
```

*Reference: `../../ATProtoPDS/Sources/Debug/PDSLogger.h`*

### Log Rotation

Logs are automatically rotated when they exceed `maxLogFileSize`:

```

server.log       (current)
server.log.1     (previous)
server.log.2
server.log.3
server.log.4
server.log.5     (oldest, deleted on next rotation)
```

*Reference: `../../ATProtoPDS/Sources/Debug/PDSLogger.m`*

### Manual Rotation

```objc
// Force immediate rotation
[[PDSLogger sharedLogger] forceRotate];

// Flush buffered logs
[[PDSLogger sharedLogger] flush];
```

## Component Filtering

Enable logging for specific components only:

```objc
PDSLogger *logger = [PDSLogger sharedLogger];

// Only log Auth and Database components
logger.enabledComponents = [NSSet setWithObjects:
    PDSLogComponentAuth,
    PDSLogComponentDatabase,
    nil
];

// Re-enable all components
logger.enabledComponents = nil;
```

*Reference: `../../ATProtoPDS/Sources/Debug/PDSLogger.h`*

This is useful for debugging specific subsystems without noise from others.

## Async Logging

For high-throughput scenarios, enable async logging:

```objc
PDSLogger *logger = [PDSLogger sharedLogger];
logger.asyncLogging = YES;
```

**How it works**:
- Log messages are buffered in memory
- Buffer is flushed every 100 messages or on ERROR level
- Background queue handles file I/O
- Reduces latency on the logging thread

**Trade-offs**:
- Logs may be lost if the process crashes before flush
- Slightly more complex debugging (logs appear delayed)
- Better for production, worse for development

*Reference: `../../ATProtoPDS/Sources/Debug/PDSLogger.m`*

## Sensitive Data Redaction

### Redaction Rules

**NEVER log the following**:
- Passwords, tokens, API keys
- Private keys, signing keys
- Session secrets, refresh tokens
- Email addresses (in production)
- IP addresses (in production, depending on privacy policy)
- Full DIDs in high-volume logs (use truncated versions)

### Sanitization Patterns

The codebase uses several patterns to avoid logging sensitive data:

#### 1. Sanitized Error Summaries

Instead of logging full error objects (which may contain sensitive data), log sanitized summaries:

```objc
// Helper function definition
static NSString *XrpcAuthSanitizedErrorSummary(NSError *error) {
    if (!error) {
        return @"domain=unknown code=0";
    }
    return [NSString stringWithFormat:@"domain=%@ code=%ld",
            error.domain, (long)error.code];
}

// Usage in authentication code
PDS_LOG_AUTH_WARN(@"Invalid DPoP proof (%@)", 
                  XrpcAuthSanitizedErrorSummary(dpopError));
```

*Source: <!-- `../../ATProtoPDS/Sources/Network/XrpcAuthHelper.m` -->*

This pattern extracts only the error domain and code, avoiding potentially sensitive information in the error's `userInfo` dictionary or localized description.

**Real-world usage examples:**

```objc
// From XrpcAuthHelper.m - Checking takedown status
BOOL isTakedown = [adminController isAccountTakedownActive:did error:&takedownError];
if (takedownError) {
    PDS_LOG_AUTH_WARN(@"Failed to check takedown status (%@)", 
                      XrpcAuthSanitizedErrorSummary(takedownError));
    return nil;
}
```

*Reference: `../../ATProtoPDS/Sources/Network/XrpcAuthHelper.m`*

```objc
// From PDSAdminAuth.m - JWT verification failure
if (![verifier verifyJWT:jwt error:&verifyError]) {
    PDS_LOG_AUTH_WARN(@"PDSAdminAuth: JWT verification failed (%@)",
                      PDSAdminAuthSanitizedErrorSummary(verifyError));
    if (error) {
        *error = [NSError errorWithDomain:PDSAdminAuthErrorDomain 
                                     code:401 
                                 userInfo:@{NSLocalizedDescriptionKey: @"Invalid token"}];
    }
    return nil;
}
```

*Reference: `../../ATProtoPDS/Sources/Admin/PDSAdminAuth.m`*

**Additional sanitized error helpers:**

The same pattern is used in multiple modules with module-specific helper functions:

- `PDSAdminAuthSanitizedErrorSummary()` in `../../ATProtoPDS/Sources/Admin/PDSAdminAuth.m`
- `XrpcAuthSanitizedErrorSummary()` in `../../ATProtoPDS/Sources/Network/XrpcAuthHelper.m`

#### 2. Sanitized URLs

Remove query parameters and credentials from URLs before logging:

```objc
// Helper function definition
static NSString *PDSSanitizedURLString(NSURL *url) {
    if (!url) return @"";
    NSURLComponents *components = [NSURLComponents componentsWithURL:url 
                                              resolvingAgainstBaseURL:NO];
    if (!components) return url.absoluteString ?: @"";
    components.query = nil;      // Remove query parameters
    components.fragment = nil;   // Remove fragments
    return components.string ?: (url.absoluteString ?: @"");
}

// Usage
PDS_LOG_SERVICE_INFO(@"Forwarding request to %@", PDSSanitizedURLString(url));
```

*Reference: `../../ATProtoPDS/Sources/Federation/FederationClient.m`*

This prevents logging of sensitive data that might be in URL query parameters (tokens, API keys, etc.).

**Real-world usage examples:**

```objc
// From FederationClient.m - XRPC forwarding
PDS_LOG_SERVICE_INFO(@"Forwarding XRPC request (method=%@, did=%@) to %@", 
                     method ?: @"", did ?: @"", PDSSanitizedURLString(url));
```

*Reference: `../../ATProtoPDS/Sources/Federation/FederationClient.m`*

```objc
// From FederationClient.m - HTTP forwarding
PDS_LOG_SERVICE_INFO(@"Forwarding HTTP request (method=%@) to %@", 
                     method ?: @"", PDSSanitizedURLString(url));
```

*Reference: `../../ATProtoPDS/Sources/Federation/FederationClient.m`*

```objc
// From FederationClient.m - Binary XRPC forwarding
PDS_LOG_SERVICE_INFO(@"Forwarding binary XRPC request (method=%@, did=%@) to %@", 
                     method ?: @"", did ?: @"", PDSSanitizedURLString(url));
```

*Reference: `../../ATProtoPDS/Sources/Federation/FederationClient.m`*

#### 3. Redacting Record Data

When logging events, remove large or sensitive fields:

```objc
// From EventFormatter.m - Sanitizing firehose commit events
// Sanitize ops to remove recordCBOR which is internal-only and huge
// Per ATProto spec, the record data is in the blocks (CAR), not in the ops metadata
NSMutableArray *sanitizedOps = [NSMutableArray arrayWithCapacity:event.ops.count];
for (NSDictionary *op in event.ops) {
    if (op[@"recordCBOR"]) {
        NSMutableDictionary *cleanOp = [op mutableCopy];
        [cleanOp removeObjectForKey:@"recordCBOR"];
        [sanitizedOps addObject:cleanOp];
    } else {
        [sanitizedOps addObject:op];
    }
}
payload[@"ops"] = sanitizedOps;
```

*Reference: `../../ATProtoPDS/Sources/Sync/EventFormatter.m`*

This pattern removes the `recordCBOR` field which contains the full record data (potentially sensitive user content) while keeping the metadata needed for debugging.

#### 4. Null Byte Sanitization

Input validation helpers strip null bytes before processing to prevent injection attacks. While primarily for security, this also ensures clean log output:

```objc
// From PDSInputValidator.m - Sanitizing SQL input
- (nullable NSString *)sanitizeSQLInput:(NSString *)input error:(NSError **)error {
    if (!input || input.length == 0) {
        if (error) *error = [NSError errorWithDomain:PDSValidationErrorDomain 
                                                 code:PDSValidationErrorEmptyString 
                                             userInfo:@{NSLocalizedDescriptionKey: @"SQL input cannot be empty"}];
        return nil;
    }
    NSMutableString *sanitized = [NSMutableString stringWithString:input];
    [sanitized replaceOccurrencesOfString:@"\0" withString:@"" options:0 range:NSMakeRange(0, sanitized.length)];
    return [sanitized copy];
}
```

*Reference: `../../ATProtoPDS/Sources/Security/PDSInputValidator.m`*

Similar sanitization is applied in:
- `sanitizePathInput:error:` - `../../ATProtoPDS/Sources/Security/PDSInputValidator.m`
- `sanitizeJSONField:error:` - `../../ATProtoPDS/Sources/Security/PDSInputValidator.m`

### Best Practices for Redaction

1. **Log identifiers, not content**: Log DIDs, not user data
2. **Use truncation**: `did:plc:abc...xyz` instead of full DID
3. **Log metadata, not payloads**: Log request size, not request body
4. **Sanitize before formatting**: Don't rely on format strings for security
5. **Review logs regularly**: Use the `objc-log-redaction-audit` skill

### What NOT to Log

The following data types should **NEVER** appear in logs:

#### Authentication & Secrets

- **Passwords** (plaintext or hashed) - Never log password values
- **Access tokens, refresh tokens** - Log only token metadata (type, expiration)
- **API keys, service tokens** - Use sanitized error summaries instead
- **Private keys, signing keys** - Never log cryptographic key material
- **Session secrets** - Log session IDs only, not secret values
- **DPoP proofs** - Log validation results, not proof contents
- **JWT payloads** - Log claims metadata, not full payload

**Example - What to log:**

```objc
// GOOD: Log token issuance metadata
PDS_LOG_AUTH_DEBUG(@"Tokens issued: sub=%@ client_id=%@", sub, clientID);
```

*Reference: `../../ATProtoPDS/Sources/OAuthProvider/OAuthProvider.m`*

```objc
// GOOD: Log token validation failure without exposing token
PDS_LOG_AUTH_WARN(@"JWT verification failed for request from IP: %@", 
                  request.remoteAddress ?: @"unknown");
```

*Source: <!-- `../../ATProtoPDS/Sources/Network/XrpcAuthHelper.m` -->*

```objc
// GOOD: Log password operations without the password value
PDS_LOG_INFO(@"Updating password for account: %@", did);
```

*Reference: `../../ATProtoPDS/Sources/Services/PDSAdminService.m`*

#### Personal Information

- **Email addresses** - Consider privacy policy; may be acceptable in development, should be limited in production
- **Full DIDs in high-volume logs** - Use truncated versions for performance
- **User-generated content** - Log content metadata (size, type), not actual content
- **IP addresses** - Consider privacy regulations; acceptable for security/debugging but may need retention limits

**Example - Email logging patterns:**

```objc
// Development/debugging: Email addresses are logged
PDS_LOG_INFO(@"[Resend] Sending email to: %@ subject: %@", to, subject);
```

*Reference: `../../ATProtoPDS/Sources/Email/PDSResendEmailProvider.m`*

**Note:** Email logging is currently used for debugging email delivery. In production environments with strict privacy requirements, consider logging only email domain or a hash.

**Example - IP address logging patterns:**

```objc
// Acceptable: IP addresses for security monitoring
PDS_LOG_HTTP_INFO(@"[%@] %@ %@", request.remoteAddress, request.methodString, logPath);
```

*Reference: `../../ATProtoPDS/Sources/Network/HttpServer.m`*

```objc
// Acceptable: IP addresses for authentication failures
PDS_LOG_AUTH_WARN(@"JWT verification failed for request from IP: %@", 
                  request.remoteAddress ?: @"unknown");
```

*Reference: `../../ATProtoPDS/Sources/Network/XrpcAuthHelper.m`*

**Privacy considerations for IP addresses:**
- IP addresses are logged for security monitoring, rate limiting, and debugging
- Consider your jurisdiction's privacy regulations (GDPR, CCPA, etc.)
- Implement log retention policies appropriate for your privacy requirements
- Consider anonymization or truncation for long-term storage

#### Large or Binary Data

- **Full record CBOR data** - Use the EventFormatter sanitization pattern
- **Binary blobs** - Log size and hash, not content
- **CAR file contents** - Log metadata only
- **Full request/response bodies** - Log size and content-type

**Example - Redacting large data:**

```objc
// GOOD: Remove recordCBOR before logging/transmitting
if (op[@"recordCBOR"]) {
    NSMutableDictionary *cleanOp = [op mutableCopy];
    [cleanOp removeObjectForKey:@"recordCBOR"];
    [sanitizedOps addObject:cleanOp];
}
```

*Reference: `../../ATProtoPDS/Sources/Sync/EventFormatter.m`*

### Creating New Sanitization Helpers

When adding new logging to sensitive code paths, follow these patterns:

#### Pattern 1: Module-Specific Error Sanitizer

```objc
// In your .m file (static function)
static NSString *MyModuleSanitizedErrorSummary(NSError *error) {
    if (!error) {
        return @"domain=unknown code=0";
    }
    return [NSString stringWithFormat:@"domain=%@ code=%ld",
            error.domain, (long)error.code];
}

// Usage
PDS_LOG_ERROR(@"Operation failed (%@)", MyModuleSanitizedErrorSummary(error));
```

#### Pattern 2: URL Sanitizer

```objc
// In your .m file (static function)
static NSString *MySanitizedURLString(NSURL *url) {
    if (!url) return @"";
    NSURLComponents *components = [NSURLComponents componentsWithURL:url 
                                              resolvingAgainstBaseURL:NO];
    if (!components) return url.absoluteString ?: @"";
    components.query = nil;      // Remove query parameters
    components.fragment = nil;   // Remove fragments
    return components.string ?: (url.absoluteString ?: @"");
}
```

#### Pattern 3: Field Redaction

```objc
// Remove sensitive fields before logging
NSMutableDictionary *sanitized = [originalDict mutableCopy];
[sanitized removeObjectForKey:@"password"];
[sanitized removeObjectForKey:@"token"];
[sanitized removeObjectForKey:@"secret"];
PDS_LOG_DEBUG(@"Request data: %@", sanitized);
```

## Platform-Specific Logging

### macOS: os_log Integration

On macOS, logs are also sent to the unified logging system. The capability is explicitly guarded to ensure it only compiles on Apple platforms:

```objc
#if defined(__APPLE__) && __has_include(<os/log.h>)
#define PDS_HAS_OS_LOG 1
#endif

#if PDS_HAS_OS_LOG
- (void)logToOSLogWithLevel:(PDSLogLevel)level
                  formatted:(NSString *)formatted
                  component:(NSString *)component {
    os_log_t log = os_log_create("com.atproto.pds", [component UTF8String]);
    os_log_with_type(log, type, "%{public}@", formatted);
}
#endif
```

*Reference: `../../ATProtoPDS/Sources/Debug/PDSLogger.m`*

View logs with Console.app or `log` command:

```bash
# Stream PDS logs
log stream --predicate 'subsystem == "com.atproto.pds"'

# Filter by component
log stream --predicate 'subsystem == "com.atproto.pds" && category == "Auth"'
```

## Linux/GNUstep: NSLog Fallback

On Linux, the system falls back to `NSLog`:

```c
#define os_log(log, format, ...) \
    NSLog(PDS_LOG_CONVERT(format), ##__VA_ARGS__)

#define os_log_info(log, format, ...) \
    NSLog(@"[ATProtoPDS INFO] " PDS_LOG_CONVERT(format), ##__VA_ARGS__)
```

*Reference: `../../Sources/Compat/os/log.h`*

## Configuration Examples

### Development Configuration

```objc
PDSLogger *logger = [PDSLogger sharedLogger];
logger.logLevel = PDSLogLevelDebug;
logger.printToStdout = YES;
logger.logFormat = PDSLogFormatText;
logger.asyncLogging = NO;  // Immediate output for debugging
```

### Production Configuration

```objc
PDSLogger *logger = [PDSLogger sharedLogger];
logger.logLevel = PDSLogLevelInfo;
logger.logFilePath = @"/var/log/pds/server.log";
logger.printToStdout = NO;
logger.logFormat = PDSLogFormatJSON;  // For log aggregation
logger.asyncLogging = YES;  // Better performance
logger.maxLogFileSize = 50 * 1024 * 1024;  // 50MB
logger.maxLogFiles = 10;
```

### Debug Specific Component

```objc
PDSLogger *logger = [PDSLogger sharedLogger];
logger.logLevel = PDSLogLevelDebug;
logger.enabledComponents = [NSSet setWithObject:PDSLogComponentAuth];
// Only Auth component logs will be output
```

## Integration with Monitoring

### Shipping Logs to Aggregators

For JSON format logs, use log shippers like:

- **Filebeat**: Ships to Elasticsearch
- **Fluentd**: Ships to various backends
- **Vector**: High-performance log router

Example Filebeat configuration:

```yaml
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/pds/server.log
    json.keys_under_root: true
    json.add_error_key: true

output.elasticsearch:
  hosts: ["localhost:9200"]
  index: "pds-logs-%{+yyyy.MM.dd}"
```

### Querying JSON Logs

With JSON format, you can query logs programmatically:

```bash
# Find all errors in the last hour
jq 'select(.level == "ERROR" and .timestamp > "2025-01-15T13:00:00Z")' server.log

# Count errors by component
jq -r 'select(.level == "ERROR") | .component' server.log | sort | uniq -c

# Find logs for a specific correlation ID
jq 'select(.correlation_id == "req-abc-123")' server.log
```

## Best Practices

### Do's

- **Use appropriate log levels**: Don't log everything at ERROR
- **Include context**: Log relevant IDs, states, and parameters
- **Use component tags**: Makes filtering and debugging easier
- **Set correlation IDs**: Track requests across the system
- **Sanitize sensitive data**: Never log secrets or PII
- **Log errors with context**: Include error domain and code
- **Use structured logging in production**: JSON format for aggregation

### Don'ts

- **Don't log in tight loops**: Causes performance issues
- **Don't log sensitive data**: Passwords, tokens, keys
- **Don't log full objects**: Use selective field logging
- **Don't ignore log levels**: Respect the configured level
- **Don't log to stdout in production**: Use log files
- **Don't forget to flush**: Call `flush` before shutdown
- **Don't log without context**: Include relevant identifiers

## Related Documentation

- [Metrics Collection](metrics-collection) - Quantitative monitoring
- [Performance Monitoring](performance-monitoring) - Profiling and optimization
- [Security Audit Guide](security-audit-guide) - Using the log redaction audit skill
- [Secrets Management](../06-authentication/secrets-management) - Handling sensitive data

## Auditing Log Redaction

The repository includes a specialized audit skill for reviewing log statements:

### Using the Log Redaction Audit Skill

The `objc-log-redaction-audit` skill (located in `.opencode/skills/objc-log-redaction-audit/`) analyzes the codebase for potential sensitive data leaks in log statements.

**What it checks:**
- Passwords, tokens, keys in log statements
- Email addresses and PII in logs
- Full error objects that may contain sensitive data
- URLs with query parameters
- Large binary data in logs

**How to use:**

Refer to the skill's documentation in `.opencode/skills/objc-log-redaction-audit/` for usage instructions. The skill can be invoked through Kiro's skill system to perform automated analysis of logging patterns.

**When to audit:**
- Before production deployment
- After adding new authentication/authorization code
- When implementing new API endpoints
- During security reviews
- After adding email or notification features

## See Also

- [Apple Unified Logging](https://developer.apple.com/documentation/os/logging)
- [Structured Logging Best Practices](https://www.structlog.org/en/stable/why.html)
- [OWASP Logging Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html)

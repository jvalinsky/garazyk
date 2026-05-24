# Refactoring Inventory Matrix: Mikrus, Beskid, and Syrena

This document lists and maps the matching capabilities, duplicate logic, and
boilerplate code across **Mikrus**, **Beskid**, and **Syrena (AppView)**.

## Core Capability Comparison

| Feature / Domain              | Mikrus                           | Beskid                           | Syrena (AppView)                      | Implementation State                     |
| ----------------------------- | -------------------------------- | -------------------------------- | ------------------------------------- | ---------------------------------------- |
| **Signal Trapping**           | `GZSignalManager`                | `GZSignalManager`                | `GZSignalManager`                     | Duplicated signal block registration     |
| **Crash Reporting**           | `GZCrashReporter`                | `GZCrashReporter`                | `GZCrashReporter`                     | Duplicated initialization                |
| **Linux Compat Checks**       | -                                | -                                | Category verification check           | GNUstep-specific categories              |
| **CLI Parser**                | Custom `parse_options`           | Custom `parse_options`           | Custom `parse_appview_options`        | Highly similar scanner-based parsing     |
| **Configuration Model**       | `MikrusConfiguration`            | `BeskidConfiguration`            | `AppViewConfiguration`                | Identical pattern (load env, parse dict) |
| **IP Rate-Limiting Config**   | Yes                              | Yes                              | No (handled differently)              | Duplicate dictionary keys and env-vars   |
| **SQLite Connection**         | Pooled (`ATProtoConnectionPool`) | Pooled (`ATProtoConnectionPool`) | Raw (`sqlite3_open_v2` + queue)       | Architectural divergence                 |
| **WAL & Pragma Setup**        | Managed by Pool                  | Managed by Pool                  | Direct `ATProtoDBConfigurePragmas`    | Partially shared via `Database/Utils/`   |
| **DB Query Helpers**          | `executeQuery:params:error:`     | `executeQuery:params:error:`     | `executeParameterizedQuery:...`       | Character-for-character duplication      |
| **DB Update Helpers**         | `executeUpdate:params:error:`    | `executeUpdate:params:error:`    | `executeParameterizedUpdate:...`      | Character-for-character duplication      |
| **Local Identity Cache**      | Yes (`mikrus_handles`)           | Yes (`beskid_identities`)        | Yes (`handles` / `appview_relevance`) | Shared concepts, separate tables         |
| **HTTP Parameter Validation** | Duplicated helpers               | Duplicated helpers               | Handled in handler methods            | Standard validation helpers              |
| **HTTP Rate-Limiting**        | `checkRateLimitForRequest:...`   | `checkRateLimitForRequest:...`   | -                                     | Character-for-character duplication      |
| **DID Doc Property Parsers**  | `handleFromDocument:` etc.       | `handleFromDocument:` etc.       | Handled in identity helper classes    | Character-for-character duplication      |
| **Network Read-Throughs**     | `fetchRemoteRecord...`           | `fetchAndCacheRemoteRecord...`   | Managed by backfill orchestrator      | Overlapping safe HTTP requests           |

---

## Detailed Duplication Breakdown

### 1. Main Entrypoint Boilerplate (`main.m`)

- **Bootstrapping**:
  ```objc
  [[GZSignalManager sharedManager] installIgnoredSignals];
  [GZCrashReporter installCrashHandlersWithExecutableName:"..."];
  #if defined(GNUSTEP)
      curl_global_init(CURL_GLOBAL_ALL);
  #endif
  @autoreleasepool {
      NSDateFormatterLinkATProtoCategory();
  ```
  Found in:
  - [mikrus/main.m](file:///Users/jack/Software/garazyk/Garazyk/Binaries/mikrus/main.m#L113-L119)
  - [beskid/main.m](file:///Users/jack/Software/garazyk/Garazyk/Binaries/beskid/main.m#L97-L103)
  - [syrena/main.m](file:///Users/jack/Software/garazyk/Garazyk/Binaries/syrena/main.m#L213-L228)

- **Graceful Shutdown Trapping**: Registering `SIGINT`/`SIGTERM` handlers that
  call `[runtime stop]` followed by `exit(0)`.

### 2. Configuration Class Structure

All three configure themselves by mapping environment variables and config files
to properties.

- **Environment Value Overrides**: Duplicate logic in
  `+configurationFromEnvironment` extracting parameters using
  `[[NSProcessInfo processInfo] environment]`.
- **String/Number Port Parsing**: Scanner-based numeric check to guarantee the
  HTTP port fits in a `uint16_t` range. Found in:
  - [MikrusConfiguration.m](file:///Users/jack/Software/garazyk/Garazyk/Sources/Mikrus/MikrusConfiguration.m#L68-L79)
  - [BeskidConfiguration.m](file:///Users/jack/Software/garazyk/Garazyk/Sources/Beskid/BeskidConfiguration.m#L61-L72)

### 3. Database Execution Engine

The `MikrusDatabase` and `BeskidDatabase` run execution helper methods to
prepare SQL statements, bind arguments via `ATProtoDBBindParams`, step rows, and
fetch column values using `ATProtoDBColumnValue`.

- **`executeQuery:params:error:`** and
  **`executeUpdate:params:connection:error:`**: Identical logic that converts
  SQL statement outputs to a standard `NSArray<NSDictionary *>` representation.
  Found in:
  - [MikrusDatabase.m](file:///Users/jack/Software/garazyk/Garazyk/Sources/Mikrus/MikrusDatabase.m#L627-L688)
  - [BeskidDatabase.m](file:///Users/jack/Software/garazyk/Garazyk/Sources/Beskid/BeskidDatabase.m#L395-L456)

### 4. XRPC Route Packs

The HTTP routers handle incoming parameters, serialize responses, and assert
caller constraints.

- **Rate-Limit Auditing**: `checkRateLimitForRequest:response:` query checker
  that interacts with the `RateLimiter` singleton to return a standard
  `TooManyRequests` payload. Found in:
  - [MikrusXrpcRoutePack.m](file:///Users/jack/Software/garazyk/Garazyk/Sources/Mikrus/MikrusXrpcRoutePack.m#L51-L65)
  - [BeskidXrpcRoutePack.m](file:///Users/jack/Software/garazyk/Garazyk/Sources/Beskid/BeskidXrpcRoutePack.m#L61-L75)

- **Identity Parsing**: `handleFromDocument:`, `pdsEndpointFromDocument:`, and
  `signingKeyFromDocument:` extract specific properties from DID documents
  (`alsoKnownAs`, `service`, `verificationMethod`). Found in:
  - [MikrusXrpcRoutePack.m](file:///Users/jack/Software/garazyk/Garazyk/Sources/Mikrus/MikrusXrpcRoutePack.m#L401-L443)
  - [BeskidXrpcRoutePack.m](file:///Users/jack/Software/garazyk/Garazyk/Sources/Beskid/BeskidXrpcRoutePack.m#L555-L574)

# Refactoring Inventory Matrix: Mikrus, Beskid, and Syrena

This inventory maps matching capabilities, duplicate logic, and similar
boilerplate across Mikrus, Beskid, and Syrena. Exact duplication is called out
separately from related implementation patterns.

## Core Capability Comparison

| Feature / Domain              | Mikrus                                   | Beskid                                   | Syrena (AppView)                                              | Implementation State                                                                                         |
| ----------------------------- | ---------------------------------------- | ---------------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Signal setup                  | `GZSignalManager`                        | `GZSignalManager`                        | `GZSignalManager` plus custom exception/SIGABRT handlers      | Shared primitive, different lifecycle details                                                                |
| Crash reporting               | `GZCrashReporter`                        | `GZCrashReporter`                        | `GZCrashReporter` plus uncaught exception/SIGABRT diagnostics | Shared primitive, Syrena has extra behavior                                                                  |
| Linux category check          | Category link function                   | Category link function                   | Category link function plus runtime selector assertion        | Syrena-specific guard must stay                                                                              |
| CLI parser                    | `parse_options`                          | `parse_options`                          | `parse_appview_options`                                       | Similar scanner loops, different option sets                                                                 |
| Configuration model           | `MikrusConfiguration`                    | `BeskidConfiguration`                    | `AppViewConfiguration`                                        | Similar loading shape; not identical                                                                         |
| IP rate-limit config          | Yes                                      | Yes                                      | No equivalent in `AppViewConfiguration`                       | Shared only between Mikrus/Beskid                                                                            |
| SQLite connection             | `ATProtoConnectionManagerPooled`         | `ATProtoConnectionManagerPooled`         | raw `sqlite3_open_v2` with serialized queue                   | AppView is a separate concurrency migration                                                                  |
| WAL/pragma setup              | Managed by connection manager            | Managed by connection manager            | Direct `ATProtoDBConfigurePragmas`                            | Partially shared through `Database/Utils`                                                                    |
| DB query helpers              | `executeQuery:params:error:`             | `executeQuery:params:error:`             | `executeParameterizedQuery:params:error:`                     | Exact pattern in Mikrus/Beskid; AppView is similar but distinct                                              |
| DB update helpers             | `executeUpdate:params:connection:error:` | `executeUpdate:params:connection:error:` | `executeParameterizedUpdate:params:error:`                    | Exact pattern in Mikrus/Beskid; AppView is similar but distinct                                              |
| Local identity cache          | `mikrus_handles`                         | `beskid_identities`                      | `handles` and relevance tables                                | Shared concept, separate schemas                                                                             |
| HTTP parameter validation     | duplicated helper                        | duplicated helper                        | mostly inline or generic handler-local checks                 | Shared helper opportunity                                                                                    |
| HTTP rate-limit response      | duplicated route helper                  | duplicated route helper                  | handled elsewhere                                             | Exact Mikrus/Beskid duplication; `RateLimiter` already exposes header helpers                                |
| DID document field extraction | local helper methods                     | local helper methods                     | separate AppView/PDS helpers                                  | Wider duplication already exists in `Core/DID.m`, `XrpcIdentityHelper.m`, `XrpcRepoPack.m`, and related code |
| Network read-through          | `fetchRemoteRecord...`                   | `fetchAndCacheRemoteRecord...`           | backfill/write proxy paths                                    | Similar concerns, not a first extraction target                                                              |

## Detailed Duplication Breakdown

### 1. Entrypoint Bootstrap

All three binaries install ignored signals, install crash handlers, call
`curl_global_init` under GNUstep, force-link the `NSDateFormatter+ATProto`
category, parse command-line options, apply configuration overrides, start a
runtime, and install SIGINT/SIGTERM handlers.

Evidence:

- `Garazyk/Binaries/mikrus/main.m`
- `Garazyk/Binaries/beskid/main.m`
- `Garazyk/Binaries/syrena/main.m`

Important correction: Syrena is not just a copy of the Mikrus/Beskid lifecycle.
It also registers an uncaught exception handler, a SIGABRT backtrace handler,
and a Linux category selector assertion. A lifecycle helper must allow
service-specific hooks before and after common setup.

### 2. CLI Option Parsing

The three binaries maintain manual array-scanning parsers:

- Mikrus accepts `--port`, `--relay`, `--data-dir`, `--config`, `--no-ingest`,
  and verbosity flags.
- Beskid accepts `--port`, `--data-dir`, `--config`, and verbosity flags.
- Syrena accepts those plus AppView-specific partial/backfill options and a
  `status` command.

This is a good secondary refactor candidate because it can be tested without
starting services. It should be schema-driven and command-aware rather than a
one-off shared loop.

### 3. Configuration Loading

Mikrus and Beskid have close duplication in defaults, environment overrides,
dictionary loading, and `uint16_t` port validation. AppView shares the general
shape but has a larger configuration surface and currently accepts port values
through `integerValue` without the same dictionary-side `UINT16_MAX` validation.

Existing related code:

- `Garazyk/Sources/MediaCore/ATProtoMediaServiceConfiguration.m` already has
  prefix-based environment helpers (`envInt`, `envDouble`, `envBool`).
- `Garazyk/Sources/App/ATProtoServiceConfiguration.[hm]` is a much larger
  PDS-specific configuration object and should not be made a parent of these
  services.

Refactor implication: start with small parsing utilities rather than
inheritance.

### 4. Database Execution Helpers

Mikrus and Beskid duplicate the same SQLite execution structure:

- `executeQuery:params:error:` prepares a statement through the connection
  manager, binds params with `ATProtoDBBindParams`, collects rows with
  `ATProtoDBColumnValue`, finalizes manually, and returns
  `NSArray<NSDictionary *>`.
- `executeUpdate:params:connection:error:` prepares and steps an update on an
  existing transaction connection.
- `performWriteTransaction:error:` wraps `connectionManager transact:`.

Evidence:

- `Garazyk/Sources/Mikrus/MikrusDatabase.m`
- `Garazyk/Sources/Beskid/BeskidDatabase.m`

Important correction: these methods are structurally identical but use
service-specific error helpers (`MikrusDBError`, `BeskidDBError`). A shared
runner must preserve error domains and row null semantics.

### 5. AppView Database Similarity

AppView implements `executeParameterizedQuery:params:error:` and
`executeParameterizedUpdate:params:error:` with the same low-level primitives,
but the execution context differs:

- raw `_db` connection,
- serialized `safeExecuteSync`,
- `PDS_SQLITE_AUTORELEASE_STMT`,
- different null handling (AppView omits null values where Mikrus/Beskid store
  `[NSNull null]`).

This supports a later AppView cleanup, but it should not be bundled with the
first Mikrus/Beskid query-runner extraction.

### 6. XRPC Route Helpers

Mikrus and Beskid duplicate:

- `checkRateLimitForRequest:response:`
- `requiredParam:request:response:`
- invalid request and database error response helpers
- DID document field helpers such as handle, PDS endpoint, and signing key
  extraction

Existing related code already covers part of this:

- `XrpcErrorHelper` centralizes error response construction.
- `RateLimiter` exposes rate-limit header helpers.
- `Core/DID.m`, `XrpcIdentityHelper.m`, `XrpcRepoPack.m`,
  `AppViewIdentityHelper.m`, and `VideoJWTAuthProvider.m` contain overlapping
  DID document field extraction.

Refactor implication: split route support from DID document parsing. A single
`GZXrpcHelper` class would become too broad if it owns rate limiting, query
params, error responses, and identity parsing.

# Refactoring Audit Skill Notes: Mikrus, Beskid, and Syrena

These notes capture caveats from the review pass.

## 1. SQLite Connection Managers

The first extraction should depend on `<ATProtoConnectionManager>`, not
`ATProtoConnectionPool`. Mikrus and Beskid already use the manager interface,
which lets a query runner stay agnostic to pooled versus serialized access.

Do not include AppView in the first pass. AppView uses raw `_db` plus
`safeExecuteSync`, and changing that is a concurrency migration.

## 2. Statement Finalization

Use `PDS_SQLITE_AUTORELEASE_STMT` in the shared runner. Mikrus and Beskid
currently finalize manually; AppView and much of the PDS code already use the
cleanup macro. The runner is a good place to make finalization consistent
without touching every caller.

## 3. Row Null Semantics

Mikrus and Beskid store `[NSNull null]` for SQLite null columns. AppView omits
null-valued columns. A shared runner must preserve the Mikrus/Beskid behavior
during phase 1. If AppView later uses the runner, make null handling an explicit
option or adapter.

## 4. Error Domains

The duplicated database helpers are not fully service-neutral because they map
SQLite failures into service domains (`MikrusDatabaseErrorDomain`,
`BeskidDatabaseErrorDomain`). The query runner should accept an error domain or
an error-factory block.

## 5. Existing XRPC Helpers

Do not create a new all-purpose XRPC helper that duplicates existing
infrastructure. The repo already has:

- `XrpcErrorHelper` for standard JSON error bodies.
- `RateLimiter` helpers for rate-limit headers.
- `XrpcMiddleware` for route middleware patterns.
- `XrpcIdentityHelper` and `Core/DID` logic for identity resolution and DID
  document parsing.

The route helper should be narrow and should delegate to these where possible.

## 6. DID Document Shape Compatibility

DID field extraction must preserve both current and legacy shapes:

- current `verificationMethod` array entries with `publicKeyMultibase`,
- legacy PLC-style `verificationMethods` dictionaries,
- `alsoKnownAs` entries with and without `at://`,
- trailing slash handling for handles.

This matters because Mikrus, Beskid, PDS repo import, AppView identity helpers,
and video auth each carry related parsing logic.

## 7. Objective-C Category Verification

Syrena has a Linux/GNUstep category selector assertion for
`NSDateFormatter+ATProto`. Any lifecycle helper must preserve this check and the
explicit category link call. Do not hide it behind a helper that could be
optimized out or skipped.

## 8. Configuration Refactor Boundary

Configuration extraction should start with parsing utilities, not a parent
class. `MikrusConfiguration`, `BeskidConfiguration`, and `AppViewConfiguration`
share parsing mechanics, but their properties and validation rules differ.

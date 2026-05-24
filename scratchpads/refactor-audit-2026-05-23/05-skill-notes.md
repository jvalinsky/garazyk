# Refactoring Audit Skill Notes: Mikrus, Beskid, and Syrena

This document outlines key technical takeaways, environment caveats, and tips
gathered during the refactor audit process of **Mikrus**, **Beskid**, and
**Syrena (AppView)**.

## 1. Concurrency Safety and Connection Managers

- **Takeaway**: When refactoring SQLite helper wrappers, ensure that they rely
  entirely on the `<ATProtoConnectionManager>` interface rather than direct
  references to `ATProtoConnectionPool`.
- **Why it matters**: `ATProtoConnectionManager` isolates the query runner from
  having to know whether the underlying database is pooled
  (`ATProtoConnectionManagerPooled`) or serial
  (`ATProtoConnectionManagerSerial`). This opens the door to bringing
  `AppViewDatabase` under the connection-pool umbrella safely in a future phase.

## 2. PDS_SQLITE_AUTORELEASE_STMT compiler cleanup

- **Takeaway**: Ensure that all extracted SQLite helper methods utilize the
  `PDS_SQLITE_AUTORELEASE_STMT` compiler macro where appropriate.
- **Why it matters**: It mitigates statement leaks under GNUstep and macOS,
  guaranteeing that if an early return occurs (e.g. during step checks or column
  parsing), `sqlite3_finalize` is reliably invoked without cluttering methods
  with multiple verbose `sqlite3_finalize` calls.

## 3. Objective-C Category Verification

- **Takeaway**: Category methods (like `NSDateFormatter+ATProto`) are vulnerable
  to linker stripping on Linux/GNUstep if the linker flags `-ObjC` or
  `-force_load` are not correctly configured.
- **Why it matters**: Syrena's startup logic contains a vital assert:
  ```objc
  if (![NSDateFormatter respondsToSelector:NSSelectorFromString(@"atproto_dateFromString:")]) { ... }
  ```
  Any refactor that impacts how entrypoint headers or categories are loaded must
  preserve this check, preventing runtime `unrecognized selector sent to class`
  crashes.

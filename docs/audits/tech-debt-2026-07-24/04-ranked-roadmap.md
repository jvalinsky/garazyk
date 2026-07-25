# Ranked Roadmap

This roadmap outlines the prioritized sequence of refactors based on the risk scores and deep dives.

> **Update (2026-07-24):** After manual verification, all items in Phases 1 and 2 were found to be **False Positives** from the heuristic scanners. The codebase is already secured with prepared statements, safe string comparisons, and explicit backpressure limits.

## Phase 1: Critical Security Primitives (Verified Safe)
1. **Constant-Time String Comparison:**
   - *Status: No action needed.* Flagged `isEqualToString:` usages were for public identifiers (DIDs, keys) and non-secret constants.

2. **SQL Injection Hardening (Prepared Statements):**
   - *Status: No action needed.* Flagged `IN (%@)` strings are safely populated via `sqlPlaceholders()` which generates the correct number of `?` parameters before binding.

## Phase 2: Reliability and Concurrency (Verified Safe)
3. **Firehose Backpressure Implementation:**
   - *Status: No action needed.* `SubscribeReposHandler.m` already implements `maxPendingSendsPerConnection` and `maxPendingBytesPerConnection`.

4. **Locking Imbalances & Re-entrancy:**
   - *Status: No action needed.* The scanner incorrectly flagged `__block` variables and `UsingBlock:` as locks. There are no imbalances.

## Phase 3: Cleanup
5. **Database Migration Formatting:**
   - *Status: Verified safe.* String formatting in `PDSMigrationManager.m` is used for static table whitelisting, which cannot be parameterized in SQLite.

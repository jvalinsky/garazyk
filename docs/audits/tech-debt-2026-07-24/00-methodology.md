# Methodology

This technical debt audit was generated on 2026-07-24.

## Goals
The objective is to find and rank refactoring opportunities without immediately changing implementation code, and to produce a roadmap based on evidence gathered from automated architecture, concurrency, and security scans.

## Tools Used
- `run_architecture_audit.sh`
- `run_concurrency_audit.sh`
- `run_all_security_scans.sh`

## Evaluation Dimensions
Candidates were evaluated based on the following criteria:
- **Boundary Risk:** Security vulnerabilities, unauthorized access, or improper SQL formatting.
- **Structural Drag:** Missing invariants or unhandled edge cases (e.g., missing SQL prepare/finalize).
- **Test Leverage:** Availability of tests for characterization.
- **Change Safety:** How risky it is to modify the candidate.
- **Refactor Payoff:** System stability, security, or performance improvements.

## Post-Audit Verification (2026-07-24)
Upon attempting to implement the refactors outlined in the roadmap, it was discovered that the heuristic scanners produced **false positives** for all three major areas:
1. **SQL Injection:** The `IN (%@)` instances were actually powered by a safe `sqlPlaceholders` function that generates parameterized `?` strings, which are then properly bound via `executeParameterizedUpdate`.
2. **Timing Attacks:** The `isEqualToString:` and `memcmp` usages flagged were comparing public DIDs, token types (e.g., "EC", "P-256"), or CBOR data, none of which are sensitive secrets vulnerable to timing attacks.
3. **Concurrency/Locking:** "Lock imbalances" flagged were actually regex matches on Objective-C `__block` variables and `UsingBlock:` methods. Furthermore, Firehose backpressure is already fully implemented via `maxPendingSendsPerConnection` dropping slow consumers.

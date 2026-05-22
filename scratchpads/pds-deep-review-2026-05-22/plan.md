# PDS Deep Code Review Plan

## Goal

Perform a repository-grounded review of the PDS implementation for inefficient and insecure code.

## Review Scope

- PDS request routing and XRPC handlers.
- Authentication, OAuth, sessions, token handling, and signing paths.
- Account registration, identity, PLC, and repository mutation paths.
- Blob upload/storage and media validation.
- SQLite database, migrations, pooling, transactions, and cache behavior.
- Federation, sync, firehose, and network boundary behavior where it affects PDS safety or resource use.

## Research Questions

- Which externally reachable entry points lack authorization, input validation, size limits, rate limits, or timeouts?
- Which storage paths use dynamic SQL, unsafe path construction, weak transaction discipline, or unbounded scans?
- Which crypto/session paths leak secrets, use weak primitives, or mishandle token lifetimes?
- Which hot paths do avoidable O(n), blocking, or unbounded work under attacker-controlled input?
- Which findings are high-confidence enough to file or fix immediately?

## Evidence Plan

- Run local scanner suites from `.agents/skills/objc-security-audit` and `.agents/skills/objc-architecture-audit`.
- Inventory relevant Objective-C implementation files and tests.
- Use `rg` patterns for risky APIs: `sqlite3_exec`, string SQL formatting, token logging, path construction, file reads/writes, unbounded JSON/body parsing, network calls, locks, and cache growth.
- Manually read the highest-risk files before accepting scanner output as findings.
- Keep tentative notes in `findings.md`; only move confirmed issues to the report.

## Output

- Final report: `docs/reports/pds-deep-code-review-2026-05-22.md`
- Temporary evidence: `scratchpads/pds-deep-review-2026-05-22/findings.md`
- Scanner outputs: `scratchpads/pds-deep-review-2026-05-22/scans/`

# Documentation Review Session Scratchpad - 2026-04-25

## Active Review Tasks

| Task ID | Target Document | Auditor Agent | Focus Area | Status |
|---------|-----------------|---------------|------------|--------|
| T1 | `docs/04-network-layer/` | `architecture-auditor` | Moderation methods & registration order | Pending |
| T2 | `docs/11-reference/api-reference.md` | `atproto-coverage-auditor` | API parity (putRecord/updateRecord) | Pending |
| T3 | `docs/05-database-layer/` | `architecture-auditor` | SQLite schema accuracy (Schema.m) | Pending |
| T4 | `docs/10-tutorials/` | `general` | Method signatures & testing methodology | Pending |

## Preliminary Findings (from DOCUMENTATION_ACCURACY_REVIEW.md)
- Missing `XrpcModerationMethods`.
- Registration order mismatch in `method-registry.md`.
- Flawed tutorial testing methodology (long-running server issue).
- Tutorial 1 signature mismatch (`initWithConfiguration`).
- Schema naming/type mismatches (`users` vs `accounts`).

## Proposed Revisions
(To be populated by subagent results)

---
name: objc-sql-injection-deep-audit
description: "Audit Objective-C SQLite database code for SQL injection vulnerabilities beyond basic pattern matching. Use when reviewing database query construction, dynamic SQL, raw query execution, or any code that builds SQL strings from user input."
---

# Objective-C SQL Injection Deep Audit

Use this skill to find SQL injection vulnerabilities in Objective-C SQLite codebases.

## Quick start
1. Run:
```bash
./skills/objc-sql-injection-deep-audit/scripts/scan_sql_injection.sh . /tmp/objc-sql-injection-deep-audit
```
2. Read `/tmp/objc-sql-injection-deep-audit/summary.md`.
3. Validate candidates with `references/sql-injection-checklist.md`.

## Workflow
1. Map all SQL execution points (`sqlite3_exec`, `executeQuery`).
2. Identify string formatting/concatenation in SQL context.
3. Trace data flow from user input to SQL execution.
4. Verify parameterized queries are used correctly.
5. Check dynamic table/column names for injection.

## Triage priorities
- P0: User input directly concatenated into SQL.
- P1: Dynamic SQL construction with string formatting.
- P2: Missing input validation before SQL operations.
- P3: Indirect injection via configuration or file paths.

## Fix patterns
- Use parameterized queries (`sqlite3_bind_*`) for all user input.
- Whitelist allowed table/column names for dynamic SQL.
- Apply input validation before SQL context.
- Never trust `PRAGMA` values from user input.
- Use `PDSInputValidator.sanitizeSQLInput` as defense-in-depth.

## Resources
- Script: `scripts/scan_sql_injection.sh`
- Reference: `references/sql-injection-checklist.md`

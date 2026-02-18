# Log Redaction Checklist

Use this checklist while validating candidates from `scan_log_redaction.sh`.

## Sensitive classes
- Credentials and tokens (`access`, `refresh`, bearer, cookie).
- Cryptographic material or proof payloads.
- User identifiers and potentially sensitive personal fields.

## Logging behavior
- Verify sensitive values are never logged raw.
- Verify redaction is centralized and consistent.
- Verify debug-level logs do not bypass redaction helpers.

## Error and network paths
- Verify request/response dumps redact headers and bodies.
- Verify exception logs do not include secret-bearing objects.
- Verify auth failures do not echo secrets in diagnostics.

## Regression safety
- Add tests for redaction helper behavior.
- Add policy checks in code review for new log statements.
- Prefer structured logging fields with explicit redaction tags.

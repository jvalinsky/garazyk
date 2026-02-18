# Service Boundary Checklist

Use this checklist while validating candidates from `scan_service_boundaries.sh`.

## Entry-point authorization
- Verify each privileged service operation enforces authz explicitly.
- Verify caller identity is derived from trusted session context.
- Verify denied paths fail closed with no side effects.

## Input trust and validation
- Verify actor/repo identifiers are validated before mutation.
- Verify role and scope checks match operation sensitivity.
- Verify admin-only paths cannot be reached by normal callers.

## Consistency and regression safety
- Verify similar operations share common authz logic.
- Add negative tests for unauthorized, malformed, and cross-tenant attempts.
- Ensure audit logs capture denied privileged attempts without leaking secrets.

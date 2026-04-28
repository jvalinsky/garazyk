---
name: better-code-security-design
description: "Proactive security design: Sink Prevention, Source-to-Sink Tracing, and Safe Primitives."
---

# Better Code: Security Design

This skill focuses on preventing vulnerabilities at the architectural level rather than just finding them during audits.

## Proactive Defense

### 1. Sink Prevention
A "Sink" is a dangerous operation (e.g., executing SQL, writing to memory, network requests).
- **Rule**: Never allow raw user input to reach a sink.
- **Strategy**: Build **Safe Primitives**. Instead of a function that takes a raw SQL string, build a `PDSSqlQuery` object that only accepts bound parameters.

### 2. Source-to-Sink Tracing
When reviewing code, trace the path of untrusted data.
- **Source**: Where data enters (e.g., XRPC endpoint, file read, user input).
- **Sink**: Where data is used dangerously.
- **Validation Chain**: Identify where data is transformed, sanitized, or validated. If the chain is broken or missing, it's a P0 vulnerability.

### 3. Parse, Don't Sanitize
Sanitization (removing "bad" characters) is fragile. 
- **Preferred**: Parse the input into a structured, validated object.
- If the parsing fails, the data is rejected immediately at the boundary.

## Common Sink Patterns & Fixes

| Sink Type | Danger | Better Code Fix |
|-----------|--------|-----------------|
| `sqlite3_exec` | SQL Injection | Use `sqlite3_bind_*` or `PDSSqliteQuery`. |
| `dispatch_async` | Race Conditions | Use serial queues for resource access. |
| `NSData` (Raw) | Buffer Overflows | Use typed CBOR/JSON parsers with bounds checks. |
| `NSLog` | Token Leakage | Use `PDSLogRedactor` for sensitive identifiers. |

## Exploitation Discipline
A finding is only a vulnerability if it is:
1. **Reachable**: An attacker can trigger the path.
2. **Triggerable**: The validation chain fails to stop the malicious payload.

When fixing, always fix the **Root Cause** (the lack of a safe primitive) rather than just patching the specific instance.

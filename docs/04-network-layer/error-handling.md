---
title: Error Handling
---

# Error Handling

`XrpcErrorHelper` provides a standardized interface for common XRPC and HTTP failures. This consistency ensures that clients and protocol explorers receive predictable error shapes.

## Standard Error Format

The helper standardizes responses using the expected AT Protocol JSON structure:

```json
{
  "error": "InvalidRequest",
  "message": "Detailed description of the failure"
}
```

Standardizing these responses at the transport layer simplifies client-side parsing and automated testing.

## Common Error Cases

The helper covers the most frequent failure classes:

- **Authentication**: `AuthenticationRequired`, `InvalidToken`.
- **Authorization**: `Forbidden`, `InsufficientPrivileges`.
- **Validation**: `InvalidRequest`, `LexiconNotFound`.
- **Resource Management**: `NotFound`, `AccountNotFound`.
- **Transport**: `MethodNotAllowed`, `InternalServerError`.

## Method Management

When a `MethodNotAllowed` error is issued, the helper automatically attaches the `Allow` header to the response. This provides clients with immediate feedback on the supported HTTP methods for the requested path.

## Usage Guidelines

`XrpcErrorHelper` should be the default choice for standard transport and authorization failures.

Handlers should use the helper when:
- The failure matches a common protocol error class.
- A bespoke response payload is not required by the lexicon.
- Consistency across the API is a priority.

For errors requiring specific lexicon-defined shapes or complex metadata, handlers may construct custom response objects.

## Related

- [Auth Helpers](./auth-helpers)
- [XRPC Dispatch](./xrpc-dispatch)
- [API Reference](../11-reference/api-reference)
- [Troubleshooting](../11-reference/troubleshooting)
- [Documentation Map](../11-reference/documentation-map.md)


---
title: Error Handling
---

# Error Handling

## Overview

`XrpcErrorHelper` exists to keep common XRPC failures predictable. The goal is
not to eliminate every custom error in the codebase. The goal is to make the
most common transport-level failures consistent enough that contributors and
clients can reason about them quickly.

## The Standard Error Shape

The helper standardizes responses around this JSON shape:

```json
{
  "error": "InvalidRequest",
  "message": "Human-readable description"
}
```

That format matters because many request failures are handled before a service
ever runs. A stable transport-level shape keeps parsing and testing simple.

## Common Helper Cases

The current helper covers the most common XRPC failure classes:

- authentication required
- authorization failure
- invalid request
- not found
- internal server error
- method not allowed
- a few convenience cases such as account or lexicon not found

This is the right level of abstraction for a shared network-layer helper. It
standardizes the recurring cases without pretending every endpoint-specific
domain error should look identical.

## Why `MethodNotAllowed` Is Special

The method-not-allowed helper also sets the `Allow` header. That small detail is
important because it turns an error response into something a client or
contributor can act on immediately.

It is a good example of why shared error helpers exist at all: the right
transport behavior is easy to forget when every route authors its own response
by hand.

## What The Helper Does Not Cover

Not every runtime error flows through `XrpcErrorHelper`. Some handlers still
emit custom errors because they need endpoint-specific status, lexicon-shaped
messages, or protocol-specific behavior.

That is fine. The docs should describe the helper as the standard path for
common XRPC failures, not as the only error path in the repository.

## When To Use The Helper

Use the helper when:

- the failure is a standard transport or authorization case
- the endpoint does not need a bespoke payload shape
- consistency across handlers is more important than local customization

Do not use it to hide a domain-specific error that callers actually need to
distinguish.

## Related Reading

- [Auth Helpers](./auth-helpers)
- [API Reference](../11-reference/api-reference)
- [Troubleshooting](../11-reference/troubleshooting)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)


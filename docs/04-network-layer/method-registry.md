---
title: Method Registry
---

# Method Registry

## Overview

`XrpcMethodRegistry` defines the public XRPC surface using domain-specific registration helpers. It maps service dependencies to registered NSIDs.

## Responsibilities

The registry determines:

- The NSIDs available in the runtime.
- The domain module responsible for each method.
- The service dependencies required for registration.
- The method families wired during startup.

The registry is part of the application boot sequence, not just a lookup table.

## Registration Order

Registration order determines how `XrpcDispatcher` handles overlapping NSIDs. `XrpcMethodRegistry.m` follows this sequence:

1. **XrpcServerMethods** (`com.atproto.server.*`)
2. **XrpcIdentityMethods** (`com.atproto.identity.*`)
3. **XrpcRepoMethods** (`com.atproto.repo.*`)
4. **XrpcSyncMethods** (`com.atproto.sync.*`)
5. **XrpcAppBskyMethods** (`app.bsky.*`)
6. **XrpcAdminMethods** (`com.atproto.admin.*`)
7. **XrpcLabelMethods** (`com.atproto.label.*`)
8. **XrpcModerationMethods** (`com.atproto.moderation.*`)

## Why This Matters

Endpoint behavior may fail in the live runtime even if unit tests pass. The registry helps identify:

- Unregistered methods.
- Broken dependencies within a domain family.
- The registration module responsible for an auth or dispatch issue.

The registry confirms whether an endpoint is missing, miswired, or failing later in the stack.

## Boundaries

The registry does not define endpoint semantics. It is not the place to debug:

- record validation.
- JWT or DPoP proof verification.
- repository commit construction.
- blob provider behavior.

These reside in the domain module and service layer.

## When To Read The Deep Dives

Use the registry docs for the static map. Use the deep dives when you need the live request path from route to service call.

## Related Deep Dives

- [HTTP Request and Route Pipeline](./http-request-and-route-pipeline)
- [From NSID to Service Call](./from-nsid-to-service-call)

## Related Reading

- [XRPC Dispatch](./xrpc-dispatch)
- [Domain Methods](./domain-methods)
- [Services Overview](../03-application-layer/services-overview)
- [Startup and Boot Sequence](../01-getting-started/startup-and-boot-sequence)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)


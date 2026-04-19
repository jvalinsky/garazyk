---
title: Method Registry
---

# Method Registry

## Overview

`XrpcMethodRegistry` assembles the public XRPC surface from domain-specific registration helpers. It is the place where the codebase turns service and controller dependencies into a concrete set of registered NSIDs.

## What The Registry Owns

Treat the registry as the answer to these questions:

- which NSIDs exist in this runtime
- which domain module registered each method
- what service dependencies must be present for registration to succeed
- which shared method families are wired during startup

That makes it more than a lookup table. It is part of the application boot sequence.

## Why Registration Order Matters

Endpoint behavior can look correct in unit tests and still disappear from the live runtime if registration changes. The registry matters because:

- an unregistered method is indistinguishable from a missing feature to the caller
- dependency drift can break one domain family while leaving others intact
- auth and dispatch bugs are easier to localize once you know the owning registration module

In practice, the registry is where contributors confirm whether an endpoint is missing, miswired, or simply failing later in the stack.

## What It Does Not Own

The registry does not implement the endpoint semantics themselves. It should not be the main place you debug:

- record validation logic
- JWT or DPoP proof verification
- repository commit construction
- blob provider behavior

Those concerns live in the owning domain module and service layer.

## When To Read The Deep Dives

Use the registry docs for the static map. Use the deep dives when you need the live request path from route to service call.

## Related Deep Dives

- [HTTP Request and Route Pipeline](./http-request-and-route-pipeline)
- [From NSID to Service Call](./from-nsid-to-service-call)

## Related Reading

- [XRPC Dispatch](./xrpc-dispatch)
- [Domain Methods](./domain-methods)
- [Services Overview](../03-application-layer/services-overview)
- [Startup and Boot Sequence](../01-getting-started/startup-and-boot-sequence)\n\n## Related\n\n- [Documentation Map](../11-reference/documentation-map.md)\n- [Contributor Guide](../index.md)\n- [Repository Documentation Index](../repo-index/index.md)\n\n
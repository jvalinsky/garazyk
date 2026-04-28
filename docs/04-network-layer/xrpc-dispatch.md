---
title: XRPC Dispatch
---

# XRPC Dispatch

## Overview

XRPC dispatch adapts transport requests to application logic. After a request matches the `/xrpc/*` route, this layer resolves the NSID, applies handling rules, and invokes the domain method.

## Responsibilities

This layer determines:

- The NSID mapped to the request path.
- Whether the NSID is registered.
- How auth, validation, and protocol errors apply.
- How the handler result translates to an HTTP response.

It serves as the seam between request arrival and service execution.

## Boundaries

Dispatch does not define:

- repository mutation rules.
- blob-storage policy.
- account lifecycle semantics.
- PLC or identity resolution.

If the request reaches the correct handler but produces the wrong result, the issue likely resides below dispatch.

## Why NSID Mapping Matters

In Garazyk, contributors often interact with the codebase by endpoint name first. That makes dispatch and registration the fastest way to answer:

- is this endpoint even exposed?
- which module registered it?
- does the failure happen before or after service code runs?

That distinction is the difference between debugging a registration bug and debugging a service bug.

## When To Start Here

Start with XRPC dispatch when:

- the endpoint returns 404 or "method not found"
- auth or validation fails before the service should run
- the wrong handler appears to own the request
- the response shape looks like protocol glue, not business logic

## Related Deep Dives

- [HTTP Request and Route Pipeline](./http-request-and-route-pipeline)
- [From NSID to Service Call](./from-nsid-to-service-call)

## Related Reading

- [Method Registry](./method-registry)
- [Domain Methods](./domain-methods)
- [Auth Helpers](./auth-helpers)
- [Request Lifecycle](../01-getting-started/request-lifecycle)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)


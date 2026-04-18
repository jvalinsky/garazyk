---
title: XRPC Dispatch
---

# XRPC Dispatch

## Overview

XRPC dispatch is the protocol adapter between transport and application behavior. Once a request reaches the `/xrpc/*` route family, this layer is responsible for resolving the NSID, applying shared request handling rules, and invoking the registered domain method.

## What Dispatch Owns

This layer is where the runtime answers:

- which NSID the request path maps to
- whether that NSID is registered at all
- how shared auth, validation, and protocol errors are applied
- how the handler result becomes an HTTP response

That makes it the seam between "the request arrived" and "the service is doing work."

## What Dispatch Does Not Own

Dispatch is not where the domain behavior lives. It should not be the place that explains:

- repository mutation rules
- blob-storage policy
- account lifecycle semantics
- PLC or identity resolution behavior

If a request reaches the right handler and the result is still wrong, the bug usually lives below dispatch.

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

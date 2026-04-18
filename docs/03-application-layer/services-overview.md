---
title: Services Overview
---

# Services Overview

## Overview

The service layer is where Garazyk turns protocol requests into application
work. New contributors should understand this layer early because it explains
why the codebase is not organized around one giant controller anymore.

`PDSApplication` is the composition root. It configures shared infrastructure,
builds the core services, wires HTTP routes, and keeps a compatibility facade
around `PDSController` for older call sites.

## Why Services Exist

The service split keeps three concerns separate:

- handlers parse requests and shape responses
- services coordinate business logic
- storage, repository, and database code own persistence details

That split makes it much easier to test, reason about, and replace one part of
the stack without rewriting the rest.

## The Current Service Composition

At startup, `PDSApplication` builds shared infrastructure first:

- configuration
- logging
- rate limiting
- service databases
- user database pool
- JWT infrastructure

It then builds the application services and adjacent controllers:

- account service
- record service
- blob service
- repository service
- admin controller
- subscribeRepos handler
- relay service

This order matters because most services depend on the database pools, config,
or auth infrastructure being ready first.

## The Typical Request Path

Most HTTP or XRPC work follows the same shape:

1. route registration in the HTTP builder or XRPC layer
2. auth and validation in helpers or handlers
3. service call for the owning business operation
4. repository, database, or storage work
5. response shaping back at the handler layer

That path is more useful to memorize than the exact file layout because it tells
you where to look when behavior is wrong.

## `PDSController` Is A Compatibility Layer

`PDSController` still exists, but the repo explicitly treats it as a legacy
facade over `PDSApplication` and the service layer. New code should call the
services directly unless it is intentionally extending an older compatibility
surface.

This is one of the most important contributor guidelines in the tree. Many docs
became confusing because they described `PDSController` as if it were still the
preferred architecture.

## When To Add A Service

Add or extend a service when the behavior:

- spans multiple handlers or protocols
- coordinates more than one persistence concern
- needs a testable boundary that is not tied to HTTP

Do not add a service just to wrap one trivial helper. The point of the service
layer is to create meaningful seams, not more indirection.

## Related Reading

- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [Deep Dive: Runtime Flow](./runtime-flow-walkthrough)
- [Blob Service](./blob-service)
- [Repository Service](./repository-service)
- [Relay Service](./relay-service)
- [Auth Helpers](../04-network-layer/auth-helpers)

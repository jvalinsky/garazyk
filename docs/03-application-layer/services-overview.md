---
title: Services Overview
---

# Services Overview

## Overview

The service layer translates protocol requests into application logic. Understanding this layer explains why the codebase uses multiple services rather than a single large controller.

`PDSApplication` acts as the composition root. It configures shared infrastructure, builds core services, wires HTTP routes, and provides a compatibility facade around the legacy `PDSController`.

## Purpose

The service split separates three concerns:

- Handlers parse requests and shape responses.
- Services coordinate business logic.
- Storage and repository code manage persistence.

This split simplifies testing and replacement of individual stack components.

## Service Composition

At startup, `PDSApplication` builds shared infrastructure:

- configuration
- logging
- rate limiting
- service databases
- user database pool
- JWT infrastructure

It then builds application services and controllers:

- account service
- record service
- blob service
- repository service
- admin service (via controller)
- subscribeRepos handler
- relay service
- age assurance service
- chat moderation service

### Standalone Servers

The repository also implements standalone servers for global AT Protocol roles:

- **Syrena (AppView)**: Consumes the global firehose to build read-models.
- **Zuk (Relay)**: Aggregates data from multiple PDS instances.
- **Campagnola (PLC)**: A standalone directory server for `did:plc`.

Most services depend on the database pools, configuration, and authentication infrastructure.

## Request Path

Most HTTP or XRPC work follows this path:

1. Register routes in the HTTP builder or XRPC layer.
2. Perform authentication and validation in helpers.
3. Call the relevant service for the operation.
4. Execute repository, database, or storage work.
5. Shape the response in the handler layer.

This sequence identifies where to look when behavior is incorrect.

## PDSController Legacy

`PDSController` is a legacy facade over `PDSApplication`. New code should call services directly.

## Adding a Service

Add or extend a service when behavior:

- spans multiple handlers or protocols.
- coordinates multiple persistence concerns.
- requires a testable boundary independent of HTTP.

The service layer creates meaningful seams, not just indirection. Trivial helpers do not require their own service.

## Related Reading

- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [Deep Dive: Runtime Flow](./runtime-flow-walkthrough)
- [Syrena AppView Server](./appview-server)
- [Zuk Relay Server](./relay-server)
- [Trust, Safety, and Compliance](./safety-and-compliance)
- [Chat Service](./chat-service)
- [Blob Service](./blob-service)
- [Repository Service](./repository-service)
- [Relay Service](./relay-service)
- [Auth Helpers](../04-network-layer/auth-helpers)


## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)


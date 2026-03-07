---
title: HTTP Server
---

# HTTP Server

## Overview

`HttpServer` is the transport boundary for September. It accepts HTTP/1.1 requests, enforces request-size and timing limits, handles keep-alive behavior, and performs WebSocket upgrade handoff. It is the first runtime component in the request path, but it is not the place where ATProto semantics are decided.

## What This Layer Owns

Treat the HTTP server as the answer to these questions:

- can the runtime parse this request at all?
- did the request exceed header or body limits?
- does the path match a registered route family?
- should this connection stay HTTP or upgrade to WebSocket?
- can the runtime serialize and send the response back cleanly?

Those are transport questions, not protocol questions.

## What It Deliberately Does Not Own

The HTTP server does not decide:

- which NSID an XRPC request resolves to
- whether a token is valid for a domain method
- what a service should do with the request
- how repository or blob state is mutated

Those concerns move to dispatch, auth helpers, domain methods, and services after route selection succeeds.

## Why This Boundary Matters

A lot of debugging time gets lost by jumping into service code before confirming the request reached the correct route family. In this codebase, `HttpServer` and `PDSHttpServerBuilder` together answer whether the request can even arrive at the subsystem you think you are testing.

If the wrong handler is firing, or a WebSocket endpoint behaves differently from a normal HTTP endpoint, start here before reading business logic.

## Primary Runtime Seams

The main files worth knowing are:

- `ATProtoPDS/Sources/Network/HttpServer.m`
- `ATProtoPDS/Sources/Network/PDSHttpServerBuilder.m`

Read them together. The server owns connection behavior, while the builder owns which routes exist and in what order they are installed.

## Related Deep Dives

- [HTTP Request and Route Pipeline](./http-request-and-route-pipeline)
- [From NSID to Service Call](./from-nsid-to-service-call)

## Related Reading

- [XRPC Dispatch](./xrpc-dispatch)
- [Method Registry](./method-registry)
- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [Firehose Overview](../08-sync-firehose/firehose-overview)

---
title: HTTP Server
---

# HTTP Server

## Overview

`HttpServer` is the transport boundary for Garazyk. It implements a **Sans-I/O architecture**, separating protocol parsing logic from network socket operations. It accepts HTTP/1.1 requests, enforces request-size and timing limits, handles keep-alive behavior, and performs WebSocket upgrade handoff.

## What This Layer Owns

Treat the HTTP server and its session state machines as the answer to these questions:

- can the runtime parse this request at all? (`HttpProtocolSession`)
- did the request exceed header or body limits?
- does the path match a registered route family? (`PDSHttpServerBuilder`)
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

- `Garazyk/Sources/Network/HttpServer.m`
- `Garazyk/Sources/Network/PDSHttpServerBuilder.m`

Read them together. The server owns connection behavior, while the builder owns which routes exist and in what order they are installed.

## Advanced internals track

If you want the transport and parser walkthrough instead of the short reference
version of this page, continue to the tutorial subguide:

- [Subguide: HTTP + WebSocket from Scratch](../10-tutorials/network-from-scratch/)
- [Part 1: HTTP Transport and Parser](../10-tutorials/network-from-scratch/http-transport-and-parser)
- [Part 2: Routing, Pipelining, and Responses](../10-tutorials/network-from-scratch/http-routing-pipelining-and-responses)

## Related Deep Dives

- [HTTP Request and Route Pipeline](./http-request-and-route-pipeline)
- [From NSID to Service Call](./from-nsid-to-service-call)

## Related Reading

- [XRPC Dispatch](./xrpc-dispatch)
- [Method Registry](./method-registry)
- [Request Lifecycle](../01-getting-started/request-lifecycle)
- [Firehose Overview](../08-sync-firehose/firehose-overview)\n\n## Related\n\n- [Documentation Map](../11-reference/documentation-map.md)\n- [Contributor Guide](../index.md)\n- [Repository Documentation Index](../repo-index/index.md)\n\n
# Networking Layer Review

## Overview

This document presents a technical review of the networking layer in `ATProtoPDS`. The review focuses on the HTTP server implementation, XRPC dispatch mechanism, WebSocket support, and protocol compliance.

## Key Findings

### 1. Critical: Incomplete HTTP Body Reading
**Severity: Critical**
**File:** `Sources/Network/HttpServer.m`

The `HttpServer` currently buffers data only until the HTTP headers are received (indicated by `\r\n\r\n`). Once headers are found, it immediately attempts to parse the request using `HttpRequest`.

**Issue:**
- There is no logic to parse the `Content-Length` header and wait for the full body to be received.
- If the request body is split across multiple TCP packets (which is standard for any non-trivial POST/PUT), `HttpRequest` will be initialized with a partial or empty body.
- This effectively breaks `com.atproto.repo.uploadBlob` and any method accepting a JSON body larger than a single packet.

**Recommendation:**
- Implement a state machine in `HttpServer`:
  1.  Read until headers are complete.
  2.  Parse headers to find `Content-Length`.
  3.  Continue reading until `accumulated_body_length >= content_length`.
  4.  Only then instantiate `HttpRequest`.

### 2. Manual Multipart Parsing
**Severity: High**
**File:** `Sources/Network/HttpRequest.m`

The `parseMultipartFormData` method implements a custom manual parser for `multipart/form-data`.

**Issue:**
- Manual string/data searching is error-prone and inefficient for large files.
- It loads the entire multipart body into memory, which is a denial-of-service (DoS) risk for large blob uploads (e.g., 50MB video files).
- Boundary handling may be brittle (e.g., handling nested boundaries or boundaries that happen to appear in binary data, though the current implementation looks mostly correct by checking for CRLF).

**Recommendation:**
- For a production server, consider streaming the body to disk for large uploads.
- Ensure the parser strictly adheres to RFC 7578.

### 3. Hardcoded Authentication
**Severity: High**
**File:** `Sources/Network/XrpcMethodRegistry.m`

The `extractDIDFromAuthHeader` method currently returns a hardcoded DID (`did:plc:test123456789`) for any request with a "Bearer" token.

**Issue:**
- No actual token verification is performed.
- Any client sending `Authorization: Bearer whatever` acts as the test user.

**Recommendation:**
- Integrate the `Auth/JWT` logic (if available) or implement proper bearer token validation (verify signature, expiration, and scope).
- Middleware should handle auth before reaching the specific XRPC handlers.

### 4. WebSocket Sequence Numbers
**Severity: Medium**
**File:** `Sources/Sync/SubscribeReposHandler.m`

The `sequenceNumber` for the firehose is stored in an instance variable (`NSUInteger _sequenceNumber`) and initializes to 0 on startup.

**Issue:**
- If the server restarts, sequence numbers reset.
- Clients relying on sequence numbers to resume consumption will lose their place or receive duplicate/conflicting sequences.
- In a distributed or persistent system, sequence numbers should be tied to the database commit log (e.g., the SQLite `id` of the commit).

**Recommendation:**
- Fetch the last sequence number from the database on startup.
- Ideally, use the database's auto-incrementing ID as the sequence number.

### 5. Threading and Concurrency
**Severity: Low (Positive)**
**File:** `Sources/Network/HttpServer.m`, `HttpRouter.m`

- **Good:** The server uses `Network.framework` (`nw_listener`), which is the modern, efficient way to do networking on Apple platforms.
- **Good:** Request processing is dispatched to a global concurrent queue (`dispatch_get_global_queue`), ensuring the network event loop isn't blocked.
- **Good:** `HttpRouter` uses a concurrent queue with barrier blocks for thread-safe route registration.

## Detailed Code Analysis

### HTTP Server (`HttpServer.m`)
- **Port Binding:** Correctly uses `nw_listener_create_with_port`.
- **Connection Handling:** Uses `nw_connection_set_queue` and state handlers correctly.
- **Reading:** Relies on `nw_connection_receive`. As noted in Critical Findings, it lacks a loop for body completion.

### XRPC Dispatch (`XrpcHandler.m`, `XrpcMethodRegistry.m`)
- **Dispatch:** Efficient `NSDictionary` lookup for method handlers.
- **Registration:** Clean block-based API for registering handlers.
- **Input Validation:** Handlers generally check for required fields, which is good.
- **Error Handling:** Returns standard JSON error formats (`error`, `message`).

### Protocol Compliance
- **Headers:** `HttpResponse` adds security headers (`X-Content-Type-Options`, `X-Frame-Options`, `CSP`) by default. This is best practice.
- **Status Codes:** Uses standard `HttpStatus` enum.
- **Methods:** Router supports standard HTTP methods.

## Action Plan

1.  **Fix Body Reading:** This is the immediate priority. The server is likely non-functional for data ingestion until this is fixed.
2.  **Implement Real Auth:** Replace the hardcoded DID with a check against the `Account` or `Session` database tables.
3.  **Persist Sequence Numbers:** Link the firehose sequence to the database commit history.


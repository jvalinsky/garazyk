---
title: Introducing the AT Protocol
description: DIDs, Handles, XRPC Lexicons, and the PLC Directory architecture
---

The AT Protocol (Authenticated Transfer Protocol) is an open, heavily standardized protocol
explicitly designed to power decentralized, globally federated social networks like Bluesky.

Unlike traditional siloed Web2 platforms (like Twitter or Facebook) where a single corporation
intrinsically owns your data, the social graph, and the recommendation algorithms, ATProto
structurally separates the social graph, the digital identity root, and the top-level application
layers. This architectural decoupling enables true data portability and algorithmic choice for end
users.

Implementing a Personal Data Server (PDS) from scratch in Objective-C requires a rigorous, deep
mathematical understanding of exactly how identity is resolved globally, how data schemas are
strictly defined over the wire, and how discrete APIs communicate securely within this massive
distributed ecosystem. This guide explores the foundational pillars of the AT Protocol and how they
are practically implemented in the `ATProtoPDS` architecture.

## Identity: DIDs and Handles

At the absolute core of ATProto is a brilliantly bifurcated identity system that mathematically
separates human-readable names from permanent cryptographic identifiers. This exact design is what
flawlessly allows users to change their public usernames or seamlessly migrate to entirely different
physical hosting servers without ever losing their social graph, their followers, or their post
history.

In ATProto, your identity consists of two rigidly distinct components:

1. **Handle:** A standard, human-readable domain name (e.g., `@jack.bsky.social`, `@garazyk.xyz`, or
   `@apple.com`). Handles are inherently meant to be user-friendly, memorable, and importantly, can
   be safely changed over time. They are strictly verified over the public internet via DNS `TXT`
   records or HTTPS `/.well-known/atproto-did` endpoints to actively prove cryptographic ownership.
2. **DID (Decentralized Identifier):** A permanent, cryptographically verifiable string identifier
   (e.g., `did:plc:ragtjsm2j2vponn25vk332ce` or `did:web:pds.garazyk.xyz`). The DID document acts as
   your true, unchangeable identity root on the global network.

When your application receives a request, it must be highly capable of securely resolving handles
into their backing DIDs and rigorously fetching the DID documents from a trusted registry, such as
the open PLC directory (`https://plc.directory`). The DID document securely contains the public
ECDSA keys and the routing service endpoints (like the user's specific PDS URL) currently associated
with that identity.

> [!NOTE]
> The `did:plc` (Placeholder) method is the heavily recommended default for ATProto, offering
> incredibly strong server portability and account recovery. The older `did:web` method is
> technically supported but violently ties the cryptographic identity directly to a specific DNS
> domain name, almost entirely destroying migration capabilities if the domain registration is ever
> lost or hijacked.

### Resolving Handles Securely (`HandleResolver`)

In `ATProtoPDS`, all dynamic identity resolution is managed centrally by the Objective-C
`HandleResolver`. When a remote user provides a handle string, the internet-facing server absolutely
cannot blindly make an HTTP `GET` request to that domain without catastrophically exposing itself to
severe security risks, explicitly Server-Side Request Forgery (SSRF) vulnerabilities.

The `HandleResolver` forcefully implements several critical infrastructure defenses before daring to
execute an HTTP GET to `https://<handle>/.well-known/atproto-did`:

1. **SSRF Protection:** The `SSRFValidator` ruthlessly ensures that the remote handle's DNS
   `A`/`AAAA` resolution mathematically points exclusively to a public, internet-routable IP
   address. If a malicious user registers a DNS domain artificially pointing to `127.0.0.1`,
   `localhost`, an AWS metadata IP `169.254.169.254`, or a local subnet (e.g., `10.0.0.0/8`), the
   `SSRFValidator` will violently abort the TCP connection pre-flight, definitively preventing the
   server from accidentally querying internal network services.
2. **Rate Limiting:** The resolver tightly controls all outbound network requests. It strictly
   limits active resolutions per domain to a reasonable threshold using a thread-safe
   `NSMutableArray` of timestamps, completely preventing the PDS from being hijacked as a vector for
   massive DDoS amplification attacks.
3. **Exponential Backoff:** If a domain resolution fails (due to a TCP timeout or a 500 network
   error), the resolver caches the exact failure locally and applies a strict exponential backoff
   strategy (up to 1 hour or more) before allowing the queue to attempt to resolve that handle
   again.
4. **DNS TXT Fallback:** If the HTTPS `/.well-known/atproto-did` web endpoint is unresponsive,
   refuses connection, or simply returns a 404 Not Found, the resolver seamlessly falls back to
   legacy DNS. It natively uses the low-level POSIX `res_query()` C-function to physically inspect
   the domain's UDP DNS `TXT` records for a specific text string starting with exactly `_atproto.`,
   which should contain `did=did:plc:...`.

> [!WARNING]
> Proper, air-tight SSRF mitigation is absolutely vital. A compromised or poorly implemented
> `HandleResolver` can allow remote internet attackers to silently scan your internal cloud VPC
> infrastructure, read highly sensitive internal AWS metadata endpoints, or actively exploit other
> unsecured services running purely alongside the PDS.

---

## Communication: XRPC and Typed Lexicons

Unlike traditional REST APIs that lazily rely on arbitrary, loosely defined, undocumented JSON
structures that frequently break client code, ATProto strictly utilizes **XRPC**. XRPC is an
HTTP-based Remote Procedure Call mechanism deliberately designed to operate absolutely strictly on
standard JSON schemas formally called **Lexicons**.

Lexicons define perfectly and exactly what an endpoint requires as an input payload and what it
identically will return in its output shape. Every single method has a unique Name Space Identifier
(NSID), such as `com.atproto.server.createSession`.

- **Queries:** Strictly mapped exclusively to HTTP `GET` requests. Used solely for fetching data
  safely without side effects (e.g., reading a profile or fetching a timeline feed). Parameters are
  mandated to be passed cleanly in the URL query string.
- **Procedures:** Strictly mapped exclusively to HTTP `POST` requests. Used aggressively for actions
  that physically mutate database state (e.g., creating a post, liking, or logging in via OAuth).
  The mutation payload is typically a strongly-validated JSON or DAG-CBOR object.

By ruthlessly enforcing Lexicons natively at the router level, the global network mathematically
guarantees incredibly strong typing and flawless forward API compatibility. If a mobile client sends
a JSON payload that doesn't strictly and perfectly match the Lexicon schema, the PDS will
immediately reject the HTTP request with a `400 Bad Request` before the data even reaches the
application routing logic.

### The `XrpcDispatcher` Architecture

In the `ATProtoPDS` architecture, dynamically routing these incoming HTTP calls is the core
responsibility of the highly optimized `XrpcDispatcher` and the `XrpcMethodRegistry`. They elegantly
bridge the gap between the raw, untyped HTTP byte layer and the strongly typed ATProto Lexicon
schemas.

```mermaid
flowchart TD
    Client[Client App/Relay] -->|HTTP TCP Request| HttpServer[PDSHttpServer]
    HttpServer -->|NSID String & Payload| XrpcDispatcher[XrpcDispatcher]
    XrpcDispatcher -->|O(1) Hash Lookup Method| XrpcMethodRegistry[XrpcMethodRegistry]
    
    XrpcMethodRegistry --> XrpcServerPack[XrpcServerPack]
    XrpcMethodRegistry --> XrpcRepoPack[XrpcRepoPack]
    XrpcMethodRegistry --> XrpcIdentityPack[XrpcIdentityPack]
    
    XrpcRepoPack -->|Strictly Validate & Execute| PDSRecordService[PDSRecordService]
    PDSRecordService -->|Yield Dictionary Result| XrpcDispatcher
    XrpcDispatcher -->|Serialize exactly to JSON/CBOR| HttpServer
    HttpServer -->|HTTP 200 OK Response| Client
```

The registry intelligently delegates to specific modular domain logic (like `XrpcServerPack` for
authentication or `XrpcRepoPack` for user data mutations). Here is a conceptual snippet representing
exactly how a strongly-typed XRPC endpoint is wired into the Objective-C kernel:

```objc
// Conceptually mapping an incoming XRPC NSID directly to a specific Objective-C handler block
[methodRegistry registerMethod:@"app.bsky.actor.getProfile" 
                       handler:^XrpcResponse *(XrpcRequest *request, NSError **error) {
                       
    // 1. Authenticate the remote user securely against OAuth/DPoP (via XrpcAuthHelper)
    if (![XrpcAuthHelper validateRequest:request error:error]) {
        return nil; // Returns standard AuthRequired Lexicon error
    }

    // 2. Safely extract and rigidly validate parameters against the loaded Lexicon schema
    NSString *actorDid = request.parameters[@"actor"];
    if (!actorDid) {
        *error = [ATProtoError missingParameter:@"actor"];
        return nil;
    }

    // 3. Fetch the requested profile securely from the SQLite DatabasePool
    NSDictionary *profileDict = [pdsApplication.recordService fetchProfileForDid:actorDid error:error];
    if (!profileDict) {
        return nil; // Returns standard 404 RecordNotFound
    }

    // 4. Return the standard typed response, the Dispatcher handles the final JSON serialization
    return [[XrpcResponse alloc] initWithStatusCode:200 body:profileDict];
}];
```

## Summary

Deeply understanding these two absolute core pillars—Identity (DIDs and verifiable Handles) and
Communication (strict XRPC and strongly typed Lexicons)—is fundamentally essential before safely
diving into the lower-level socket architectures, concurrent SQLite database migrations, or the
complexities of the ATProto binary WebSocket firehose. By rigorously validating both mathematical
identity domains and raw XRPC payloads natively in C/Objective-C, `ATProtoPDS` provides an
incredibly secure, violently robust foundation for fully participating in the decentralized social
web.

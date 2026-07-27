# ADR 0016: Outbound Connections Use the Validated Address Set

**Status:** Accepted
**Date:** 2026-07-27

## Context

`SSRFValidator` previously checked one DNS result while the outbound HTTP
client resolved the hostname again when it connected. A rebinding domain could
therefore return a public address to validation and a private address to the
connection.

Both HTTP implementations require the same resolution and connection state:
libcurl on GNUstep/Linux and the Apple transport. Redirect targets are new
security decisions, not continuations of the original connection.

## Decision

1. Resolution returns the complete vetted address set. A host is accepted
   only when every result is public; a caller selects only from that set.
2. GNUstep/Linux passes that set to libcurl with per-transfer
   `CURLOPT_RESOLVE` entries. Curl retains the URL hostname for TLS and HTTP
   while dialing only the numeric vetted addresses.
3. Apple uses an in-file `NWConnection` transport for non-loopback traffic.
   It dials a numeric vetted address, retains the original `Host` header, and
   sets the TLS server name to the original hostname for SNI and certificate
   validation.
4. A connection failure may fail over only to another address in the original
   vetted set. Neither implementation performs a fallback DNS lookup.
5. Redirects are processed one hop at a time. Every target is revalidated,
   resolved, and pinned before a new connection is attempted.
6. Loopback retains its existing compatibility path. Resolver calls have a
   deadline; a timeout fails the request rather than waiting indefinitely.

## Consequences

- CDN and multi-address hosts retain controlled failover, but a newly added
  DNS answer is not used until a new validated request begins.
- The Apple transport owns a small HTTP/1.1 request/response bridge inside
  `ATProtoSafeHTTPClient.m`; this keeps platform pinning details out of the
  general network transport layer.
- A security test can inject a resolver for one call without mutable global
  state, so timeout and address-set behavior remain deterministic under
  parallel test execution.

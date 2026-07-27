---
phase: 18
title: Outbound egress pinning and SSRF gaps
status: pending
agent: worker
depends_on: []
---

# Phase 18: Outbound egress pinning and SSRF gaps

## Mission

Execute workstream 01 § S10 slices 5-8. `SSRFValidator`'s address
classification is sound and comprehensive — the problem is that its verdict is
discarded. It resolves a hostname, approves the addresses, and then
`ATProtoSafeHTTPClient` hands the original URL string to curl, which resolves
again independently. A short-TTL attacker-controlled domain returns a public
address to the validator and a private one to the connection.

Do not rewrite the IP classification. `SSRFValidator.m:25-57` already covers
10/8, 172.16/12, 192.168/16, 127/8, 169.254/16 (cloud metadata), 0/8,
100.64/10, the TEST-NETs, multicast and reserved, plus IPv6 loopback, ULA,
link-local, and IPv4-mapped decoding. Three narrow IPv6 gaps are listed below;
everything else is correct and should be left alone.

## Read first

- `docs/plans/workstreams/01-security-and-protocol-correctness.md` § S10
  (authoritative)
- `Garazyk/Sources/Network/SSRFValidator.m` in full
- `Garazyk/Sources/Network/ATProtoSafeHTTPClient.m:164-221` (`validateURL:`)
  and `:262` (the curl handoff). Note there are **two** client
  implementations in this file — a curl path and an `NSURLSession` path — and
  both need the same treatment.

## Decisions already taken (do not re-litigate)

- The validated address is **pinned into the connection** via
  `CURLOPT_RESOLVE` and the `NSURLSession` equivalent. Not
  re-validate-after-connect, and not an egress proxy.
- TLS SNI and the `Host` header must continue to carry the original hostname.
  Pinning changes which address is dialed, not what the server is told.

## Scope and order

1. **Pin the resolved address.** Change `SSRFValidator` to return the vetted
   address alongside its verdict, and have both client implementations connect
   to that address instead of re-resolving. Handle the multi-address case
   deliberately: if a host resolves to several public addresses, either pin one
   and fail over within the vetted set, or re-run validation on failover —
   never fall back to an unvalidated lookup.
2. **Close the IPv6 gaps.** `:44` catches `::1` by exact `memcmp` against
   `in6addr_loopback`, so `::` (unspecified) classifies as public. Add it,
   plus NAT64 (`64:ff9b::/96`) and 6to4 (`2002::/16`) decoding to the embedded
   IPv4 address, which then goes through the existing
   `isPrivateIPv4Address:`.
3. **Bound DNS resolution.** `CFHostStartInfoResolution` (`:82`) and
   `getaddrinfo` (`:164`) are synchronous with no timeout, so a hostile
   authoritative server stalls the calling thread. Give resolution a deadline
   on both platform paths.
4. **Fix the misleading indentation** in `validateURL:`
   (`ATProtoSafeHTTPClient.m:199-218`), which is indented as though it sits
   outside `if (!isLoopback) {` at `:178` when brace counting shows it is
   inside. Behavior is correct today; the formatting is what invites a future
   edit to break it. Do this while already touching the function.

## Acceptance gate

- **Rebinding:** a test resolver that returns a public address on the first
  lookup and a private address on the second must produce a failed request.
  This is the whole point of the phase — without it, nothing here is proven.
- **Classification:** `::`, a NAT64-encoded private IPv4, and a 6to4-encoded
  private IPv4 are each rejected; a genuine public IPv6 address is still
  accepted.
- **Resolver timeout:** a deliberately slow resolver causes a timeout error
  rather than an unbounded hang.
- **No regression in normal egress:** a legitimate multi-address or CDN-backed
  host still fetches successfully. Exercise this against a round-robin DNS
  target, not just a single-A-record host.
- Existing loopback behavior is unchanged: `127.0.0.1`, `localhost`, and `::1`
  still bypass the public-IP requirement as they do today.

New suites need registration in `Garazyk/Tests/test_main.m` plus a cmake
reconfigure. Then the global gates:

```bash
deno task check
deno task lint
deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests
```

Bounded parallelism only (`--parallel 4`). Run the Linux Docker gate too —
this phase changes `Network/` code with a platform-conditional implementation,
and the `getaddrinfo` path only compiles on the non-Apple branch.

## Rollback

Each slice is a single-commit revert. Slice 1 changes how every outbound
request connects and is the risky one. If a legitimate host starts failing,
the likely cause is a multi-address or CDN host whose pinned address went
stale mid-request — check that case before assuming the validator is wrong.
Slices 2-4 are narrow and independently revertible.

## On completion

Write the ADR recording the egress model: that SSRF validation and connection
must share one resolved address, why re-validation after connect was not
chosen, and how multi-address hosts and failover are handled. Update S10
slices 5-8 status in workstream 01 with commit hashes, then set
`status: complete` here.

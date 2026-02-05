# Project Tasks

## Context
We are currently focused on implementing the core PDS/PLC functionality. These tasks capture the follow-up work needed for stubbed paths that fall outside of the current scope or are necessary for long term parity.

## Tasks
1. **Finish Linux transport “real network” support**  
   - Reference: `ATProtoPDS/Sources/Network/PDSNetworkTransportLinux.m`  
   - Reason: The non-blocking connect + read/write loop exists, but outbound connections currently only accept numeric IPv4 addresses. Add hostname (DNS) + IPv6 support (`getaddrinfo`) and tighten error handling/backpressure behavior.

2. **Secure admin authentication + gating**  
   - Reference: `ATProtoPDS/Sources/Admin/PDSAdminAuth.m:29`  
   - Reason: Admin auth currently uses a hardcoded password (`admin123`). Replace with secure configuration and/or gate admin endpoints when unset.

3. **Bring characterization tests up to real coverage**  
   - Reference: `ATProtoPDS/Tests/CharacterizationTests/*`  
   - Reason: Many characterization tests are scaffolds (`TODO: Initialize self.subject` / commented `XCTFail`) and currently provide little safety net.

Only the Linux/PLC work that keeps the PDS/PLC core running is in scope now; treat other tasks as backlog.

## Recently Completed (no longer tracked here)
- `did:key` parsing supports secp256k1 + P-256 via `PLCDIDKey`.
- Moderation/labeling controller paths now route through the admin controller/service (no longer immediate `NotImplemented`).
- Explore CID base58btc (“z” multibase) decoding support exists in `Base58`/`CID`.
- Follower counts use a SQL count query in `ActorService` (remaining work is correctness/perf hardening).

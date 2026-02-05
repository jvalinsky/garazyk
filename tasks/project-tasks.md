# Project Tasks

## Context
We are currently focused on implementing the core PDS/PLC functionality. These tasks capture the follow-up work needed for stubbed paths that fall outside of the current scope or are necessary for long term parity.

## Tasks
1. **Finish Linux transport “real network” support**  
   - Reference: `ATProtoPDS/Sources/Network/PDSNetworkTransportLinux.m`  
   - Reason: Hostname + IPv4/IPv6 resolution is in place (`getaddrinfo`), but we still need real Linux/GNUstep validation, test coverage, and fallback behavior (for example: trying the next `getaddrinfo` candidate if an async connect fails).

2. **Secure admin authentication + gating**  
   - Reference: `ATProtoPDS/Sources/Admin/PDSAdminAuth.m:29`  
   - Reason: Admin auth now requires `PDS_ADMIN_PASSWORD`, but we still need a clear production story (secret files/hashes, rotation, and request-level authorization rather than process-global state).

Only the Linux/PLC work that keeps the PDS/PLC core running is in scope now; treat other tasks as backlog.

## Recently Completed (no longer tracked here)
- `did:key` parsing supports secp256k1 + P-256 via `PLCDIDKey`.
- Linux transport outbound connects resolve hostnames + IPv4/IPv6 via `getaddrinfo()`.
- Admin auth no longer uses a hardcoded password (uses `PDS_ADMIN_PASSWORD`).
- Characterization tests contain real assertions/fixtures (no longer scaffolds).
- Moderation/labeling controller paths now route through the admin controller/service (no longer immediate `NotImplemented`).
- Explore CID base58btc (“z” multibase) decoding support exists in `Base58`/`CID`.
- Follower counts use a SQL count query in `ActorService` (remaining work is correctness/perf hardening).

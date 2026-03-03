# Project Tasks (Archived)

> **Note:** This file is archived. Active project tracking is now in [sans-io-refactor.md](sans-io-refactor).

## Context
We are currently focused on implementing the core PDS/PLC functionality. These tasks capture the follow-up work needed for stubbed paths that fall outside of the current scope or are necessary for long term parity.

## Completed Tasks

### Linux Transport (2026-02)
- Hostname + IPv4/IPv6 resolution via `getaddrinfo()` ✅
- Implementation tracked in: [010-linux-transport-real-network-validation-and-fallback.md](010-linux-transport-real-network-validation-and-fallback)

### Admin Auth (2026-02)
- Admin auth now requires `PDS_ADMIN_PASSWORD` ✅
- Production hardening tracked in: [020-admin-auth-production-hardening.md](020-admin-auth-production-hardening)

### Previously Completed
- `did:key` parsing supports secp256k1 + P-256 via `PLCDIDKey`.
- Linux transport outbound connects resolve hostnames + IPv4/IPv6 via `getaddrinfo()`.
- Admin auth no longer uses a hardcoded password (uses `PDS_ADMIN_PASSWORD`).
- Characterization tests contain real assertions/fixtures (no longer scaffolds).
- Moderation/labeling controller paths now route through the admin controller/service (no longer immediate `NotImplemented`).
- Explore CID base58btc ("z" multibase) decoding support exists in `Base58`/`CID`.
- Follower counts use a SQL count query in `ActorService` (remaining work is correctness/perf hardening).

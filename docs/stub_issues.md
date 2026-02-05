# Behaviors to Track (Remaining Work)

1. `ATProtoPDS/Sources/Admin/PDSAdminAuth.m:29`
   - Admin auth now requires a configured secret (`PDS_ADMIN_PASSWORD`) and mints an admin JWT when it matches.
   - Impact: Admin endpoints still need a clear production gating story (for example: “disabled unless configured”, support for secret files/hashes, and request-level authorization instead of process-global state).
   - Next step: define the production model (env vs file vs hash, rotation, and per-request authorization) and enforce it consistently across admin endpoints.

2. `ATProtoPDS/Sources/AppView/ActorService.m:183`
   - Follower counts use `records.subject_did` for follow records and have supporting indices (`idx_records_subject_did`, `idx_records_subject_did_collection`).
   - Impact: Remaining risk is correctness: ensure all follow/block write paths populate `subject_did` consistently.
   - Next step: add a targeted integration test that creates a follow and asserts follower count increments for the subject.

## Recently Resolved
- `did:key` parsing now supports secp256k1 + P-256 multicodecs via `PLCDIDKey` (ATProtoPDS/Sources/PLC/PLCDIDKey.m).
- Linux transport outbound connects resolve hostnames + IPv4/IPv6 via `getaddrinfo()` and try subsequent candidates when async connect fails (ATProtoPDS/Sources/Network/PDSNetworkTransportLinux.m).
- Admin auth no longer uses a hardcoded password (ATProtoPDS/Sources/Admin/PDSAdminAuth.m).
- Admin endpoints now require per-request JWT verification (scope includes `admin`) and support server-side logout invalidation via issued-at cutoff (ATProtoPDS/Sources/Admin/PDSAdminAuth.m).
- Server JWT signing key is persisted to disk so sessions survive restarts (override path with `PDS_JWT_PRIVATE_KEY_PATH`) (ATProtoPDS/Sources/Auth/JWTSigningKeyStore.m).
- Characterization tests now contain real assertions/fixtures (ATProtoPDS/Tests/CharacterizationTests/*).

Please file follow-up work items if you want these tracked in an issue tracker, and reopen this file if the list grows.

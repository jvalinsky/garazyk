# Behaviors to Track (Remaining Work)

1. `ATProtoPDS/Sources/Network/PDSNetworkTransportLinux.m`
   - The non-blocking connect + read/write loop is implemented, but outbound connections currently only accept numeric IPv4 addresses (`inet_pton(AF_INET, ...)`).
   - Impact: Linux/GNUstep builds can’t connect to hostnames (DNS) or IPv6 targets, limiting real-world deployability.
   - Next step: switch to `getaddrinfo()` (IPv4/IPv6), attempt multiple candidates, and add targeted tests.

2. `ATProtoPDS/Sources/Admin/PDSAdminAuth.m:29`
   - Admin auth currently uses a hardcoded password (`admin123`).
   - Impact: Unsafe default; blocks any credible “production-ready” claim for admin/moderation endpoints even if the controller/service paths are implemented.
   - Next step: replace with secure, configurable auth (env-provided secret or hash; constant-time compare) and/or gate admin endpoints if unset.

3. `ATProtoPDS/Sources/AppView/ActorService.m:183`
   - Follower counts now use a SQL count query, but it depends on `records.subject_did` being populated for follow records and may need indexing for scale.
   - Impact: Counts can be wrong/slow if `subject_did` isn’t consistently written or if the table grows large.
   - Next step: ensure write paths populate `subject_did` for `app.bsky.graph.follow` and add an index covering `(subject_did, collection)`.

## Recently Resolved
- `did:key` parsing now supports secp256k1 + P-256 multicodecs via `PLCDIDKey` (ATProtoPDS/Sources/PLC/PLCDIDKey.m).

Please file follow-up work items if you want these tracked in an issue tracker, and reopen this file if the list grows.

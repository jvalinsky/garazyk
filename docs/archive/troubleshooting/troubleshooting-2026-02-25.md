---
title: ATProto PDS Troubleshooting & Bug Logs (25 Feb 2026)
---

# ATProto PDS Troubleshooting & Bug Logs (25 Feb 2026)

This document captures the errors, protocol subtleties, and infrastructure anomalies encountered during the development and verification of the ATProto PDS system, specifically regarding relay integration and repository ingestion.

## 1. HTTP Server Transient Hang on describeRepo/getRepoStatus
**Error:** PDS endpoints (like `getRepoStatus?did=...`) completely hang and stop responding to `curl` requests. The process itself docs not crash, but the thread enters a deadlock.
**Cause:** Initially suspected to be a string formatting vulnerability regarding the `%3A` URL encoding in the DIDs. However, logging evaluation confirmed that `PDS_LOG_HTTP_INFO` safely formats strings natively. The true cause of the hang was a transient deadlock—likely a SQLite database lock or networking race condition induced by concurrent crawl limits.
**Fix:** The transient lock was cleared by restarting the container (`docker compose up -d --force-recreate pds`). To aid in future debugging of potential concurrent lock-ups or abuse, we modified `HttpServer.m` to log the incoming `remoteAddress` of all connecting clients.

### 2. SQLite Database Auto-Creation for Invalid DIDs
**Error:** Passing an invalid `did` to `com.atproto.sync.getRepoStatus` returned `active: true` and created a 0-byte SQLite database on the disk instead of returning a `404 RepoNotFound` error.
**Cause:** Our endpoint queried `[PDSDatabasePool storeForDid:did error:&error]`. By design, `storeForDid:` inherently creates a database file on disk if it doesn't already exist.
**Fix:** Updated the `getRepoStatus` endpoint in `XrpcSyncMethods.m` to first query `[PDSServiceDatabases getAccountByDid:did error:&error]`. This safely queries the core tracking database without triggering disk side-effects, allowing us to accurately return a 404 for missing accounts.

### 3. Array Subscript Object Conversion error on HttpRequest Query
**Error:** Compilation error `expected method to read array element not found on object of type 'NSString *'` when parsing XRPC parameters.
**Cause:** Code incorrectly assumed `request.query[@"did"]` was a mapped property returning a parsed dictionary, when `request.query` wasn't mapped that way.
**Fix:** Replaced dictionary access with the native `HttpRequest` method: `[request queryParamForKey:@"did"]`.

### 4. Relay Scraping vs. AppView Indexing
**Error:** A `curl` to the public Bluesky AppView (`public.api.bsky.app`) for our PDS DID returns `{"error":"InvalidRequest","message":"Profile not found"}`, despite positive logs showing `bsky.network` successfully receiving `requestCrawl`, pulling `com.atproto.sync.getRecord`, and scraping the CAR blocks.
**Cause:** Relays (like `bsky.network` or `fire.hose.cam`) and AppViews are decoupled. The relay performs the cryptographic mathematical verification and imports the nodes into the raw firehose, while the AppView performs aggressive spam prevention. Brand new PDS nodes have low trust profiles, so AppViews often silently ignore profile hydration until reputation is met.
**Fix:** There is no code bug here. The solution to force the AppView to index the node's profile is organic cross-node interaction (e.g., an established `bsky.social` user following the newly federated PDS account).

### 5. `com.atproto.sync.describeRepo` returning `501 Not Implemented`
**Error:** PDS Request Logs showed external crawlers pinging `/xrpc/com.atproto.sync.describeRepo` and receiving `501 Not Implemented` instead of the expected JSON or `404 Not Found`.
**Cause:** Legacy `describeRepo` functions once existed under the `sync.*` namespace but were permanently moved to `com.atproto.repo.describeRepo` in the official ATProto spec. Relays often still test for the legacy endpoint out of backwards compatibility. 
**Fix:** Do nothing. Returning `501 NotImplemented` when routing unregistered `/xrpc/` endpoints is the intended, protocol-compliant behavior. The relays correctly register the 501 and gracefully shift their parsing strategy.

### 6. Remote Docker Daemon Configuration Networking
**Error:** Random file mounting conflicts or build failures when using OrbStack/local docker clients against remote servers.
**Cause:** Mismatches between local client daemon paths and the deployed Linux target architecture.
**Fix:** Executing `docker compose build pds` natively over SSH to the Linux VM rather than tunnelling remote build contexts.

### 7. Relay Federation Crawl Timeline (`subscribeRepos` behavior)
**Observation:** When sending a `requestCrawl` to a relay (like `bsky.network`), the relay immediately calls `GET /xrpc/com.atproto.server.describeServer`, but does not immediately connect to the `subscribeRepos` WebSocket.
**Explanation:** This is expected behavior dictated by the Indigo relay's crawler architecture (specifically `cmd/relay/relay/slurper.go`). 
1. **Verification:** Upon receiving a `requestCrawl`, the relay synchronously fires a `CheckHost` API call to `describeServer` to ensure the host is actually an online PDS.
2. **Queueing:** If the check passes, the relay adds the PDS to its internal database with `status = active`. 
3. **Connection:** A background process (`Slurper`) pulls active hosts from the database and dials the `subscribeRepos` WebSocket. However, this is subject to the relay's `HostPerDayLimiter`, concurrent connection limits, and connection polling intervals.
**Conclusion:** It is completely normal for a relay to take several minutes (or even hours depending on the global queue) to actually connect to the `subscribeRepos` firehose after a successful `requestCrawl`. Once connected, it will backfill all events starting from the requested cursor.

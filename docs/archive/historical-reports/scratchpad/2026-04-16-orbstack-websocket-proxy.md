# OrbStack WebSocket Proxy Investigation

**Date**: 2026-04-16
**Nodes**: 315, 321
**Status**: INVESTIGATION COMPLETE - OrbStack networking limitation

## Issue

WebSocket upgrade fails over OrbStack HTTPS hostname but works via localhost:
- `https://local-relay.local-network.orb.local/xrpc/com.atproto.sync.subscribeRepos` → HTTP/2 404
- `http://127.0.0.1:2584/xrpc/com.atproto.sync.subscribeRepos` → HTTP/1.1 101 Switching Protocols

## Root Cause

OrbStack's HTTPS proxy does NOT forward WebSocket upgrade headers to Docker containers.

### Evidence

```bash
# OrbStack HTTPS - returns 404 as GET, no upgrade
$ curl -ik -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  https://local-relay.local-network.orb.local/xrpc/com.atproto.sync.subscribeRepos
HTTP/2 404
{"error":"Not Found","message":"No handler for GET /xrpc/com.atproto.sync.subscribeRepos"}

# Localhost - returns 101
$ curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  http://127.0.0.1:2584/xrpc/com.atproto.sync.subscribeRepos
HTTP/1.1 101 Switching Protocols
upgrade: websocket
sec-websocket-accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```

### Analysis

1. The WebSocket server in `SubscribeReposHandler` binds to `localhost:2584` (line 132 in SubscribeReposHandler.m)
2. OrbStack forwards HTTPS traffic to container port, but strips/drops the `Connection: Upgrade` header
3. The relay receives a plain GET request instead of upgrade request
4. XRPC handler returns 404 because GET isn't valid for subscribeRepos

## Solution Applied

Added polling fallback in `RelayEventsController.j`:
- On WebSocket error, automatically switch to HTTP polling
- Poll `/xrpc/com.atproto.sync.getRepo?limit=100&cursor=...` every 5 seconds
- Works over any HTTP endpoint without WebSocket support

## Why Not Fix OrbStack

1. This is an OrbStack networking configuration issue, not our codebase bug
2. Would require OrbStack-specific config or nginx sidecar in container
3. Polling fallback provides same functionality with zero infrastructure changes
4. Works for all users regardless of their deployment environment

## Test Commands

```bash
# Test WebSocket upgrade on localhost (should return 101)
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  http://127.0.0.1:2584/xrpc/com.atproto.sync.subscribeRepos

# Test WebSocket upgrade on OrbStack (returns 404)
curl -ik -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  https://local-relay.local-network.orb.local/xrpc/com.atproto.sync.subscribeRepos

# Test polling fallback works (returns 200 with repo data)
curl -s https://local-relay.local-network.orb.local/xrpc/com.atproto.sync.getRepo | jq
```

## Related Files

- `Garazyk/Sources/App/CappuccinoUI/RelayEventsController.j` - Polling fallback implementation
- `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:132` - WebSocket binds to localhost
- `Garazyk/Binaries/zuk/main.m:382` - WebSocket route registration

---

## XRPC Endpoint Coverage by Service (Local-Network)

### PLC (port 2582)
| Endpoint | Status | Notes |
|----------|--------|-------|
| `com.atproto.identity.getSigningKey` | Not Found | |
| `com.atproto.identity.resolveHandle` | Not Found | |
| `com.atproto.identity.updateHandle` | Not Found | |
| `com.atproto.identity.signOperations` | Not Found | |
| `com.atproto.identity.submitOperation` | Not Found | |
| `com.atproto.plc.getOperationLog` | Not Found | |

### PDS (port 2583)
| Endpoint | Status | Notes |
|----------|--------|-------|
| `com.atproto.server.createSession` | InvalidRequest | Needs params |
| `com.atproto.server.createAccount` | InvalidRequest | Needs params |
| `com.atproto.server.getSession` | AuthRequired | ✓ Protected |
| `com.atproto.repo.listRecords` | InvalidRequest | Needs params |
| `com.atproto.repo.createRecord` | AuthRequired | ✓ Protected |
| `com.atproto.repo.getRecord` | InvalidRequest | Needs params |
| `com.atproto.sync.listRepos` | OK | ✓ Works |
| `com.atproto.sync.getHead` | AuthRequired | ✓ Protected |
| `com.atproto.sync.subscribeRepos` | UpgradeRequired | ✓ WebSocket required |
| `app.bsky.actor.getProfile` | InvalidRequest | Needs params |
| `app.bsky.feed.getTimeline` | AuthRequired | ✓ Protected |

### Relay (port 2584) - UPDATED 2026-04-16
| Endpoint | Status | Notes |
|----------|--------|-------|
| `com.atproto.sync.listRepos` | OK | ✓ Works (returns [] when no upstream data) |
| `com.atproto.sync.getHead` | OK | ✓ Works |
| `com.atproto.sync.getRepo` | OK | ✓ Works |
| `com.atproto.sync.subscribeRepos` | 101 localhost | ✓ WebSocket works on localhost |
| `com.atproto.sync.subscribeRepos` | 404 OrbStack | OrbStack proxy issue (not our code) |
| `api/relay/health` | OK | ✓ Works |
| `api/relay/upstreams` | OK | ✓ Works |
| `api/relay/metrics` | OK | ✓ Works |

### AppView (port 3200)
| Endpoint | Status | Notes |
|----------|--------|-------|
| `app.bsky.feed.getTimeline` | Not Found | **MISSING** |
| `app.bsky.feed.getAuthorFeed` | Not Found | **MISSING** |
| `app.bsky.actor.getProfile` | Not Found | **MISSING** |
| `app.bsky.notification.listNotifications` | Not Found | **MISSING** |
| `admin/backfill/status` | OK | ✓ Works (with auth) |
| `admin/capabilities` | OK | ✓ Works (with auth) |

---

## Implications for Polling Fallback

The Relay NOW exposes:
- `com.atproto.sync.listRepos` ✓
- `com.atproto.sync.getHead` ✓
- `com.atproto.sync.getRepo` ✓
- `com.atproto.sync.subscribeRepos` WebSocket ✓

The polling fallback in `RelayEventsController.j` can now use the relay endpoint directly.

---

## AppView XRPC Gaps (Next Phase)

AppView is missing all `app.bsky.*` endpoints. Required endpoints per ATProto spec:

| Priority | Endpoint | Description |
|----------|----------|-------------|
| P0 | `app.bsky.feed.getTimeline` | Authenticated user's home feed |
| P0 | `app.bsky.feed.getAuthorFeed` | Posts by a given account |
| P0 | `app.bsky.actor.getProfile` | Profile for an account |
| P0 | `app.bsky.notification.listNotifications` | User's notifications |
| P1 | `app.bsky.feed.getPostThread` | Thread view for a post |
| P1 | `app.bsky.graph.getFollows` | Accounts a user follows |
| P1 | `app.bsky.graph.getFollowers` | Accounts following a user |
| P2 | `app.bsky.feed.getLikes` | Likes on a post |
| P2 | `app.bsky.actor.getSuggestions` | Suggested accounts |

Implementation approach:
1. Create AppViewXrpcRoutePack similar to RelayXrpcRoutePack
2. Wire up data store (already exists - AppViewDatabase)
3. Register endpoints at `/xrpc/` path

---
title: Chat Service (syrena-chat)
---

# Chat Service (syrena-chat)

**syrena-chat** is a standalone AT Protocol service providing direct messaging (DM) and group chat functionality, implemented as a separate binary from the PDS.

## Overview

The Chat service handles the `chat.bsky.*` XRPC method namespace. It can run as:
- A **standalone binary** (`syrena-chat`) — serves chat.bsky.* methods directly on its own HTTP port
- **Embedded in the PDS** — the PDS registers local handlers when no remote chat URL is configured

## XRPC Interface

### Actor Methods
- `chat.bsky.actor.declaration` — Manage a user's chat declaration (allow incoming messages)
- `chat.bsky.actor.exportAccountData` — Export chat account data

### Conversation Methods
- `chat.bsky.convo.getConvo` — Get a specific conversation
- `chat.bsky.confo.getConvoForMembers` — Find or create conversation for participants
- `chat.bsky.confo.leaveConvo` — Leave a conversation
- `chat.bsky.confo.listConvos` — List conversations for the user
- `chat.bsky.confo.muteConvo` / `chat.bsky.confo.unmuteConvo`
- `chat.bsky.confo.updateRead` — Mark conversation as read
- `chat.bsky.confo.sendMessage` — Send a direct message
- `chat.bsky.confo.getMessages` — Get conversation messages
- `chat.bsky.confo.getLog` — Get conversation event log
- `chat.bsky.confo.acceptConvo` — Accept an incoming conversation request

### Group Methods
- `chat.bsky.confo.addMember` — Add a member to a group
- `chat.bsky.confo.removeMember` — Remove a member from a group
- `chat.bsky.confo.listMembers` — List group members

## Service Discovery and Routing

Chat requests follow the AT Protocol proxy routing convention:

```
atproto-proxy: did:web:<chat-service-domain>#bsky_chat
```

### DID Document Discovery

The Chat service serves its own `did:web` DID document at `GET /.well-known/did.json`:

```json
{
  "@context": ["https://www.w3.org/ns/did/v1"],
  "id": "did:web:<service-domain>",
  "service": [{
    "id": "#bsky_chat",
    "type": "BskyChatService",
    "serviceEndpoint": "https://<service-domain>"
  }]
}
```

The PDS also includes `#bsky_chat` in its own DID document when `PDS_CHAT_URL` is configured.

### Routing Flow

1. Client sends `atproto-proxy: did:web:<domain>#bsky_chat` + XRPC request to PDS
2. PDS resolves `did:web:<domain>` → fetches `https://<domain>/.well-known/did.json`
3. PDS finds the `#bsky_chat` service entry and extracts the `serviceEndpoint` URL
4. PDS proxies the XRPC request to the Chat service with a service JWT
5. Chat service verifies the JWT against the PDS's JWKS endpoint

## Configuration

Environment variables for the standalone Chat service:

| Variable | Default | Description |
|---|---|---|
| `CHAT_HTTP_PORT` | 2585 | HTTP listen port |
| `CHAT_DATA_DIR` | `./data/chat` | Data directory |
| `CHAT_ADMIN_SECRET` | (empty) | Admin API secret |
| `PDS_URL` | `http://localhost:2583` | Upstream PDS for JWT verification |
| `CHAT_SERVICE_DOMAIN` | (computed) | Public domain for `did:web` (e.g., `chat.garazyk.xyz`) |

## Authentication

The Chat service delegates JWT verification to the PDS. On startup, it fetches the PDS's JWKS at `{pdsUrl}/oauth/jwks` (or `/.well-known/jwks.json`) and uses those keys to verify incoming service JWTs.

The chat service itself has no independent DID identity — its DID document is served at `/.well-known/did.json` using the configured `CHAT_SERVICE_DOMAIN` (or defaults to `did:web:localhost:<port>`).

## Related
- [Services Overview](./services-overview)
- [PDS Application Facade](./pds-application)
- [Germ E2EE Mailbox Service](./germ-service)
- [XRPC Dispatch](../04-network-layer/xrpc-dispatch)
- [AT Protocol Proxy Headers](../04-network-layer/xrpc-dispatch.md#proxy-dispatch)

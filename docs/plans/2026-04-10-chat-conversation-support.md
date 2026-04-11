---
title: "Phase 3: Chat/Conversation Support Plan"
---

# Phase 3: Chat/Conversation Support

> **Status:** 0% Complete - Not implemented
> **Priority:** P2 (Medium)
> **Generated:** 2026-04-10

## Executive Summary

Chat/direct messaging (DM) functionality requires implementing the `chat.bsky.*` namespace. This is needed for ATProto direct messaging support. Currently no endpoints are implemented.

---

## Current Implementation Status

| Endpoint | Status | Notes |
|----------|--------|-------|
| `chat.bsky.convo.*` | ❌ Not implemented | 17 endpoints |
| `chat.bsky.moderation.*` | ❌ Not implemented | 3 endpoints |
| `chat.bsky.actor.*` | ❌ Not implemented | 2 endpoints |

---

## Database Schema Design

### Core Tables

```sql
-- Conversations (DMs)
CREATE TABLE convos (
    id TEXT PRIMARY KEY,           -- UUID
    did TEXT NOT NULL,             -- Owner (sender/recipient)
    peer_did TEXT NOT NULL,        -- Peer in conversation
    last_message_at TEXT,
    unread_count INTEGER DEFAULT 0,
    muted INTEGER DEFAULT 0,
    archived INTEGER DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(did, peer_did)
);

CREATE INDEX idx_convos_did ON convos(did);
CREATE INDEX idx_convos_peer ON convos(did, peer_did);
CREATE INDEX idx_convos_updated ON convos(did, updated_at DESC);

-- Messages
CREATE TABLE messages (
    id TEXT PRIMARY KEY,
    convo_id TEXT NOT NULL,
    sender_did TEXT NOT NULL,
    content TEXT NOT NULL,
    embed_json TEXT,               -- Rich embeds (images, posts)
    reply_to_id TEXT,              -- Reply to another message
    hashtags TEXT,                 -- Extracted for search
    facets_json TEXT,              -- Rich text facets (links, mentions)
    labels TEXT,                   -- Message labels
    deleted_at TEXT,               -- Soft delete
    created_at TEXT NOT NULL,
    FOREIGN KEY (convo_id) REFERENCES convos(id)
);

CREATE INDEX idx_messages_convo ON messages(convo_id, created_at DESC);
CREATE INDEX idx_messages_sender ON messages(sender_did);
CREATE INDEX idx_messages_deleted ON messages(deleted_at);

-- Reactions
CREATE TABLE message_reactions (
    id TEXT PRIMARY KEY,
    message_id TEXT NOT NULL,
    did TEXT NOT NULL,              -- Who reacted
    reaction TEXT NOT NULL,        -- emoji
    created_at TEXT NOT NULL,
    FOREIGN KEY (message_id) REFERENCES messages(id),
    UNIQUE(message_id, did)
);

CREATE INDEX idx_reactions_message ON message_reactions(message_id);

-- Read receipts
CREATE TABLE convo_reads (
    convo_id TEXT NOT NULL,
    did TEXT NOT NULL,
    last_read_message_id TEXT NOT NULL,
    last_read_at TEXT NOT NULL,
    PRIMARY KEY (convo_id, did),
    FOREIGN KEY (convo_id) REFERENCES convos(id)
);

-- Actor access control (for moderation)
CREATE TABLE actor_access (
    did TEXT PRIMARY KEY,
    allow_messages INTEGER DEFAULT 1,
    allow_mentions INTEGER DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

---

## Tasks

### Task 3.1: Create XrpcChatMethods.m Handler

**Goal:** New handler file for chat namespace

**Files:**
- New: `ATProtoPDS/Sources/Network/XrpcChatMethods.m`
- New: `ATProtoPDS/Sources/Network/XrpcChatMethods.h`

**Steps:**
1. Create header file with registration method
2. Create implementation with all endpoint handlers
3. Add to XrpcMethodRegistry dispatch

---

### Task 3.2: Implement chat.bsky.convo.getConvo

**Goal:** Get a specific conversation by ID

**Input:**
- `convoId`: string (required)

**Output:**
```objc
@{
    @"convo": @{
        @"id": convoId,
        @"rev": rev,
        @"actor": @{ @"did": peerDid, @"handle": handle },
        @"lastMessage": @{ @"text": text, @"sentAt": sentAt },
        @"unreadCount": @(unread),
        @" muted": @(muted),
        @"updatedAt": updatedAt
    }
}
```

**Files:**
- Implementation: `XrpcChatMethods.m`
- Database: Query convos table

---

### Task 3.3: Implement chat.bsky.convo.listConvos

**Goal:** List all conversations for user with pagination

**Input:**
- `limit`: integer (optional, default 50, max 100)
- `cursor`: string (optional)

**Output:**
```objc
@{
    @"convos": convosArray,
    @"cursor": nextCursor
}
```

**Steps:**
1. Query convos table ordered by last_message_at DESC
2. Apply pagination with cursor
3. Include last message preview
4. Return unread count

---

### Task 3.4: Implement chat.bsky.convo.sendMessage

**Goal:** Send a message in a conversation

**Input:**
- `convoId`: string (required)
- `message`: object (required)
  - `text`: string
  - `embed`: object (optional)
  - `replyTo`: string (optional)

**Output:**
```objc
@{
    @"message": @{
        @"id": messageId,
        @"convoId": convoId,
        @"sender": @{ @"did": senderDid },
        @"text": text,
        @"sentAt": sentAt
    }
}
```

**Steps:**
1. Validate sender is participant in convo
2. Store message in messages table
3. Update convos.last_message_at
4. Emit WebSocket event for real-time delivery
5. Return message with server-assigned ID

---

### Task 3.5: Implement chat.bsky.convo.sendMessageBatch

**Goal:** Send multiple messages in one request

**Input:**
- `convoId`: string
- `messages`: array of message objects

**Output:**
```objc
@{
    @"messages": messagesArray
}
```

**Steps:**
1. Validate all messages
2. Insert in transaction
3. Update conversation last_message_at

---

### Task 3.6: Implement chat.bsky.convo.getMessages

**Goal:** Get messages in a conversation with cursor-based pagination

**Input:**
- `convoId`: string (required)
- `limit`: integer (optional, default 25, max 100)
- `cursor`: string (optional)
- `since`: string (optional) - only return messages after this time

**Output:**
```objc
@{
    @"messages": messagesArray,
    @"cursor": nextCursor
}
```

**Steps:**
1. Query messages by convo_id
2. Apply cursor-based pagination
3. Filter deleted messages (unless sender viewing own)
4. Include sender info

---

### Task 3.7: Implement Read Receipts

#### Task 3.7a: chat.bsky.convo.updateRead

**Input:**
- `convoId`: string
- `messageId`: string (optional) - mark as read up to this message

#### Task 3.7b: chat.bsky.convo.updateAllRead

**Input:** (none - marks all conversations as read)

**Steps for both:**
1. Update convo_reads table
2. Update convos.unread_count = 0
3. Emit WebSocket event to peer

---

### Task 3.8: Implement Reactions

#### Task 3.8a: chat.bsky.convo.addReaction
**Input:**
- `convoId`: string
- `messageId`: string  
- `reaction`: string (emoji)

#### Task 3.8b: chat.bsky.convo.removeReaction
**Input:**
- `convoId`: string
- `messageId`: string

**Steps:**
1. Insert/delete from message_reactions table
2. Emit WebSocket event to message sender

---

### Task 3.9: Implement Convo Management

| Endpoint | Description |
|----------|-------------|
| `acceptConvo` | Accept an incoming conversation invite |
| `leaveConvo` | Leave/delete a conversation |
| `muteConvo` | Mute notifications for conversation |
| `unmuteConvo` | Unmute conversation |
| `deleteMessageForSelf` | Soft delete message for self only |

**Steps:**
1. Add archived/muted columns to convos table (if not present)
2. Implement each endpoint handler
3. Handle soft-delete for messages

---

### Task 3.10: Implement chat.bsky.convo.getLog

**Goal:** Get a stream of conversation events for sync

**Input:**
- `cursor`: string (optional)
- `limit`: integer (optional)

**Output:**
```objc
@{
    @"logs": @[
        @{ @"action": "create", @"convo": convo },
        @{ @"action": "message", @"message": msg },
        @{ @"action": "reaction", @"reaction": rxn }
    ],
    @"cursor": nextCursor
}
```

**Steps:**
1. Create event log table for chat events
2. Query with cursor pagination
3. Support filtering by action type

---

### Task 3.11: Implement chat.bsky.moderation.* Endpoints

| Endpoint | Description |
|----------|-------------|
| `getActorMetadata` | Get user's message/mention settings |
| `getMessageContext` | Get surrounding messages for moderation |
| `updateActorAccess` | Update allow_messages, allow_mentions |

**Implementation:**
- Query/insert/update actor_access table
- Get message context: fetch N messages before/after

---

### Task 3.12: Implement chat.bsky.actor.* Endpoints

| Endpoint | Description |
|----------|-------------|
| `deleteAccount` | Delete account (should also delete all messages) |
| `exportAccountData` | Export all DM data |

**Steps:**
1. For deleteAccount: cascade delete convos, messages, reactions
2. For exportAccountData: query all tables, return JSON/CSV

---

### Task 3.13: Add Additional Conversation Features

**Optional enhancements:**
- `getConvoForMembers` - Find convo by participants
- `getConvoAvailability` - Check if can message user

---

## XRPC Endpoint Reference

### Required Endpoints (Total: 22)

#### Convo (17)
1. `chat.bsky.convo.getConvo` - Get single convo
2. `chat.bsky.convo.listConvos` - List convos
3. `chat.bsky.convo.sendMessage` - Send message
4. `chat.bsky.convo.sendMessageBatch` - Batch send
5. `chat.bsky.convo.getMessages` - Get messages
6. `chat.bsky.convo.getLog` - Get event log
7. `chat.bsky.convo.acceptConvo` - Accept invite
8. `chat.bsky.convo.leaveConvo` - Leave convo
9. `chat.bsky.convo.muteConvo` - Mute
10. `chat.bsky.convo.unmuteConvo` - Unmute
11. `chat.bsky.convo.updateRead` - Mark read
12. `chat.bsky.convo.updateAllRead` - Mark all read
13. `chat.bsky.convo.addReaction` - Add reaction
14. `chat.bsky.convo.removeReaction` - Remove reaction
15. `chat.bsky.convo.deleteMessageForSelf` - Soft delete
16. `chat.bsky.convo.getConvoForMembers` - Find by members
17. `chat.bsky.convo.getConvoAvailability` - Check availability

#### Moderation (3)
18. `chat.bsky.moderation.getActorMetadata` - Get settings
19. `chat.bsky.moderation.getMessageContext` - Get context
20. `chat.bsky.moderation.updateActorAccess` - Update settings

#### Actor (2)
21. `chat.bsky.actor.deleteAccount` - Delete DMs
22. `chat.bsky.actor.exportAccountData` - Export DMs

---

## Dependencies

- `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m` - Registration
- `ATProtoPDS/Sources/Database/PDSDatabase.m` - Storage
- WebSocket infrastructure (existing `SubscribeReposHandler.m` as reference)

---

## Related Plans

- [Phase 2: Video Processing Pipeline](2026-04-10-video-processing-pipeline.md)
- [Phase 1: OAuth 2.0/DPoP Compliance](2026-04-10-oauth-dpop-compliance.md)

---

## Next Steps

After video pipeline complete:
1. Create database migration for chat schema
2. Create XrpcChatMethods.m/h
3. Implement endpoints in order of criticality (convo first, then moderation/actor)
4. Add WebSocket support for real-time message delivery
5. Test full DM flow end-to-end
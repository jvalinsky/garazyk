---
title: Chat and Conversation Service
---

# Chat and Conversation Service

The Garazyk PDS implements the `chat.bsky.*` namespace, enabling private and group conversations with strong safety controls and auditable event logs.

## Subsystem Architecture

The chat implementation is divided between the XRPC route handlers and the core business logic in `ChatService`.

### 1. `XrpcChatBskyConvoPack`
**Location:** `Garazyk/Sources/Network/XrpcChatBskyConvoPack.m`

This pack registers all conversation-related endpoints, including:
*   `chat.bsky.convo.getLog`: Retrieves the safety audit log for conversations.
*   `chat.bsky.convo.sendMessageBatch`: Optimized bulk message delivery.
*   `chat.bsky.convo.getConvoForMembers`: Resolves or creates conversations based on a set of DIDs.

### 2. `ChatService`
**Location:** `Garazyk/Sources/AppView/Services/ChatService.m`

Implements the core logic for:
*   **Message Delivery**: Inserting messages into the `messages` table and updating conversation timestamps.
*   **Membership Management**: Handling `accepted`, `pending`, and `left` states for conversation participants.
*   **Event Logging**: Automatically recording all safety-sensitive actions to the `chat_event_log`.

## Safety & Moderation

Chat safety is integrated into the service layer via the `ChatModerationService`.

*   **Actor Metadata**: Per-user flags for muting and blocking are checked during message delivery.
*   **Auditing**: The `chat.bsky.moderation` endpoints allow authorized moderators to retrieve message context and actor history to resolve safety reports.

## Database Schema (Chat)

| Table | Purpose |
| --- | --- |
| `conversations` | Header information for all chat threads. |
| `conversation_members` | Join/leave status and read-receipts for each participant. |
| `messages` | The content and metadata of all sent messages. |
| `message_reactions` | Emoji reactions associated with messages. |
| `chat_event_log` | Permanent audit trail of all chat activity. |

---

## Related
- [Trust, Safety, and Compliance](./safety-and-compliance)
- [XRPC Namespace Packs](../xrpc-namespace-packs)
- [Database Schema (Service)](../05-database-layer/service-databases)

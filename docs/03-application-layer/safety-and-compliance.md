---
title: Trust, Safety, and Compliance
---

# Trust, Safety, and Compliance

Garazyk implements several layers of trust and safety, including Age Assurance, Chat Moderation, and Event Logging, to ensure regulatory compliance and protect users.

## Operational Model

The safety layer focuses on three pillars:
1.  **Verification**: Confirming user attributes (e.g., age) while maintaining privacy.
2.  **Moderation**: Utilizing automated and human-driven tools to manage participant behavior.
3.  **Auditability**: Maintaining a permanent record of safety-related actions.

## Age Assurance

The Age Assurance system verifies that users meet the minimum age requirements for specific services or regions.

### Verification Flow
1.  **Initiation**: The user provides an email and region via `app.bsky.ageassurance.begin`.
2.  **Token Issuance**: `AgeAssuranceService` generates a 6-digit verification code and stores a `pending` state.
3.  **Email Delivery**: The configured `PDSEmailProvider` sends the token to the user.
4.  **Confirmation**: The user submits the token via `app.bsky.unspecced.confirmAgeAssurance`.
5.  **Assurance**: Upon successful verification, the user's status is updated to `assured` in the database.

### Regional Compliance
`AgeAssuranceConfig` defines per-region rules to enforce `minAccessAge` requirements, aligning with local jurisdictional laws.

## Chat Moderation

The `ChatModerationService` manages safety within private and group conversations.

### Participant Metadata
The system tracks state in the `chat_actor_metadata` table:
*   **Muted**: Suppresses chat notifications for the actor.
*   **Blocked**: Prevents messages from being delivered to or received from the actor.
*   **Labels**: Attaches metadata labels (e.g., `spam`, `harassment`) for filtering and review.

### Moderation Review
Moderators can retrieve flagged message context, including surrounding conversation history, via the `chat.bsky.moderation.getMessageContext` endpoint.

## Chat Event Logging

Significant actions within the chat subsystem are recorded in the `chat_event_log` for auditing.

### Logged Events
*   `message`: Record of a message transmission.
*   `accept`/`leave`: Entry or departure from a conversation.
*   `reaction_add`/`reaction_remove`: Emoji interactions.
*   `mute`/`block`: Administrative moderation actions.

The log is accessible to authorized callers via `chat.bsky.convo.getLog`.

## Database Schema (Safety Layer)

| Table Name | Description |
| :--- | :--- |
| `age_assurance_states` | Status, email, token, and region for age verification. |
| `chat_actor_metadata` | Per-actor moderation flags and metadata. |
| `chat_event_log` | Permanent audit trail of chat safety events. |

## Related
- [Ozone Moderation Endpoints](../tools-ozone-endpoints)
- [Email & Verification Guide](../06-authentication/email-and-verification)
- [Database Schema](../05-database-layer/service-databases)
- [Admin Service](./admin-service)
- [Services Overview](./services-overview)
- [Documentation Map](../11-reference/documentation-map.md)

---
title: Trust, Safety, and Compliance
---

# Trust, Safety, and Compliance

Garazyk implements a robust set of features to ensure regulatory compliance (e.g., EU Digital Services Act) and user safety. These features include Age Assurance, Chat Moderation, and comprehensive Event Logging.

## Philosophy

Our trust and safety model is built on three pillars:
1.  **Verification**: Confirming user attributes (like age) without compromising more privacy than necessary.
2.  **Granular Moderation**: Providing both automated and human-led tools to manage actor behavior and content access.
3.  **Auditable Logs**: Maintaining a secure, permanent record of all safety-sensitive actions for oversight and reporting.

## Age Assurance System

The Age Assurance system ensures that users meet age requirements for specific services or regions.

### Verification Flow
1.  **Begin (`app.bsky.ageassurance.begin`)**: The user initiates a request, providing their email and region.
2.  **Token Issuance**: The `AgeAssuranceService` generates a unique 6-digit verification code and stores a `pending` state in `age_assurance_states`.
3.  **Email Delivery**: The token is sent via the pluggable `PDSEmailProvider` (integration with SMTP or services like Resend).
4.  **Confirmation (`app.bsky.unspecced.confirmAgeAssurance`)**: The user submits the token.
5.  **Assurance**: Upon successful token validation, the user's status is updated to `assured` in the database.

### Regional Rules
Compliance rules are defined per-region (e.g., US, GB, EU) in the `AgeAssuranceConfig`. This allows the system to enforce different `minAccessAge` requirements based on local laws.

## Chat Moderation

The `ChatModerationService` provides tools to manage the safety of private and group conversations.

### Actor Metadata tracking
The system tracks moderation state for chat participants in the `chat_actor_metadata` table:
*   **Muted**: Prevents the actor from appearing in the user's chat notifications.
*   **Blocked**: Prevents the actor from sending messages to the user.
*   **Labels**: Attaches moderation labels (e.g., `spam`, `harassment`) to specific actors.

### Contextual Review
Moderators can retrieve the full context of a flagged message, including surrounding messages and conversation metadata, via the `chat.bsky.moderation.getMessageContext` endpoint.

## Chat Event Logging

For safety and auditability, all significant chat actions are recorded in the `chat_event_log`.

### Logged Events
*   `message`: Record of a message being sent (including `messageId`).
*   `accept`/`leave`: When a user joins or departs a conversation.
*   `reaction_add`/`reaction_remove`: Tracking emoji reactions.
*   `mute`/`block`: Moderation actions taken against participants.

The log can be retrieved via `chat.bsky.convo.getLog`, providing a transparent trail for safety reviews.

## Database Tables (Safety Layer)

| Table Name | Description |
| :--- | :--- |
| `age_assurance_states` | Status, email, token, and region for age verification. |
| `chat_actor_metadata` | Per-actor moderation flags (muted, blocked). |
| `chat_event_log` | Permanent audit trail of all chat safety events. |

---

## Related
- [Ozone Moderation Endpoints](../tools-ozone-endpoints)
- [Email & Verification Guide](../06-authentication/email-and-verification)
- [Database Schema](../05-database-layer/service-databases)

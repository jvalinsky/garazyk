---
title: Trust, Safety, and Compliance
---

# Trust, Safety, and Compliance

Garazyk uses Age Assurance, Chat Moderation, and Event Logging for regulatory compliance and user safety.

## Model

The trust and safety model uses:
1.  **Verification**: Confirming user attributes while maintaining privacy.
2.  **Moderation**: Automated and human tools to manage behavior and content.
3.  **Logging**: A permanent record of safety actions.

## Age Assurance

The Age Assurance system verifies that users meet age requirements for specific services or regions.

### Verification Flow
1.  **Begin (`app.bsky.ageassurance.begin`)**: User provides email and region.
2.  **Token Issuance**: `AgeAssuranceService` generates a 6-digit code and stores a `pending` state.
3.  **Email Delivery**: Pluggable `PDSEmailProvider` sends the token.
4.  **Confirmation (`app.bsky.unspecced.confirmAgeAssurance`)**: User submits the token.
5.  **Assurance**: `assured` status updated in the database.

### Regional Rules
`AgeAssuranceConfig` defines rules per-region to enforce `minAccessAge` requirements based on local laws.

## Chat Moderation

The `ChatModerationService` manages the safety of private and group conversations.

### Actor Metadata
The system tracks participant state in the `chat_actor_metadata` table:
*   **Muted**: Prevents chat notifications.
*   **Blocked**: Prevents messages from the actor.
*   **Labels**: Attaches labels like `spam` or `harassment`.

### Contextual Review
Moderators retrieve flagged message context, including surrounding messages, via the `chat.bsky.moderation.getMessageContext` endpoint.

## Chat Event Logging

Significant chat actions are recorded in the `chat_event_log`.

### Logged Events
*   `message`: Record of a message sent.
*   `accept`/`leave`: Joins or departures.
*   `reaction_add`/`reaction_remove`: Emoji reactions.
*   `mute`/`block`: Moderation actions.

The log is accessible via `chat.bsky.convo.getLog`.

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

# Sub-plan: 06 — Chat DM allowIncoming Enforcement

## Problem
`getConvoForMembers` is not rejected when the target user has `allowIncoming=none`. Expected: the call should fail.

## Investigation

### Expected behavior
When a user sets their incoming message preference to "none", other users should not be able to start conversations with them. `getConvoForMembers` (which creates/finds a conversation) should reject the request.

### Root cause candidates
1. **allowIncoming preference not checked**: Chat service creates the conversation without checking the recipient's preference
2. **Preference storage not consulted**: The preference is stored but not read during DM creation
3. **Wrong preference key**: The scenario sets one preference key but the code reads another

## Work

### 1. Find Chat service implementation
- Look for chat/IM/DM service code in `Garazyk/Sources/`
- Find where `getConvoForMembers` is handled
- Check how conversations are created

### 2. Find allowIncoming preference
- Check how the scenario sets `allowIncoming` (likely via `app.bsky.actor.putPreferences`)
- Find where preferences are stored
- Check the preference schema for `allowIncoming`

### 3. Add enforcement
- In the conversation creation path, before creating the convo, check the target user's `allowIncoming` preference
- If `allowIncoming = "none"`, reject with an appropriate error
- If `allowIncoming = "following"`, check if the initiator follows the target

## Files
- `Garazyk/Sources/Chat/` or `Garazyk/Sources/Services/Chat/` (chat service)
- `Garazyk/Sources/Network/XrpcChatPack.m` (chat XRPC handlers)
- `scripts/scenarios/scenarios/06_chat_dms.ts` (scenario)

## Verification
```bash
nix develop -c bash -c "cd scripts/scenarios && deno run -A e2e_runner.ts --scenario 06"
```

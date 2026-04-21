# XRPC Compliance Audit - Next Steps

**Session**: 6 (2026-04-21)
**Git Hash**: d2c541ea
**Status**: 100% XRPC endpoint coverage achieved

## Completed This Session

### Commits
- `2cc6f816` - feat(xrpc): implement 13 missing XRPC endpoints
- `d2c541ea` - fix(test): update ageassurance test for local handlers

### Endpoints Added (13 total)

| Category | Endpoint | Type | Status |
|----------|----------|------|--------|
| tools.ozone.moderation | cancelScheduledActions | procedure | ✅ Stub |
| tools.ozone.moderation | getSubjects | query | ✅ Stub |
| app.bsky.unspecced | getTrends | query | ✅ Stub |
| app.bsky.ageassurance | begin | procedure | ✅ Stub |
| app.bsky.ageassurance | getConfig | query | ✅ Stub |
| app.bsky.ageassurance | getState | query | ✅ Stub |
| chat.bsky.actor | deleteAccount | procedure | ✅ Stub |
| chat.bsky.actor | exportAccountData | query | ✅ Stub |
| chat.bsky.convo | getLog | query | ✅ Stub |
| chat.bsky.group | enableJoinLink | procedure | ✅ Stub |
| chat.bsky.moderation | getActorMetadata | query | ✅ Stub |
| chat.bsky.moderation | getMessageContext | query | ✅ Stub |
| chat.bsky.moderation | updateActorAccess | procedure | ✅ Stub |

### Endpoint Count
- Before: 297 registered
- After: 310 registered
- Coverage: 100% of XRPC query/procedure types

## Next Steps

### 1. Database Schema for New Endpoints

Several endpoints need database tables:

```sql
-- Age Assurance
CREATE TABLE age_assurance_states (
    id TEXT PRIMARY KEY,
    did TEXT NOT NULL,
    status TEXT NOT NULL,
    email TEXT,
    country_code TEXT,
    region_code TEXT,
    language TEXT,
    token TEXT,
    created_at INTEGER,
    updated_at INTEGER
);

-- Chat event log
CREATE TABLE chat_event_log (
    id TEXT PRIMARY KEY,
    convo_id TEXT NOT NULL,
    actor_did TEXT NOT NULL,
    event_type TEXT NOT NULL,
    event_data TEXT,
    created_at INTEGER
);

-- Chat moderation metadata
CREATE TABLE chat_actor_metadata (
    did TEXT PRIMARY KEY,
    muted INTEGER DEFAULT 0,
    blocked INTEGER DEFAULT 0,
    labels TEXT,
    updated_at INTEGER
);
```

### 2. Service Layer Implementation

**Age Assurance Service** (`AgeAssuranceService.h/m`):
- `beginAgeAssurance:email:language:countryCode:regionCode:error:`
- `getAgeAssuranceConfig`
- `getAgeAssuranceState:countryCode:regionCode:error:`
- Email verification flow integration

**Chat Moderation Service** (`ChatModerationService.h/m`):
- `getActorMetadata:actor:error:`
- `getMessageContext:messageId:error:`
- `updateActorAccess:actor:access:error:`
- Integration with existing ChatService

### 3. Full Implementation Priority

**High Priority** (user-facing features):
1. `tools.ozone.moderation.cancelScheduledActions` - Already has DB schema
2. `tools.ozone.moderation.getSubjects` - Already has ModerationService support
3. `chat.bsky.moderation.*` - Chat safety features

**Medium Priority** (compliance):
4. `app.bsky.ageassurance.*` - Regulatory compliance (EU Digital Services Act)
5. `chat.bsky.actor.deleteAccount` - Data deletion
6. `chat.bsky.actor.exportAccountData` - Data portability

**Low Priority** (optional features):
7. `app.bsky.unspecced.getTrends` - Requires trending algorithm
8. `chat.bsky.convo.getLog` - Event log archival
9. `chat.bsky.group.enableJoinLink` - Group management

### 4. Test Coverage

Add tests for new endpoints:

```
Tests/Network/XrpcAppBskyAgeAssuranceTests.m
Tests/Network/XrpcChatBskyActorTests.m
Tests/Network/XrpcChatBskyModerationTests.m
```

Test patterns:
- Auth required validation
- Input validation (required fields)
- Output schema compliance
- Error handling

### 5. Remaining AT Protocol Work

Beyond XRPC endpoints:

1. **Record Schemas** (38 lexicon schemas not endpoints):
   - `app.bsky.actor.*` record types
   - `app.bsky.feed.*` record types
   - `app.bsky.graph.*` record types
   - Validation and indexing

2. **Lexicon Validation**:
   - Ensure all input/output schemas match lexicon
   - Add JSON Schema validation for request bodies

3. **Interoperability Testing**:
   - Run against official atproto test suite
   - Test with Bluesky client apps
   - Test with other PDS implementations

### 6. Documentation

Update documentation:
- API documentation for new endpoints
- Runbook updates for age assurance flow
- Architecture docs for chat moderation

## Decision Graph

Nodes created this session:
- Node 61: Goal "Implement 13 missing XRPC endpoints"
- Node 62-68: Actions (commits linked)
- Node 69: Outcome "100% XRPC coverage achieved"

## Related Files

- [[.deciduous/deciduous.db]] - Decision graph database
- [[Garazyk/Sources/Network/XrpcAppBskyAgeAssurancePack.m]] - Age assurance handlers
- [[Garazyk/Sources/Network/XrpcChatBskyActorPack.m]] - Chat actor/moderation handlers
- [[Garazyk/Sources/AppView/Services/ModerationService.m]] - Ozone backend

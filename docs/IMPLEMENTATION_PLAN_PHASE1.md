# ATProto PDS Implementation Plan - Phase 1 Completion

## Executive Summary

**Current Status**: 22.5% complete (18/80 endpoints)
**Target**: 80% complete (64+ endpoints)
**Timeline**: 10 weeks (phased approach)
**Worktrees Required**: 4 parallel branches

---

## Phase 1: Critical Infrastructure (Week 1-2)

### 1.1 Rate Limiting Implementation

**Branch**: `rate-limiting-worktree`

**Files to Create**:
- `ATProtoPDS/ATProtoPDS/Network/RateLimiter.h`
- `ATProtoPDS/ATProtoPDS/Network/RateLimiter.m`

**Features**:
- Sliding window algorithm
- Per-DID and per-IP limits
- Configurable thresholds
- Response headers (X-RateLimit-*)

**ATProto Spec Requirements**:
```
rate limits:
  - identifier: did
    limit: 5000
    window: 1h
  - identifier: ip
    limit: 100
    window: 1m
```

**Implementation Details**:
```objective-c
@interface RateLimiter : NSObject
+ (instancetype)sharedLimiter;
- (BOOL)checkRateLimitForDid:(NSString *)did identifier:(NSString *)identifier;
- (NSDictionary *)rateLimitHeadersForDid:(NSString *)did;
@end
```

---

### 1.2 DescribeServer Endpoint

**Branch**: `rate-limiting-worktree` (combined with 1.1)

**Files to Modify**:
- `ATProtoPDS/ATProtoPDS/Network/XrpcMethodRegistry.m`
- `ATProtoPDS/ATProtoPDS/Network/XrpcHandler.h`

**Lexicon**: `com.atproto.server.describeServer`

**Response Schema**:
```json
{
  "inviteCodeRequired": true,
  "links": {
    "privacyPolicy": "https://...",
    "termsOfService": "https://...",
    "contact": "mailto:...",
    "feedPattersGenUrl": "https://..."
  },
  "consentTos": "https://...",
  "emailNoAuth": true,
  "defaultFeedDescriptors": [],
  "feedbackUrl": "https://...",
  "feeds": {
    "preferencesSupported": ["firehose", "hook"],
    "policy": {...}
  }
}
```

---

## Phase 2: Core Sync & Repo (Week 3-4)

### 2.1 SubscribeRepos WebSocket

**Branch**: `sync-core-worktree`

**Files to Create**:
- `ATProtoPDS/ATProtoPDS/Sync/SubscribeReposHandler.h`
- `ATProtoPDS/ATProtoPDS/Sync/SubscribeReposHandler.m`

**Files to Modify**:
- `ATProtoPDS/ATProtoPDS/Network/XrpcMethodRegistry.m`

**Lexicon**: `com.atproto.sync.subscribeRepos`

**Event Format**:
```json
{
  "kind": "commit",
  "repo": "did:plc:...",
  "commit": "bafyrei...",
  "rev": "3k5xyz...",
  "since": "3k5xww...",
  "blocks": <CAR bytes>,
  "ops": [
    {"action": "create", "path": "app.bsky.feed.post/3k5xyz", "cid": "bafyrei..."}
  ]
}
```

**Cursor Management**:
- SQLite-based cursor persistence
- Per-subscriber cursor tracking
- Cursor expiry (7 days)

---

### 2.2 GetRepoStatus & ListRepos

**Branch**: `sync-core-worktree`

**Lexicons**:
- `com.atproto.sync.getRepoStatus`
- `com.atproto.sync.listRepos`

**Database Schema**:
```sql
CREATE TABLE repo_status (
  did TEXT PRIMARY KEY,
  active BOOLEAN NOT NULL DEFAULT 1,
  lastStatus TEXT,
  lastCheckedAt DATETIME,
  statusAt DATETIME
);
```

---

### 2.3 ListMissingBlobs & ImportRepo

**Branch**: `sync-core-worktree`

**Lexicons**:
- `com.atproto.repo.listMissingBlobs`
- `com.atproto.repo.importRepo`

**listMissingBlobs**:
- Compare blob references in records to actual blobs
- Return CIDs of orphaned blobs

**importRepo**:
- Accept CAR file import
- Validate commit chain
- Apply to MST

---

## Phase 3: Account Management (Week 5-6)

### 3.1 Invite System

**Branch**: `account-worktree`

**Endpoints**:
- `com.atproto.server.createInviteCode`
- `com.atproto.server.createInviteCodes`
- `com.atproto.server.getAccountInviteCodes`

**Database Schema**:
```sql
CREATE TABLE invite_codes (
  code TEXT PRIMARY KEY,
  did TEXT NOT NULL,
  createdAt DATETIME NOT NULL,
  usesRemaining INTEGER NOT NULL DEFAULT 1,
  disabled BOOLEAN NOT NULL DEFAULT 0,
  forAccount TEXT
);
```

**Invite Code Generation**:
- Format: `3hvq-xxxx-xxxx-xxxx`
- Cryptographically secure random
- Code length: 16 characters

---

### 3.2 Password Management

**Branch**: `account-worktree`

**Endpoints**:
- `com.atproto.server.requestPasswordReset`
- `com.atproto.server.resetPassword`
- `com.atproto.server.createAppPassword`
- `com.atproto.server.listAppPasswords`
- `com.atproto.server.revokeAppPassword`

**Database Schema**:
```sql
CREATE TABLE app_passwords (
  id TEXT PRIMARY KEY,
  did TEXT NOT NULL,
  name TEXT NOT NULL,
  password TEXT NOT NULL,
  createdAt DATETIME NOT NULL,
  scopes TEXT NOT NULL,
  privileged BOOLEAN NOT NULL DEFAULT 0
);
```

---

### 3.3 Email Management

**Branch**: `account-worktree`

**Endpoints**:
- `com.atproto.server.requestEmailConfirmation`
- `com.atproto.server.confirmEmail`
- `com.atproto.server.requestEmailUpdate`
- `com.atproto.server.updateEmail`

**Database Schema**:
```sql
ALTER TABLE accounts ADD COLUMN emailConfirmed BOOLEAN DEFAULT 0;
ALTER TABLE accounts ADD COLUMN emailToken TEXT;
ALTER TABLE accounts ADD COLUMN emailTokenExpiresAt DATETIME;
```

---

### 3.4 Session Management

**Branch**: `account-worktree`

**Endpoints**:
- `com.atproto.server.getSession`
- `com.atproto.server.deleteSession`

**Response**:
```json
{
  "did": "did:plc:...",
  "handle": "user.bsky.social",
  "email": "user@example.com",
  "emailConfirmed": true,
  "accessJwt": "eyJ...",
  "refreshJwt": "eyJ...",
  "active": true
}
```

---

## Phase 4: Admin API (Week 7-8)

### 4.1 Admin Endpoints

**Branch**: `admin-worktree`

**Endpoints**:
- `com.atproto.admin.getAccountInfo`
- `com.atproto.admin.getAccountInfos`
- `com.atproto.admin.updateAccountHandle`
- `com.atproto.admin.updateAccountEmail`
- `com.atproto.admin.updateAccountPassword`
- `com.atproto.admin.enableAccountInvites`
- `com.atproto.admin.disableAccountInvites`
- `com.atproto.admin.getInviteCodes`
- `com.atproto.admin.disableInviteCodes`
- `com.atproto.admin.getSubjectStatus`
- `com.atproto.admin.updateSubjectStatus`
- `com.atproto.admin.sendEmail`

**Database Schema**:
```sql
CREATE TABLE admin_takedowns (
  id TEXT PRIMARY KEY,
  subjectType TEXT NOT NULL,
  subjectId TEXT NOT NULL,
  reason TEXT,
  takedownRef TEXT,
  applied BOOLEAN NOT NULL DEFAULT 1,
  createdBy TEXT NOT NULL,
  createdAt DATETIME NOT NULL
);
```

---

## Phase 5: AppView Integration (Week 9-10)

### 5.1 Actor Profiles

**Branch**: `appview-worktree`

**Endpoints**:
- `app.bsky.actor.getProfile`
- `app.bsky.actor.getProfiles`
- `app.bsky.actor.getPreferences`
- `app.bsky.actor.putPreferences`

**Profile Schema**:
```json
{
  "did": "did:plc:...",
  "handle": "user.bsky.social",
  "displayName": "User Name",
  "description": "Bio text",
  "avatar": "blob://...",
  "banner": "blob://...",
  "followersCount": 100,
  "followsCount": 50,
  "postsCount": 25,
  "indexedAt": "2024-01-01T00:00:00Z"
}
```

---

### 5.2 Feed Endpoints

**Branch**: `appview-worktree`

**Endpoints**:
- `app.bsky.feed.getTimeline`
- `app.bsky.feed.getAuthorFeed`
- `app.bsky.feed.getPostThread`
- `app.bsky.feed.getFeed`

**Implementation**:
- Query records by type (`app.bsky.feed.post`)
- Apply pagination (cursor-based)
- Hydrate referenced records

---

### 5.3 Push Notifications

**Branch**: `appview-worktree`

**Endpoint**:
- `app.bsky.notification.registerPush`

**Schema**:
```json
{
  "serviceDid": "did:web:push.example.com",
  "token": "device_push_token",
  "platform": "ios" | "android" | "web"
}
```

---

## Supporting Infrastructure

### Database Migration Framework

**Files to Create**:
- `ATProtoPDS/ATProtoPDS/Database/MigrationManager.h`
- `ATProtoPDS/ATProtoPDS/Database/MigrationManager.m`
- `ATProtoPDS/ATProtoPDS/Database/Migrations/001_initial_schema.m`

**Migration Pattern**:
```objective-c
@interface Migration001 : NSObject <Migration>
@end

@implementation Migration001
- (void)up:(PDSDatabase *)db { ... }
- (void)down:(PDSDatabase *)db { ... }
@end
```

---

### Configuration System

**Files to Create**:
- `ATProtoPDS/ATProtoPDS/Config/PDSConfig.h`
- `ATProtoPDS/ATProtoPDS/Config/PDSConfig.m`
- `config.yaml` support

**Config Options**:
```yaml
server:
  host: "0.0.0.0"
  port: 2583
  environment: "development"

database:
  main: "./data/pds.db"
  repo: "./data/repo.db"

blobStorage:
  type: "disk"  # or "s3"
  diskPath: "./data/blobs"

rateLimit:
  enabled: true
  redisUrl: "redis://localhost:6379"

identity:
  plcUrl: "https://plc.directory"
  runUrl: "https://bsky.social"

email:
  smtpHost: "smtp.example.com"
  smtpPort: 587
```

---

## Worktree Setup Commands

```bash
# Phase 1: Rate limiting + describeServer
git worktree add -b rate-limiting-worktree ../rate-limiting-worktree main

# Phase 2: Sync core
git worktree add -b sync-core-worktree ../sync-core-worktree main

# Phase 3: Account management
git worktree add -b account-worktree ../account-worktree main

# Phase 4: Admin API
git worktree add -b admin-worktree ../admin-worktree main

# Phase 5: AppView
git worktree add -b appview-worktree ../appview-worktree main
```

---

## Testing Requirements

### Unit Tests Required:
- RateLimiter: 20+ tests
- Session management: 15+ tests
- Invite codes: 10+ tests
- Admin APIs: 20+ tests

### Integration Tests Required:
- OAuth flow: 10+ scenarios
- Repo sync: 15+ scenarios
- Invite workflow: 8+ scenarios

---

## Build & Test Commands

```bash
# Build all worktrees
for wt in rate-limiting-worktree sync-core-worktree account-worktree admin-worktree appview-worktree; do
  (cd ../$wt && make clean && make) &
done
wait

# Run tests
make test-unit
./build/mime_type_validator_tests
./build/blob_storage_tests
```

---

## Completion Criteria

### Phase 1 (Week 1-2):
- [ ] Rate limiter implemented
- [ ] describeServer returns valid response
- [ ] Rate limit headers on all responses
- [ ] 95% unit test pass rate

### Phase 2 (Week 3-4):
- [ ] subscribeRepos WebSocket working
- [ ] getRepoStatus implemented
- [ ] listMissingBlobs implemented
- [ ] importRepo accepts CAR files

### Phase 3 (Week 5-6):
- [ ] Invite code generation and validation
- [ ] Password reset flow
- [ ] App password management
- [ ] Email verification

### Phase 4 (Week 7-8):
- [ ] All admin endpoints working
- [ ] Subject takedowns
- [ ] Invite code management

### Phase 5 (Week 9-10):
- [ ] Profile fetching
- [ ] Feed generation
- [ ] Push registration

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| WebSocket stability | High | Extensive testing, heartbeat mechanism |
| Database schema changes | Medium | Migration framework first |
| OAuth complexity | Medium | Use reference implementation patterns |
| Timeline slippage | Medium | Phases can overlap |

---

## References

- [ATProto Repository Spec](https://atproto.com/specs/repository)
- [ATProto Sync Spec](https://atproto.com/specs/sync)
- [PDS Lexicons](https://github.com/bluesky-social/atproto/tree/main/lexicons/com/atproto)
- [Reference PDS Implementation](https://github.com/bluesky-social/atproto/tree/main/packages/pds)

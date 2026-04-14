---
title: Next Steps Plan
---

# Next Steps Plan

**Created**: 2026-02-27
**Status**: Ready for execution

---

## Immediate Priorities

### 1. OAuth2 Client Compatibility (High Priority)

**Problem**: Login works on witchsky.app but posts/profiles don't render. Console shows 400 errors.

**Actions**:
- [ ] Build and run local PDS for testing
- [ ] Test XRPC endpoints directly with curl
- [ ] Compare responses with official bsky.app API
- [ ] Fix any response format issues

**Reference**: `docs/oauth2-testing-plan.md`

### 2. Missing XRPC Endpoints (Medium Priority)

**Recently Added (Stubs)**:
- `app.bsky.feed.getPosts` ✅ (implemented)
- `app.bsky.feed.getFeedGenerators` ✅ (stub)
- `app.bsky.feed.getSuggestedFeeds` ✅ (stub)
- `app.bsky.graph.getMutes` ✅ (stub)
- `app.bsky.graph.getBlocks` ✅ (stub)

**Still Missing**:
- [ ] `app.bsky.graph.getBlockedByActor`
- [ ] `app.bsky.feed.getFeedGenerator`
- [ ] `app.bsky.graph.getKnownFollowers`
- [ ] `app.bsky.labeler.*` endpoints
- [ ] `app.bsky.video.*` endpoints

### 3. GraphService Implementation (In Progress)

**Uncommitted Files**:
- `Garazyk/Sources/AppView/GraphService.h`
- `Garazyk/Sources/AppView/GraphService.m`

**Actions**:
- [ ] Review GraphService implementation
- [ ] Implement follow/unfollow operations
- [ ] Implement mute/block operations
- [ ] Add database schema for follows/mutes/blocks

### 4. Database Schema Updates

**Recently Added**:
- `actor_preferences` table ✅

**Still Needed**:
- [ ] `follows` table (actor, subject, created_at)
- [ ] `mutes` table (actor, subject, created_at)
- [ ] `blocks` table (actor, subject, created_at)
- [ ] `lists` table (for user lists)
- [ ] `list_items` table

### 5. Live PDS Deployment

**Server**: crimson-comet.exe.xyz

**Actions**:
- [ ] SSH and check current deployment status
- [ ] Pull latest changes
- [ ] Rebuild Docker image
- [ ] Test endpoints against live server
- [ ] Monitor logs for errors

---

## Week 1 Goals

| Day | Task |
|-----|------|
| Mon | Build local PDS, test OAuth2 endpoints |
| Tue | Fix response format issues, implement missing endpoints |
| Wed | Implement GraphService with follow/mute/block |
| Thu | Database schema for social graph |
| Fri | Deploy to live PDS, test with real clients |

---

## Technical Debt

1. **Documentation**: ✅ Completed - HeaderDoc standardized
2. **Build Artifacts**: ✅ Completed - Removed build_local/
3. **Tests**: Need to add tests for new XRPC endpoints
4. **Error Handling**: Standardize error responses across endpoints

---

## Uncommitted Changes

```

M Garazyk/Sources/Database/Schema.h
M Garazyk/Sources/Database/Schema.m
?? Garazyk/Sources/AppView/GraphService.h
?? Garazyk/Sources/AppView/GraphService.m
```

**Action**: Review and commit GraphService, or continue implementation.

---

## Memory Updates Needed

1. Update `project/overview.md` with recent progress
2. Add `project/api/xrpc-endpoints.md` for endpoint status tracking
3. Create `session-notes/2026-02-27.md` for today's work

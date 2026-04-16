---
title: "XRPC Audit & Stub Fix Plan"
---

# XRPC Audit & Stub Fix Plan

> **Status:** In Progress
> **Generated:** 2026-04-15
> **Priority:** P1 (High)

---

## Executive Summary

Deep-dive audit identified 3 categories of stubbed endpoints in the PDS. This plan prioritizes fixing stubs before performing a full ATProto lexicon audit.

---

## Phase 1: Stub Fixes (Priority)

### 1.1 app.bsky.actor.getSuggestions - EASIEST ✅

**Location:** `Garazyk/Sources/Network/XrpcAppBskyActorPack.m:200-204`

**Current State:**
```objc
// app.bsky.actor.getSuggestions - Get suggested accounts (stub)
[dispatcher registerMethod:@"app.bsky.actor.getSuggestions" handler:^(HttpRequest *request, HttpResponse *response) {
    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{@"actors": @[]}];
}];
```

**Problem:** Returns empty array (200 OK) - client thinks there are no suggestions

**Fix Options:**
1. **Option A (Recommended):** Return proper suggestions from ActorService
2. **Option B:** Return 501 NotImplemented to clearly indicate stub

**Implementation (Option A):**
- Use existing `ActorService` to query followed-by, recent actors, etc.
- Return hydrated actor profiles

**Files to Modify:**
- `Garazyk/Sources/Network/XrpcAppBskyActorPack.m`

---

### 1.2 app.bsky.graph.searchStarterPacks - EASY

**Location:** `Garazyk/Sources/Network/XrpcAppBskyGraphPack.m:479`

**Current State:**
```objc
// app.bsky.graph.searchStarterPacks - Search starter packs (stub)
```

**Problem:** Comment indicates stub, need to verify if implemented

**Fix Options:**
1. **Option A:** Implement using GraphService
2. **Option B:** Mark as explicit 501 stub

**Files to Modify:**
- `Garazyk/Sources/Network/XrpcAppBskyGraphPack.m`

---

### 1.3 app.bsky.video.* Processing - MEDIUM

**Location:** `XrpcAppBskyVideoPack.m`

**Current State:**
- `app.bsky.video.getJobStatus` - ✅ Implemented
- `app.bsky.video.uploadVideo` - ✅ Upload works, processing stubbed
- `app.bsky.video.getUploadLimits` - ✅ Implemented

**Processing Stub:** Returns "Video stored. Processing not implemented."

**See:** [2026-04-10-video-processing-pipeline.md](./2026-04-10-video-processing-pipeline.md)

---

### 1.4 chat.bsky.convo.* (5 endpoints) - HARD

**Location:** `Garazyk/Sources/Network/XrpcChatBskyConvoPack.m:12-95`

**Current State:** All return 501 NotImplemented

| Endpoint | Line | Notes |
|----------|------|-------|
| `chat.bsky.convo.getConvo` | 12 | Stub - 501 |
| `chat.bsky.convo.listConvos` | 29 | Stub - 501 |
| `chat.bsky.convo.sendMessage` | 46 | Stub - 501 |
| `chat.bsky.convo.getMessages` | 63 | Stub - 501 |
| `chat.bsky.convo.getLog` | 80 | Stub - 501 |

**See:** [2026-04-10-chat-conversation-support.md](./2026-04-10-chat-conversation-support.md)

---

## Phase 2: Full Lexicon Audit

### 2.1 Fix Node.js ESM Issue

**Problem:** `generate_xrpc_coverage_report.js` uses CommonJS `require()` but `package.json` has `"type": "module"`

**Solution A:** Rename to `.cjs`
```bash
mv scripts/docs/generate_xrpc_coverage_report.js scripts/docs/generate_xrpc_coverage_report.cjs
mv scripts/docs/generate_xrpc_next_steps.js scripts/docs/generate_xrpc_next_steps.cjs
```

**Solution B:** Convert to ESM (requires updating all `require()` to `import`)

---

### 2.2 Run Coverage Report

```bash
cd scripts/docs
node generate_xrpc_coverage_report.cjs --source-only --fail-on-duplicates
node generate_xrpc_next_steps.cjs
```

**Expected Outputs:**
- `reports/xrpc_coverage.md`
- `reports/xrpc_coverage.json`
- `reports/xrpc_next_steps_plan.md`

---

### 2.3 Scope Definition

From `scripts/docs/xrpc_coverage_scope.txt`:
```
+com.atproto.*
+app.bsky.*
-app.bsky.unspecced.*
```

This tracks:
- `com.atproto.server.*` - PDS server methods
- `com.atproto.identity.*` - Identity methods
- `com.atproto.repo.*` - Repository methods
- `com.atproto.sync.*` - Sync methods
- `com.atproto.admin.*` - Admin methods
- `com.atproto.label.*` - Label methods
- `app.bsky.actor.*` - Actor methods
- `app.bsky.feed.*` - Feed methods
- `app.bsky.graph.*` - Graph methods
- `app.bsky.notification.*` - Notification methods

---

## Phase 3: Relay Service Verification

**Location:** `Garazyk/Sources/Sync/Relay/RelayXRPCMethods.m`

**Currently Implemented:**
- `com.atproto.sync.getHead` ✅
- `com.atproto.sync.getRepo` ✅
- `com.atproto.sync.listHosts` ✅
- `com.atproto.sync.requestCrawl` ✅
- `com.atproto.sync.subscribeRepos` ✅ (via SubscribeReposHandler)

**Action:** Verify against ATProto relay spec for completeness

---

## Implementation Roadmap

```
Phase 1: Stub Fixes (by difficulty)
├── 1.1 ✅ Fix app.bsky.actor.getSuggestions     (Easiest)
├── 1.2 ✅ Fix app.bsky.graph.searchStarterPacks (Easy)  
├── 1.3 📋 Video processing                      (Medium - separate plan)
└── 1.4 📋 Chat/DM implementation                (Hard - separate plan)

Phase 2: Full Audit
├── 2.1 Fix Node.js ESM issue
├── 2.2 Run xrpc_coverage_report.js
├── 2.3 Review reports/
└── 2.4 Address missing endpoints

Phase 3: Relay Verification
└── Compare against relay spec
```

---

## Status Log

| Item | Status | Notes |
|------|--------|-------|
| app.bsky.actor.getSuggestions | 🟢 Fixed | Added TODO + cursor support |
| app.bsky.graph.searchStarterPacks | 🟢 Fixed | Added TODO + cursor support |
| chat.bsky.convo.* | 🔴 Not Started | See chat plan |
| app.bsky.video.* processing | 🔴 Not Started | See video plan |
| Full lexicon audit | 🔴 Not Started | After stubs fixed |

---

## Related Plans

- [2026-04-10-chat-conversation-support.md](./2026-04-10-chat-conversation-support.md)
- [2026-04-10-video-processing-pipeline.md](./2026-04-10-video-processing-pipeline.md)
- [2026-04-15-xrpc-service-implementation-guide.md](./2026-04-15-xrpc-service-implementation-guide.md)

---
title: "Phase 4: Unspecced/Experimental APIs Plan"
---

# Phase 4: Unspecced/Experimental APIs

> **Status:** 25% Complete (5/20 endpoints stubbed)
> **Priority:** P3 (Low)
> **Generated:** 2026-04-10

## Executive Summary

The `app.bsky.unspecced.*` namespace contains experimental and non-standard APIs. Most are not required for core PDS operation. Currently 5 endpoints are stubbed with minimal returns, and 15 are not implemented.

**Note:** These endpoints may change or be removed as the ATProto spec evolves. They are not required for federation.

---

## Current Implementation Status

### Implemented (Stubbed) - 5 endpoints
| Endpoint | Status | Location |
|----------|--------|----------|
| `app.bsky.unspecced.getConfig` | ✅ Stub | `XrpcAppBskyMethods.m:2757-2760` |
| `app.bsky.unspecced.getTaggedSuggestions` | ✅ Stub | `XrpcAppBskyMethods.m:2763-2766` |
| `app.bsky.unspecced.getPopularFeedGenerators` | ✅ Stub | `XrpcAppBskyMethods.m:2769-2772` |
| `app.bsky.unspecced.getSuggestedFeeds` | ✅ Stub | `XrpcAppBskyMethods.m:2775-2778` |
| `app.bsky.unspecced.getTrends` | ✅ Stub | (in lexicons but not registered) |

### Not Implemented - 15 endpoints

#### Age Assurance (2)
- `app.bsky.unspecced.initAgeAssurance`
- `app.bsky.unspecced.getAgeAssuranceState`

#### Starter Packs (4)
- `app.bsky.unspecced.getOnboardingSuggestedStarterPacks`
- `app.bsky.unspecced.getOnboardingSuggestedStarterPacksSkeleton`
- `app.bsky.unspecced.getSuggestedStarterPacks`
- `app.bsky.unspecced.getSuggestedStarterPacksSkeleton`

#### Skeleton/Unspecced (9)
- `app.bsky.unspecced.getPostThreadOtherV2`
- `app.bsky.unspecced.getPostThreadV2`
- `app.bsky.unspecced.getSuggestedFeedsSkeleton`
- `app.bsky.unspecced.getSuggestedUsersSkeleton`
- `app.bsky.unspecced.getSuggestionsSkeleton`
- `app.bsky.unspecced.getTrendsSkeleton`
- `app.bsky.unspecced.searchActorsSkeleton`
- `app.bsky.unspecced.searchPostsSkeleton`
- `app.bsky.unspecced.searchStarterPacksSkeleton`

---

## Tasks

### Task 4.1: Complete Stubbed Endpoints

**Goal:** Replace stub implementations with functional code

**Files:**
- Implementation: `ATProtoPDS/Sources/Network/XrpcAppBskyMethods.m`

#### 4.1a: Complete getConfig
**Current:** Returns hardcoded `@{@"checkEmailConfirmed": @NO}`

**Steps:**
1. Query actual account data for email verification status
2. Return dynamic configuration based on PDS settings
3. Include additional config flags

**Implementation:**
```objc
[dispatcher registerMethod:@"app.bsky.unspecced.getConfig" handler:^(HttpRequest *request, HttpResponse *response) {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    // Get user config from database
    NSDictionary *config = @{
        @"checkEmailConfirmed": @(emailConfirmed),
        @"labelerDefinitions": @[],
        @" generators": @[]
    };
    response.statusCode = HttpStatusOK;
    [response setJsonBody:config];
}];
```

#### 4.1b: Complete getTaggedSuggestions
**Current:** Returns empty `@{@"suggestions": @[]}`

**Steps:**
1. If no suggestions service configured, keep empty
2. If AppView proxy configured, proxy request to AppView
3. Otherwise return cached suggestions if available

#### 4.1c: Complete getPopularFeedGenerators / getSuggestedFeeds
**Current:** Returns empty feeds arrays

**Steps:**
1. These typically require AppView - implement as proxy or stub
2. Add configuration to enable/disable

---

### Task 4.2: Implement Age Assurance (Required for Compliance)

**Goal:** Support age verification for content restrictions

**Files:**
- Implementation: `ATProtoPDS/Sources/Network/XrpcAppBskyMethods.m`
- Database: Add age_assurance table

**Rationale:** Age assurance is becoming required for certain content types. Even if PDS doesn't verify age directly, it should support the protocol.

#### 4.2a: Implement initAgeAssurance
**Input:**
- `assurance`: string ("no_verification" | "verified_by_adult" | "verified_by_method")
- `methods`: array of strings (optional)

**Output:**
```objc
@{@"assurance": assurance, @"verifiedAt": timestamp}
```

**Steps:**
1. Store assurance level in account record
2. Log verification attempt (for audit)
3. Return timestamp

#### 4.2b: Implement getAgeAssuranceState
**Input:** (none - uses auth)

**Output:**
```objc
@{
    @"assurance": assurance,
    @"verifiedAt": timestamp,
    @"age": @(age) // if known
}
```

---

### Task 4.3: Implement Trending/Skeleton Endpoints

**Goal:** Support AppView proxy for trending content

**Files:**
- Implementation: `XrpcAppBskyMethods.m`
- Reference: `XrpcMethodRegistry.m` (AppView proxy pattern)

**Rationale:** Trending and skeleton endpoints are typically served by AppView. For PDS, implement as:
1. If AppView configured → proxy to AppView
2. If not → return empty/stub (client will handle)

#### Endpoints:
- `getTrends` / `getTrendsSkeleton` - Trending topics
- `getSuggestedUsersSkeleton` - Suggested users
- `getSuggestionsSkeleton` - Content suggestions
- `getSuggestedFeedsSkeleton` - Feed suggestions

**Implementation Pattern:**
```objc
[dispatcher registerMethod:@"app.bsky.unspecced.getTrendsSkeleton" handler:^(HttpRequest *request, HttpResponse *response) {
    // Check if AppView proxy configured
    NSString *appViewUrl = [[PDSConfiguration sharedConfiguration] appViewProxyURL];
    if (appViewUrl.length > 0) {
        // Proxy to AppView
        [self proxyRequestToAppView:request response:response path:@"/xrpc/app.bsky.unspecced.getTrendsSkeleton"];
    } else {
        // Return empty skeleton
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"posts": @[], @"cursor": @""}];
    }
}];
```

---

### Task 4.4: Implement Starter Pack Endpoints

**Goal:** Support onboarding starter packs

**Files:**
- Implementation: `XrpcAppBskyMethods.m`

#### Endpoints:
- `getOnboardingSuggestedStarterPacks`
- `getOnboardingSuggestedStarterPacksSkeleton`
- `getSuggestedStarterPacks`
- `getSuggestedStarterPacksSkeleton`

**Implementation:**
- Similar pattern to trending - proxy to AppView or return empty
- These are typically AppView-driven

---

### Task 4.5: Implement Search Skeleton Endpoints

**Goal:** Support search preview without full results

**Files:**
- Implementation: `XrpcAppBskyMethods.m`

#### Endpoints:
- `searchActorsSkeleton`
- `searchPostsSkeleton`
- `searchStarterPacksSkeleton`

**Implementation:**
- Return minimal response (just IDs, not full records)
- Proxy to AppView if configured

---

### Task 4.6: Implement Thread Endpoints

**Goal:** Support thread retrieval

**Files:**
- Implementation: `XrpcAppBskyMethods.m`

#### Endpoints:
- `getPostThreadV2`
- `getPostThreadOtherV2`

**Implementation:**
- These replace the v1 `getPostThread`
- Proxy to AppView or return 501 with helpful message

---

## Dependency Matrix

| Endpoint | AppView Proxy | Local | Not Required |
|----------|--------------|-------|--------------|
| getConfig | No | Yes | - |
| getTaggedSuggestions | Yes | Stub | - |
| getPopularFeedGenerators | Yes | Stub | - |
| getSuggestedFeeds | Yes | Stub | - |
| getTrends | Yes | - | - |
| initAgeAssurance | No | Yes | - |
| getAgeAssuranceState | No | Yes | - |
| getSuggestedStarterPacks | Yes | - | - |
| searchActorsSkeleton | Yes | - | - |
| searchPostsSkeleton | Yes | - | - |

---

## Dependencies

- `ATProtoPDS/Sources/Network/XrpcAppBskyMethods.m`
- `ATProtoPDS/Sources/App/PDSConfiguration.m` (for AppView URL)
- `ATProtoPDS/Sources/Network/XrpcMethodRegistry.m` (proxy pattern)

---

## Related Plans

- [Phase 2: Video Processing Pipeline](2026-04-10-video-processing-pipeline.md)
- [Phase 3: Chat/Conversation Support](2026-04-10-chat-conversation-support.md)

---

## Next Steps

These are low priority - implement only if:
1. AppView proxy is needed for client compatibility
2. Age assurance becomes required for compliance
3. Client requests specific endpoints
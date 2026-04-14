---
title: "Phase 6: Custom Extensions Plan"
---

# Phase 6: Custom Extensions

> **Status:** 0% Complete (Optional)
> **Priority:** P3 (Low)
> **Generated:** 2026-04-10

## Executive Summary

Custom extensions (`com.shinolabs.pinksea.*`) are optional and not required for core PDS operation. They implement a custom Bluesky-compatible API for the Pinksea social client. Only implement if there's a specific use case.

---

## Current Implementation Status

| Endpoint | Status | Notes |
|----------|--------|-------|
| `com.shinolabs.pinksea.getAuthorFeed` | ❌ Not implemented | Not in scope |
| `com.shinolabs.pinksea.getAuthorReplies` | ❌ Not implemented | Not in scope |

---

## Tasks

### Task 6.1: (Optional) Implement getAuthorFeed

**Goal:** Get feed for a specific author

**Files:**
- New: `Garazyk/Sources/Network/XrpcPinkseaMethods.m`

**Input:**
- `actor`: string (handle or DID)
- `limit`: integer (optional)
- `cursor`: string (optional)

**Output:**
```objc
@{
    @"feed": @[
        @{ @"post": postRecord, @"author": authorInfo },
        ...
    ],
    @"cursor": nextCursor
}
```

**Steps:**
1. Create handler file if needed
2. Query repository for author's posts
3. Return in feed format

**Implementation:**
```objc
[dispatcher registerMethod:@"com.shinolabs.pinksea.getAuthorFeed" handler:^(HttpRequest *request, HttpResponse *response) {
    NSString *actor = [request queryParamForKey:@"actor"];
    NSInteger limit = [[request queryParamForKey:@"limit"] integerValue] ?: 20;
    
    // Resolve actor to DID if needed
    NSString *did = [self resolveActorToDID:actor];
    if (!did) {
        [XrpcErrorHelper setNotFoundError:response message:@"Actor not found"];
        return;
    }
    
    // Query posts from repository
    NSArray *posts = [self.repository getRecordsForDid:did 
                                             collection:@"app.bsky.feed.post" 
                                                  limit:limit 
                                                 cursor:cursor];
    
    // Format response
    // ...
}];
```

---

### Task 6.2: (Optional) Implement getAuthorReplies

**Goal:** Get replies from a specific author

**Input:**
- `actor`: string
- `uri`: string (post URI to get replies to, optional)
- `limit`: integer
- `cursor`: string

**Output:**
```objc
@{
    @"thread": threadObject,
    @"cursor": nextCursor
}
```

**Steps:**
1. Similar to getAuthorFeed but filters for reply records
2. Include thread context
3. Return in thread format

---

## Recommendation

**Do not implement** unless:
- Specific Pinksea client compatibility is required
- Community requests support
- Custom extension namespace is needed

For most PDS deployments, these are unnecessary.

---

## Related Plans

- [Phase 5: Database Query Methods](2026-04-10-database-query-methods.md)
- [Phase 4: Unspecced/Experimental APIs](2026-04-10-unspecced-apis.md)
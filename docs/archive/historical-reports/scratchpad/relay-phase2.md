# Relay Phase 2: Event Processing

## Overview
Build event processing components for filtering, buffering, and state management.

---

## Tasks

### 2.1 Implement EventFilter

```objc
@interface BGSEventFilter : NSObject

// Filter by collection (e.g., "app.bsky.feed.post")
@property (nonatomic, strong) NSSet<NSString *> *allowedCollections;

// Filter by repo DID prefix
@property (nonatomic, strong) NSSet<NSString *> *allowedRepos;

// Filter by actor
@property (nonatomic, strong) NSSet<NSString *> *blockedActors;

// Apply filter to event
- (BOOL)shouldForwardEvent:(FirehoseCommitEvent *)event;

@end
```

**Usage:**
- Per-consumer filtering (each downstream can have different filters)
- Default: forward all events
- Filters applied after validation, before broadcast

### 2.2 Create EventBuffer (Retention Window)

```objc
@interface BGSEventBuffer : NSObject

@property (nonatomic, assign) NSUInteger retentionSeconds; // default: 86400 (24hr)
@property (nonatomic, assign) NSUInteger maxEvents; // max events in memory

// Add event to buffer
- (void)appendEvent:(NSDictionary *)event seq:(int64_t)seq;

// Get events after cursor (for backfill)
- (NSArray<NSDictionary *> *)eventsAfterCursor:(int64_t)cursor count:(NSUInteger)count;

// Prune old events
- (void)pruneExpired;

@end
```

**Implementation Notes:**
- Use circular buffer or time-bucketed storage
- Persist to SQLite for crash recovery
- Configurable retention (default 24hr per Sync v1.1 spec)

### 2.3 Create RepoStateManager

```objc
@interface BGSRepoStateManager : NSObject

// Track known repos
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *repoRoots; // did -> rootCID
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *repoSeqs; // did -> lastSeq

// Handle commit event
- (void)handleCommitEvent:(FirehoseCommitEvent *)event;

// Get cursor for repo
- (int64_t)cursorForRepo:(NSString *)repoDID;

// Persist state to SQLite
- (void)persistState;

// Load state on startup
- (void)loadState;

@end
```

### 2.4 Implement CrawlRequestHandler

**Endpoint:** `POST /xrpc/com.atproto.sync.requestCrawl`

```objc
// PDS calls this to request the relay crawl their repos
// Request: { "hostname": "pds.example.com" }
// Response: { "id": "crawl-123", "status": "queued" }
```

**Workflow:**
1. PDS sends requestCrawl with its hostname
2. BGS adds to crawl queue
3. BGS initiates subscription to that PDS
4. Crawl results stored in RepoStateManager

---

## Dependencies
- Phase 1: BGSConfiguration (for retention settings)
- Phase 1: BGSMetrics (for event counts)

## Linked Deciduous Nodes
- Node 77: Goal - Implement ATProto Relay
- Node 80: Phase 2 Action

## Status: Pending
# Relay Phase 3: XRPC Endpoints

## Overview
Implement required XRPC endpoints for relay operation.

---

## Endpoints

### 3.1 subscribeRepos (EXISTING)
**Status:** ✅ Already implemented in `SubscribeReposHandler.m`

```
GET wss://relay.example.com/xrpc/com.atproto.sync.subscribeRepos?cursor=N

Returns: WebSocket stream of firehose events
```

### 3.2 getHead
**Path:** `GET /xrpc/com.atproto.sync.getHead`

```objc
// Request: { "repo": "did:plc:..." }
// Response: { "root": "bafyre..." }

- (void)handleGetRepo:(HttpRequest *)req response:(HttpResponse *)resp {
    NSString *repo = req.queryParams[@"repo"];
    NSString *root = [self.repoStateManager rootCIDForRepo:repo];
    if (root) {
        [resp setJsonBody:@{@"root": root}];
    } else {
        resp.statusCode = 404;
    }
}
```

### 3.3 getRepo
**Path:** `GET /xrpc/com.atproto.sync.getRepo`

```objc
// Request: { "repo": "did:plc:...", "collections": ["app.bsky.feed.post"] }
// Response: HTTP 302 redirect to PDS

// Implementation: redirect to PDS URL from DID document
- (void)handleGetRepo:(HttpRequest *)req response:(HttpResponse *)resp {
    NSString *repo = req.queryParams[@"repo"];
    NSURL *pdsURL = [self resolvePDSForRepo:repo]; // from DID doc
    if (pdsURL) {
        resp.statusCode = 302;
        [resp setHeader:[pdsURL absoluteString] forKey:@"Location"];
    } else {
        resp.statusCode = 404;
    }
}
```

### 3.4 requestCrawl
**Path:** `POST /xrpc/com.atproto.sync.requestCrawl`

```objc
// Request: { "hostname": "pds.example.com" }
// Response: { "id": "crawl-123", "status": "queued" }

// Add to crawl queue (from Phase 2)
- (void)handleRequestCrawl:(HttpRequest *)req response:(HttpResponse *)resp {
    NSDictionary *body = req.jsonBody;
    NSString *hostname = body[@"hostname"];
    
    NSString *crawlId = [self.crawlQueue enqueue:hostname];
    [resp setJsonBody:@{
        @"id": crawlId,
        @"status": @"queued"
    }];
}
```

### 3.5 listHosts
**Path:** `GET /xrpc/com.atproto.sync.listHosts`

```objc
// Response: { "hosts": ["pds1.example.com", "pds2.example.com"] }

- (void)handleListHosts:(HttpRequest *)req response:(HttpResponse *)resp {
    NSArray *hosts = [self.upstreamManager activeHosts];
    [resp setJsonBody:@{@"hosts": hosts}];
}
```

### 3.6 listReposByCollection (Future)
**Path:** `GET /xrpc/com.atproto.sync.listReposByCollection`

```
Request: { "collection": "app.bsky.feed.post" }
Response: { "repos": ["did:plc:...", ...] }
```
**Status:** Not in initial scope

---

## Implementation Notes

- Add handlers to existing `XrpcMethodRegistry`
- Use existing `XrpcHandler` pattern
- All endpoints require authentication (DPoP) for upstream, none for downstream consumers

## Linked Deciduous Nodes
- Node 77: Goal - Implement ATProto Relay
- Node 81: Phase 3 Action

## Status: Pending
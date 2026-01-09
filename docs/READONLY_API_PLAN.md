# Readonly API Implementation Plan

## Goal
Complete the readonly JSON API endpoints for ATProto PDS Explorer.

## Current Working Endpoints
- `GET /explore/api/accounts` - List all accounts
- `GET /explore/api/repositories` - List accounts as repositories
- `GET /explore/api/account-records` - List records for an account
- `GET /explore/api/cid-info` - Parse and decode CID
- `POST /explore/api/create-record` - Create records

## Missing/Broken Endpoints

### 1. GET /explore/api/record?uri={uri}
**Status**: Broken - returns error, value not stored
**Fix**: Store value in records table, return it

### 2. GET /explore/api/describe?did={did}
**Status**: Partial - returns placeholder data
**Fix**: Query actual collections and root CID

### 3. GET /explore/api/collections?did={did}
**Status**: Missing
**Fix**: Query unique collections for DID

## Implementation Steps

### Phase 1: Add value column to records table

1.1 Create migration to add `value TEXT` column to records table
1.2 Update create-record to also store the JSON value
1.3 Backfill existing records with placeholder values

### Phase 2: Fix record detail endpoint

2.1 Rewrite `handleApiRecord` to query by URI
2.2 Return the stored value in response

### Phase 3: Add collections endpoint

3.1 Add `handleApiCollections` method
3.2 Query distinct collections for DID
3.3 Register endpoint

### Phase 4: Improve describe endpoint

4.1 Update `handleApiDescribe` to query real data
4.2 Return collections list and record count

## Verification

After each phase, run:
```bash
# Build and restart
xcodebuild -project ATProtoPDS.xcodeproj -scheme ATProtoPDS-CLI build
pkill -f atprotopds-cli
/Users/jack/Library/Developer/Xcode/DerivedData/ATProtoPDS-gxvfspcaobaihodzeszdnsruddhc/Build/Products/Debug/atprotopds-cli serve --port 2583 &

# Test endpoints
curl "http://localhost:2583/explore/api/record?uri=at://did:plc:g3x5vnga7kiu3oaookgeozpb/app.bsky.feed.post/test1"
curl "http://localhost:2583/explore/api/collections?did=did:plc:g3x5vnga7kiu3oaookgeozpb"
curl "http://localhost:2583/explore/api/describe?did=did:plc:g3x5vnga7kiu3oaookgeozpb"
```

## Files to Modify

- `ATProtoPDS/Sources/App/Explore/ExploreHandler.m`:
  - Add migration/column creation
  - Add handleApiCollections method
  - Update handleApiRecord to return value
  - Update handleApiDescribe with real data

## Notes

- Use sqlite3 directly (bypassing PDSDatabase) for reliability
- Store values as TEXT (JSON string)
- Generate CIDs using existing helper methods

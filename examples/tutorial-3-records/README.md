# Tutorial 3: Record Operations

This example demonstrates record CRUD operations (Create, Read, Update, Delete) with CID generation and SQLite persistence.

## What You'll Learn

- Creating records with AT URIs
- Generating CIDs for content addressing
- Retrieving records by URI
- Listing records by collection
- Deleting records
- SQLite database operations

## Building

```bash
mkdir -p build && cd build
cmake ..
make
```

## Running

```bash
./tutorial-3-records
```

## Expected Output

```
Tutorial 3: Record Operations
==============================

Test 1: Creating a record...
✓ Record created:
  URI: at://did:plc:tutorial123/app.bsky.feed.post/...
  CID: bafyrei...

Test 2: Creating another record...
✓ Record created:
  URI: at://did:plc:tutorial123/app.bsky.feed.post/...
  CID: bafyrei...

Test 3: Retrieving first record...
✓ Record retrieved:
  URI: at://did:plc:tutorial123/app.bsky.feed.post/...
  CID: bafyrei...
  Value: {
    text = "Hello from Tutorial 3!";
    createdAt = "2024-01-01T00:00:00Z";
  }

Test 4: Listing all records...
✓ Found 2 records:
  - at://did:plc:tutorial123/app.bsky.feed.post/...
    Text: This is my second post!
  - at://did:plc:tutorial123/app.bsky.feed.post/...
    Text: Hello from Tutorial 3!

Test 5: Deleting first record...
✓ Record deleted: at://did:plc:tutorial123/app.bsky.feed.post/...

Test 6: Verifying deletion...
✓ Record successfully deleted (not found)

Test 7: Listing records after deletion...
✓ Found 1 remaining records:
  - at://did:plc:tutorial123/app.bsky.feed.post/...
    Text: This is my second post!

==============================
All tests passed! ✓
Database location: ./tutorial-data
```

## Key Components

### Record Model
- `Record.h/m` — Record data model with URI, CID, value, and timestamp

### CID Generation
- `SimpleCIDGenerator.h/m` — Generates content identifiers using SHA-256

### Repository Layer
- `RecordRepository.h/m` — SQLite persistence for records

### Service Layer
- `RecordService.h/m` — Business logic for record operations

## Database Schema

```sql
CREATE TABLE records (
    uri TEXT PRIMARY KEY,
    did TEXT NOT NULL,
    collection TEXT NOT NULL,
    rkey TEXT NOT NULL,
    cid TEXT NOT NULL,
    value TEXT NOT NULL,
    created_at REAL NOT NULL,
    UNIQUE(did, collection, rkey)
);
```

## AT URI Format

Records are identified by AT URIs:
```
at://<did>/<collection>/<rkey>
```

Example:
```
at://did:plc:abc123/app.bsky.feed.post/xyz789
```

## Next Steps

- See [Tutorial 4: Authentication](../../docs/10-tutorials/tutorial-4-auth.md) for JWT verification
- See [Tutorial 5: Firehose](../../docs/10-tutorials/tutorial-5-firehose.md) for WebSocket subscriptions
- Read [Record Service](../../docs/03-application-layer/record-service.md) for production patterns
- Read [CBOR Serialization](../../docs/02-core-concepts/cbor-and-car.md) for proper encoding

## Cleanup

```bash
rm -rf tutorial-data/
```

---
title: Merkle Search Tree (MST) Implementation
---

# Merkle Search Tree (MST) Implementation

Garazyk uses Merkle Search Trees (MST) to cryptographically prove repository state. The `PDSRepositoryService` manages tree updates and persistence.

## Data Structure

An MST is a deterministic, content-addressed search tree.
- **Keys:** Record paths (e.g., `app.bsky.feed.post/3k123...`).
- **Values:** CIDs of CBOR-encoded records.
- **Nodes:** Content-addressed blocks containing key-value pairs and child pointers.

Tree height is determined by hashing keys, ensuring that identical contents result in the same root CID regardless of insertion order.

## Persistence

MST nodes are stored in each user's actor database.

```sql
CREATE TABLE mst_nodes (
    cid TEXT PRIMARY KEY,
    serialized_block BLOB NOT NULL
);
```

When a record is modified:
1. The record is encoded as CBOR to determine its CID.
2. The `PDSRepositoryService` loads the relevant branch of the tree from SQLite.
3. The new key-value pair is inserted, and nodes are split or merged according to the height algorithm.
4. New nodes are hashed and saved to the database.
5. A new signed commit points to the updated root CID.

## CAR Generation

For repository synchronization (e.g., `com.atproto.sync.getRepo`), Garazyk streams MST nodes and records into a Content Addressable aRchive (CAR).

The generator avoids buffering the entire repository:
1. It writes the CAR header with the root CID.
2. It traverses the tree nodes and yields their CID and CBOR payload directly to the HTTP output stream.

This streaming approach ensures that repositories with millions of records can be served with minimal memory overhead.

## Related

- [Repository Service](../03-application-layer/repository-service)
- [Database Layer](../05-database-layer/index)
- [Documentation Map](./documentation-map)
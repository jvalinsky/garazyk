---
title: MST Implementation Details
---

# Merkle Search Tree (MST) Implementation

Garazyk uses Merkle Search Trees (MST) to cryptographically prove the state of an actor's repository. The `PDSRepositoryService` manages the MST and persists it within each user's isolated Actor Database via the `PDSDatabasePool`.

## Core Responsibilities

1. **Commit Generation:** Mutations to a repository (creating a post, liking, following) require updating the MST. `PDSRepositoryService` computes the new tree root and generates a signed commit object.
2. **Block Serialization (CAR files):** The AT Protocol exchanges data using Content Addressable aRchives (CAR). When a client requests a repository sync, the service serializes MST blocks into a CAR stream.
3. **Repository Sync:** The MST structure allows efficient diffing between a client's known state and the server's current state for partial syncs.

## The MST Data Structure

An MST is a deterministic, content-addressed search tree.
- **Keys** are record paths (e.g., `app.bsky.feed.post/3k123...`).
- **Values** are the CID (Content Identifier) of the CBOR-encoded record.
- **Nodes** contain key-value pairs and CIDs pointing to child nodes.
- **Tree height** is determined by hashing the keys. Identical contents always result in the same tree structure and root CID, regardless of insertion order.

## Database Integration

Loading the entire MST into memory for every operation is not viable because SQLite is the storage engine. 

`PDSDatabasePool` stores MST nodes in the Actor DB. A typical table schema for nodes:

```sql
CREATE TABLE mst_nodes (
    cid TEXT PRIMARY KEY,
    serialized_block BLOB NOT NULL
);
```

When a record is inserted:
1. The system encodes the record to CBOR and computes its CID.
2. `PDSRepositoryService` loads only the required path of MST nodes from the database.
3. The system inserts the new key-value pair, splitting or merging nodes based on the deterministic height algorithm.
4. The system hashes new nodes and saves their CBOR representations to the database.
5. `PDSRepositoryService` generates a new signed commit object pointing to the new root CID.

## Block Serialization and CAR Generation

The AT Protocol requires serving MST nodes and record blocks via CAR files for methods like `com.atproto.sync.getRepo`.

Garazyk implements a stream-oriented CAR generator. It avoids buffering the entire repository:
1. It writes the CAR header with the root CID.
2. It traverses the requested MST nodes.
3. It yields the CID and CBOR payload directly to the `HttpServer` output stream for each node and record block.

Streaming prevents buffering the repository into memory, even when serving repositories with hundreds of thousands of records.
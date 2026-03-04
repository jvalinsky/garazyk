---
title: Merkle Search Trees (MST)
---

# Merkle Search Trees (MST)

## Why This Matters

Traditional databases use indexes and primary keys to organize data. But in a decentralized network where data moves between servers, you need a data structure that:
- **Proves integrity** — Any tampering is immediately detectable
- **Enables efficient sync** — Servers can quickly identify differences
- **Maintains order** — Records can be efficiently queried by key
- **Produces verifiable state** — A single hash proves the entire repository state

Merkle Search Trees (MSTs) provide all of these properties. They're the backbone of AT Protocol repositories, enabling users to move their data between servers while maintaining cryptographic proof that nothing was altered.

## Real-World Scenario

Imagine Alice has 10,000 posts on Server A and wants to migrate to Server B. Without MSTs, Server B would need to:
1. Download all 10,000 posts
2. Verify each post individually
3. Hope nothing was corrupted or tampered with

With MSTs, the process is elegant:
1. Server B requests Alice's root CID from Server A
2. Server B compares its local root CID (if any) with Server A's
3. If they differ, Server B walks the tree structure to identify exactly which records differ
4. Server B downloads only the changed records (maybe just 50 recent posts)
5. Server B verifies the entire repository by recomputing the root CID

This is the power of Merkle trees: efficient synchronization with cryptographic verification.

## Overview

A Merkle Search Tree (MST) is a data structure that stores all records in a repository. It provides:
- **Efficient lookups** — O(log n) time complexity
- **Deterministic hashing** — Same records always produce same root CID
- **Efficient synchronization** — Differences can be computed without comparing all records
- **Verifiable state** — Root CID proves repository state

## MST Structure

### Tree Organization

An MST is organized as a binary tree where:
- **Leaf nodes** — Contain actual records
- **Internal nodes** — Contain hashes of child nodes
- **Root node** — Hash of entire tree

<!-- Image placeholder: MST Tree Structure -->

```

                    Root CID
                   /        \
              Node A          Node B
             /      \        /      \
          Leaf1   Leaf2   Leaf3   Leaf4
         (rec1)  (rec2)  (rec3)  (rec4)
```

### Node Structure

Each node contains:
- **Key** — Lexicographic key for the record
- **Value** — CID of the record (for leaf nodes) or hash (for internal nodes)
- **Left child** — Pointer to left subtree
- **Right child** — Pointer to right subtree

### Key Ordering

Records are ordered lexicographically by key:
```

app.bsky.feed.like/abc123
app.bsky.feed.like/def456
app.bsky.feed.post/ghi789
app.bsky.feed.post/jkl012
```

## MST Operations

### Insertion

To insert a record:

```objc
// In MST.m
- (void)insertRecord:(NSDictionary *)record 
              forKey:(NSString *)key {
    // 1. Calculate CID of record
    NSData *cbor = [ATProtoCBORSerialization encodeObject:record error:nil];
    NSString *recordCID = [CID calculateCIDForData:cbor];
    
    // 2. Insert into tree
    self.root = [self insertNode:self.root 
                         forKey:key 
                        withCID:recordCID];
    
    // 3. Recalculate root CID
    self.rootCID = [self calculateNodeCID:self.root];
}

- (MSTNode *)insertNode:(MSTNode *)node 
                forKey:(NSString *)key 
               withCID:(NSString *)cid {
    if (node == nil) {
        // Create new leaf node
        return [[MSTNode alloc] initWithKey:key value:cid];
    }
    
    NSComparisonResult cmp = [key compare:node.key];
    
    if (cmp < 0) {
        // Insert in left subtree
        node.left = [self insertNode:node.left forKey:key withCID:cid];
    } else if (cmp > 0) {
        // Insert in right subtree
        node.right = [self insertNode:node.right forKey:key withCID:cid];
    } else {
        // Update existing node
        node.value = cid;
    }
    
    return node;
}
```

### Lookup

To find a record:

```objc
// In MST.m
- (NSString *)lookupCIDForKey:(NSString *)key {
    return [self lookupInNode:self.root forKey:key];
}

- (NSString *)lookupInNode:(MSTNode *)node forKey:(NSString *)key {
    if (node == nil) {
        return nil;
    }
    
    NSComparisonResult cmp = [key compare:node.key];
    
    if (cmp < 0) {
        return [self lookupInNode:node.left forKey:key];
    } else if (cmp > 0) {
        return [self lookupInNode:node.right forKey:key];
    } else {
        return node.value;  // Found
    }
}
```

### Range Query

To find all records in a key range:

```objc
// In MST.m
- (NSArray *)recordsInRange:(NSString *)startKey 
                    endKey:(NSString *)endKey {
    NSMutableArray *results = [NSMutableArray array];
    [self collectInRange:self.root 
              startKey:startKey 
                endKey:endKey 
               results:results];
    return results;
}

- (void)collectInRange:(MSTNode *)node 
             startKey:(NSString *)startKey 
               endKey:(NSString *)endKey 
              results:(NSMutableArray *)results {
    if (node == nil) return;
    
    // Check if node key is in range
    if ([node.key compare:startKey] >= 0 && 
        [node.key compare:endKey] <= 0) {
        [results addObject:@{@"key": node.key, @"cid": node.value}];
    }
    
    // Recurse into left subtree if needed
    if ([node.key compare:startKey] > 0) {
        [self collectInRange:node.left 
                  startKey:startKey 
                    endKey:endKey 
                   results:results];
    }
    
    // Recurse into right subtree if needed
    if ([node.key compare:endKey] < 0) {
        [self collectInRange:node.right 
                  startKey:startKey 
                    endKey:endKey 
                   results:results];
    }
}
```

## CID Calculation

### Deterministic Hashing

The root CID is calculated deterministically:

```objc
// In MST.m
- (NSString *)calculateNodeCID:(MSTNode *)node {
    if (node == nil) {
        return nil;
    }
    
    // 1. Encode node as CBOR
    NSDictionary *nodeData = @{
        @"key": node.key,
        @"value": node.value,
        @"left": [self calculateNodeCID:node.left] ?: [NSNull null],
        @"right": [self calculateNodeCID:node.right] ?: [NSNull null]
    };
    
    NSData *cbor = [ATProtoCBORSerialization encodeObject:nodeData error:nil];
    
    // 2. Calculate CID (hash of CBOR)
    NSString *cid = [CID calculateCIDForData:cbor];
    
    return cid;
}
```

### Root CID

The root CID is the hash of the entire tree:

```objc
// In MST.m
- (NSString *)rootCID {
    return [self calculateNodeCID:self.root];
}
```

## Synchronization

### Diff Calculation

To sync two repositories, calculate the difference:

```objc
// In PDSRepositoryService.m
- (NSArray *)diffMST:(MST *)localMST 
           remoteMST:(MST *)remoteMST {
    NSMutableArray *diffs = [NSMutableArray array];
    
    // 1. Compare root CIDs
    if ([localMST.rootCID isEqualToString:remoteMST.rootCID]) {
        return @[];  // No differences
    }
    
    // 2. Recursively find differences
    [self diffNodes:localMST.root 
        remoteNode:remoteMST.root 
             diffs:diffs];
    
    return diffs;
}

- (void)diffNodes:(MSTNode *)localNode 
       remoteNode:(MSTNode *)remoteNode 
            diffs:(NSMutableArray *)diffs {
    if (localNode == nil && remoteNode == nil) {
        return;
    }
    
    if (localNode == nil) {
        // Remote has record that local doesn't
        [diffs addObject:@{@"type": @"add", @"key": remoteNode.key, @"cid": remoteNode.value}];
        return;
    }
    
    if (remoteNode == nil) {
        // Local has record that remote doesn't
        [diffs addObject:@{@"type": @"remove", @"key": localNode.key}];
        return;
    }
    
    NSComparisonResult cmp = [localNode.key compare:remoteNode.key];
    
    if (cmp < 0) {
        // Local has record that remote doesn't
        [diffs addObject:@{@"type": @"remove", @"key": localNode.key}];
        [self diffNodes:localNode.right remoteNode:remoteNode diffs:diffs];
    } else if (cmp > 0) {
        // Remote has record that local doesn't
        [diffs addObject:@{@"type": @"add", @"key": remoteNode.key, @"cid": remoteNode.value}];
        [self diffNodes:localNode remoteNode:remoteNode.right diffs:diffs];
    } else {
        // Same key, check if values differ
        if (![localNode.value isEqualToString:remoteNode.value]) {
            [diffs addObject:@{@"type": @"update", @"key": localNode.key, @"cid": remoteNode.value}];
        }
        [self diffNodes:localNode.left remoteNode:remoteNode.left diffs:diffs];
        [self diffNodes:localNode.right remoteNode:remoteNode.right diffs:diffs];
    }
}
```

## Commit Processing

### Creating a Commit

When records are modified, a new commit is created:

```objc
// In PDSRepositoryService.m
- (void)createCommitWithChanges:(NSArray *)changes 
                      completion:(void (^)(NSString *commitCID, NSError *error))completion {
    // 1. Apply changes to MST
    for (NSDictionary *change in changes) {
        NSString *key = change[@"key"];
        NSString *cid = change[@"cid"];
        [self.mst insertRecord:@{} forKey:key];  // Simplified
    }
    
    // 2. Calculate new root CID
    NSString *rootCID = self.mst.rootCID;
    
    // 3. Create commit object
    NSDictionary *commit = @{
        @"root": rootCID,
        @"prev": self.lastCommitCID ?: [NSNull null],
        @"timestamp": [NSDate date],
        @"did": self.did
    };
    
    // 4. Sign commit
    NSData *commitData = [ATProtoCBORSerialization encodeObject:commit error:nil];
    NSString *signature = [self signData:commitData];
    
    // 5. Create commit CID
    NSDictionary *signedCommit = @{
        @"commit": commit,
        @"signature": signature
    };
    NSData *signedData = [ATProtoCBORSerialization encodeObject:signedCommit error:nil];
    NSString *commitCID = [CID calculateCIDForData:signedData];
    
    // 6. Store commit
    [self storeCommit:signedCommit withCID:commitCID];
    
    completion(commitCID, nil);
}
```

## Performance Characteristics

### Time Complexity

| Operation | Complexity | Notes |
|-----------|-----------|-------|
| Insert | O(log n) | Balanced tree |
| Lookup | O(log n) | Binary search |
| Range query | O(log n + k) | k = results |
| Diff | O(log n) | Only different branches |

### Space Complexity

- **O(n)** — n = number of records
- **Efficient storage** — Only store changed nodes

### Why These Characteristics Matter

The O(log n) complexity means that even with millions of records, operations remain fast. A repository with 1 million records requires only about 20 comparisons to find any record (log₂(1,000,000) ≈ 20). This is crucial for real-time applications where users expect instant responses.

The diff operation's O(log n) complexity is particularly important for synchronization. Instead of comparing all records, the algorithm only traverses branches where the CIDs differ. In practice, this means syncing a repository with 100,000 records might only require examining a few hundred nodes if only recent posts have changed.

### Design Trade-offs

**Why not use a hash table?** Hash tables provide O(1) lookups but don't support:
- Range queries (finding all posts in a date range)
- Ordered iteration (displaying posts chronologically)
- Efficient diff computation (identifying changes between repositories)

**Why not use a B-tree?** B-trees are excellent for databases but don't provide:
- Cryptographic verification (Merkle property)
- Content addressing (deterministic CIDs)
- Efficient network synchronization

MSTs combine the best of both worlds: the efficiency of binary search trees with the verifiability of Merkle trees.

## Best Practices

1. **Keep MST balanced** — Prevents O(n) operations
2. **Cache root CID** — Avoid recalculating
3. **Batch operations** — Group inserts/updates
4. **Verify signatures** — Always verify commit signatures
5. **Monitor tree depth** — Alert if tree becomes unbalanced

## Next Steps

- **[Cryptography](cryptography)** — Cryptographic operations
- **[Repository Protocol](../07-repository-protocol/repository-basics)** — Repository operations
- **[Sync & Firehose](../08-sync-firehose/firehose-overview)** — Real-time synchronization

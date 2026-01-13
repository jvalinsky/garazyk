# Chapter 6: Merkle Search Trees (MST)

The Merkle Search Tree is the heart of an AT Protocol repository. It provides a content-addressed, ordered key-value store where any change produces a new cryptographic root hash. This chapter covers implementing the MST from scratch.

## What is a Merkle Search Tree?

An MST combines two concepts:

1. **Merkle Tree**: A tree where each node's identity is the hash of its contents, providing cryptographic integrity
2. **Search Tree**: An ordered structure supporting efficient key lookup, insertion, and deletion

```
        ┌─────────────┐
        │   Root CID  │  ← Hash of entire tree state
        └──────┬──────┘
               ↓
        ┌─────────────┐
        │  MST Node   │  entries: [{key, value, subtree}, ...]
        └──────┬──────┘
               ↓
    ┌──────────┴──────────┐
    ↓                     ↓
 ┌──────┐            ┌──────┐
 │ Node │            │ Node │
 └──────┘            └──────┘
```

## Key Depth: Probabilistic Tree Balancing

The MST uses a clever technique for probabilistic balancing. Each key's **depth** in the tree is determined by counting leading zero bits in its SHA-256 hash:

```objc
+ (uint32_t)keyDepth:(NSString *)key {
    const char *utf8 = [key UTF8String];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(utf8, (CC_LONG)strlen(utf8), hash);

    uint32_t zeroCount = 0;
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        uint8_t byte = hash[i];
        if (byte == 0) {
            zeroCount += 4;  // Count 4 "half-bytes" for full zero byte
            continue;
        }
        // Count leading zero bits in first non-zero byte
        if ((byte & 0xC0) != 0) break;
        if ((byte & 0xFC) == 0) zeroCount += 3;
        else if ((byte & 0xF0) == 0) zeroCount += 2;
        else zeroCount += 1;
        break;
    }
    return zeroCount;
}
```

**Why this works:**
- Most keys have low depth (near root)
- Rare keys with more leading zeros go deeper
- Provides O(log n) average tree height
- Deterministic: same key always gets same depth

## MST Node Structure

Each MST node contains:

```objc
@interface MSTNode : NSObject

@property (nonatomic, assign, readonly) uint32_t level;     // Node's level in tree
@property (nonatomic, strong, readonly) MSTNode *left;       // Left subtree (optional)
@property (nonatomic, copy, readonly) NSArray<MSTNodeEntry *> *entries;

@end

@interface MSTNodeEntry : NSObject

@property (nonatomic, copy) NSString *fullKey;     // The record key
@property (nonatomic, strong) CID *value;          // CID of record content
@property (nonatomic, strong) MSTNode *tree;       // Right subtree (optional)

@end
```

**Node invariants:**
1. Entries within a node are sorted by key
2. All keys in left subtree < first entry's key
3. All keys between entries[i] and entries[i+1] are in entries[i].tree
4. Node level ≥ levels of all child nodes

## CBOR Serialization of Nodes

Nodes are serialized as DAG-CBOR for content addressing:

```objc
- (NSData *)serializeToCBOR:(NSMapTable<MSTNode *, CID *> *)cache {
    NSMutableArray<CBORValue *> *entriesCBOR = [NSMutableArray array];
    NSString *prevKey = @"";
    
    for (MSTNodeEntry *entry in self.entries) {
        // Calculate common prefix length with previous key
        NSUInteger prefixLen = 0;
        NSUInteger minLen = MIN(prevKey.length, entry.fullKey.length);
        for (NSUInteger i = 0; i < minLen; i++) {
            if ([prevKey characterAtIndex:i] == [entry.fullKey characterAtIndex:i]) {
                prefixLen++;
            } else {
                break;
            }
        }
        
        // Entry structure: {p: prefixLen, k: keySuffix, v: valueCID, t: subtreeCID}
        NSMutableDictionary<CBORValue *, CBORValue *> *dict = [NSMutableDictionary dictionary];
        
        // p: prefix length (how many chars shared with previous key)
        dict[[CBORValue textString:@"p"]] = [CBORValue unsignedInteger:prefixLen];
        
        // k: key suffix (remaining chars after prefix)
        NSString *suffix = [entry.fullKey substringFromIndex:prefixLen];
        dict[[CBORValue textString:@"k"]] = [CBORValue byteString:
            [suffix dataUsingEncoding:NSUTF8StringEncoding]];
        
        // v: value CID (using tag 42 for CID link)
        NSMutableData *vData = [NSMutableData dataWithBytes:"\x00" length:1];
        [vData appendData:entry.value.bytes];
        dict[[CBORValue textString:@"v"]] = [CBORValue tag:42 
            value:[CBORValue byteString:vData]];
        
        // t: subtree CID (null if no subtree)
        if (entry.tree) {
            CID *treeCID = [entry.tree getCID:cache];
            NSMutableData *tData = [NSMutableData dataWithBytes:"\x00" length:1];
            [tData appendData:treeCID.bytes];
            dict[[CBORValue textString:@"t"]] = [CBORValue tag:42 
                value:[CBORValue byteString:tData]];
        } else {
            dict[[CBORValue textString:@"t"]] = [CBORValue nilValue];
        }
        
        [entriesCBOR addObject:[CBORValue map:dict]];
        prevKey = entry.fullKey;
    }
    
    // Node structure: {e: entries, l: leftSubtreeCID}
    NSMutableDictionary<CBORValue *, CBORValue *> *nodeDict = [NSMutableDictionary dictionary];
    nodeDict[[CBORValue textString:@"e"]] = [CBORValue array:entriesCBOR];
    
    if (self.left) {
        CID *leftCID = [self.left getCID:cache];
        NSMutableData *lData = [NSMutableData dataWithBytes:"\x00" length:1];
        [lData appendData:leftCID.bytes];
        nodeDict[[CBORValue textString:@"l"]] = [CBORValue tag:42 
            value:[CBORValue byteString:lData]];
    } else {
        nodeDict[[CBORValue textString:@"l"]] = [CBORValue nilValue];
    }
    
    return [[CBORValue map:nodeDict] encode];
}
```

## Computing Node CIDs

Each node's CID is computed by hashing its CBOR serialization:

```objc
- (CID *)getCID:(NSMapTable<MSTNode *, CID *> *)cache {
    CID *cached = [cache objectForKey:self];
    if (cached) return cached;
    
    NSData *cbor = [self serializeToCBOR:cache];
    // Use dag-cbor codec (0x71) with SHA-256 multihash
    CID *cid = [CID cidWithDigest:[CID sha256Digest:cbor] codec:0x71];
    [cache setObject:cid forKey:self];
    return cid;
}
```

## Tree Operations

### Get: Looking Up a Key

```objc
- (CID *)getRecursive:(MSTNode *)node key:(NSString *)key {
    if (!node) return nil;
    
    // Binary search for key position
    NSInteger idx = 0;
    while (idx < node.entries.count && 
           [node.entries[idx].fullKey compare:key] == NSOrderedAscending) {
        idx++;
    }
    
    // Found exact match?
    if (idx < node.entries.count && 
        [node.entries[idx].fullKey isEqualToString:key]) {
        return node.entries[idx].value;
    }
    
    // Recurse into appropriate subtree
    MSTNode *subtree = (idx == 0) ? node.left : node.entries[idx-1].tree;
    return [self getRecursive:subtree key:key];
}
```

### Put: Inserting or Updating

The put operation is more complex because we need to maintain tree structure:

```objc
- (void)put:(NSString *)key valueCID:(CID *)valueCID {
    NSString *fullKey = key;
    uint32_t depth = [MST keyDepth:fullKey];
    self.root = [self addRecursive:self.root key:fullKey value:valueCID depth:depth];
}

- (MSTNode *)addRecursive:(MSTNode *)node 
                      key:(NSString *)key 
                    value:(CID *)value 
                    depth:(uint32_t)depth {
    if (!node) node = [[MSTNode alloc] initWithLevel:0];
    
    // If key's depth is greater than current node's level,
    // we need to split and create a new higher-level node
    if (depth > node.level) {
        MSTNode *splitLeft = nil;
        MSTNode *splitRight = nil;
        [node split:key left:&splitLeft right:&splitRight];
        
        // Build up intermediate levels if needed
        MSTNode *left = splitLeft;
        MSTNode *right = splitRight;
        for (uint32_t i = node.level + 1; i < depth; i++) {
            if (left) left = [[MSTNode alloc] initWithLevel:i left:left entries:@[]];
            if (right) right = [[MSTNode alloc] initWithLevel:i left:right entries:@[]];
        }
        
        // Create new entry and node at correct depth
        MSTNodeEntry *newEntry = [[MSTNodeEntry alloc] 
            initWithKey:key value:value tree:right];
        return [[MSTNode alloc] initWithLevel:depth left:left entries:@[newEntry]];
    }
    
    // Find insertion point
    NSInteger idx = 0;
    while (idx < node.entries.count && 
           [node.entries[idx].fullKey compare:key] == NSOrderedAscending) {
        idx++;
    }
    
    // Update existing entry if key matches
    if (idx < node.entries.count && 
        [node.entries[idx].fullKey isEqualToString:key]) {
        MSTNodeEntry *oldEntry = node.entries[idx];
        MSTNodeEntry *newEntry = [[MSTNodeEntry alloc] 
            initWithKey:key value:value tree:oldEntry.tree];
        NSMutableArray *newEntries = [node.entries mutableCopy];
        newEntries[idx] = newEntry;
        return [[MSTNode alloc] initWithLevel:node.level 
                                         left:node.left entries:newEntries];
    }
    
    // Insert new entry or recurse into subtree
    // ... (full implementation in source)
}
```

### Delete: Removing a Key

```objc
- (void)delete:(NSString *)key {
    self.root = [self deleteRecursive:self.root key:key];
    if (!self.root) self.root = [[MSTNode alloc] initWithLevel:0];
}

- (MSTNode *)deleteRecursive:(MSTNode *)node key:(NSString *)key {
    if (!node) return nil;
    
    // Find the entry
    NSInteger idx = 0;
    while (idx < node.entries.count && 
           [node.entries[idx].fullKey compare:key] == NSOrderedAscending) {
        idx++;
    }
    
    // Found it - merge left and right subtrees
    if (idx < node.entries.count && 
        [node.entries[idx].fullKey isEqualToString:key]) {
        MSTNodeEntry *entryToDelete = node.entries[idx];
        MSTNode *leftSubtree = (idx == 0) ? node.left : node.entries[idx-1].tree;
        MSTNode *rightSubtree = entryToDelete.tree;
        
        MSTNode *merged = [self merge:leftSubtree and:rightSubtree];
        
        NSMutableArray *newEntries = [node.entries mutableCopy];
        [newEntries removeObjectAtIndex:idx];
        
        // Update references and return trimmed node
        // ...
    }
    
    // Recurse into subtree
    // ...
}
```

## Walking the Tree

Enumerate all entries in sorted order:

```objc
- (NSArray<MSTEntry *> *)allEntries {
    NSMutableArray<MSTEntry *> *result = [NSMutableArray array];
    [self walk:self.root callback:^(MSTNodeEntry *entry) {
        [result addObject:[MSTEntry entryWithKey:entry.fullKey valueCID:entry.value]];
    }];
    return result;
}

- (void)walk:(MSTNode *)node callback:(void(^)(MSTNodeEntry *))callback {
    if (!node) return;
    
    // Walk left subtree first (smaller keys)
    if (node.left) [self walk:node.left callback:callback];
    
    // Process entries in order
    for (MSTNodeEntry *entry in node.entries) {
        callback(entry);
        // Then walk right subtree of this entry
        if (entry.tree) [self walk:entry.tree callback:callback];
    }
}
```

## Practical Example: Building a Repository Tree

```objc
// Create empty MST
MST *mst = [[MST alloc] init];

// Add some records
CID *profileCID = [CID sha256:profileData];
[mst put:@"app.bsky.actor.profile/self" valueCID:profileCID];

CID *postCID = [CID sha256:postData];
[mst put:@"app.bsky.feed.post/3jwdwj2ctlk26" valueCID:postCID];

CID *likeCID = [CID sha256:likeData];
[mst put:@"app.bsky.feed.like/3jwdwj2ctlk27" valueCID:likeCID];

// Get root CID (represents entire tree state)
CID *rootCID = mst.rootCID;
NSLog(@"Repository root: %@", rootCID.stringValue);

// List all entries
for (MSTEntry *entry in mst.allEntries) {
    NSLog(@"%@ -> %@", entry.key, entry.valueCID.stringValue);
}

// Query by prefix
NSArray *posts = [mst entriesWithPrefix:@"app.bsky.feed.post/"];
```

## Summary

In this chapter, you learned:

- ✅ MST structure: nodes, entries, and subtrees
- ✅ Key depth calculation via SHA-256 leading zeros
- ✅ DAG-CBOR serialization of nodes
- ✅ Computing node CIDs for content addressing
- ✅ Tree operations: get, put, delete
- ✅ In-order tree traversal

## Key Takeaways

1. **Content-addressed**: Any change creates new root CID
2. **Deterministic**: Same data always produces same tree structure
3. **Efficient**: O(log n) operations via probabilistic balancing
4. **Verifiable**: Root CID proves entire tree state

## Next Steps

In **Chapter 7**, we'll implement **CAR files and Repository Commits**—packaging MST nodes into portable archives and signing repository state.

---

**Files Referenced in This Chapter:**
- [MST.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Repository/MST.h)
- [MST.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Repository/MST.m)

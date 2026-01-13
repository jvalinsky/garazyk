# Chapter 6: Merkle Search Trees

In the previous chapter, we learned how to serialize data structures to DAG-CBOR—deterministic encoding that produces consistent content identifiers. But how do we organize thousands of records in a way that's both searchable and cryptographically verifiable?

This chapter introduces the **Merkle Search Tree (MST)**—the data structure at the heart of every AT Protocol repository. It combines the integrity of Merkle trees with the efficiency of search trees to create a content-addressed, ordered key-value store.

## What You'll Learn

By the end of this chapter, you'll be able to:
- Understand why MSTs are necessary for repository integrity
- Calculate key depth using SHA-256 leading zero bits
- Build MST nodes with proper structure and invariants
- Serialize nodes to DAG-CBOR with prefix compression
- Implement get, put, and delete operations
- Verify repository state using root CIDs

## Prerequisites

This chapter assumes you understand:
- **Content Identifiers (CIDs)** - cryptographic hashing and addressing (Chapter 4)
- **DAG-CBOR serialization** - deterministic encoding (Chapter 5)
- **Basic tree data structures** - nodes, children, traversal
- **Binary search** - finding elements in sorted sequences

If you're not comfortable with these, especially CIDs and DAG-CBOR, review those chapters first.

---

## The Problem: Verifiable Key-Value Storage

### Why Repositories Need Special Data Structures

Imagine Alice has a repository with 10,000 posts, likes, and follows. Bob wants to sync Alice's repository to his server. How does Bob know:
- He received all records (nothing missing)?
- Records weren't tampered with (integrity)?
- The repository state matches what Alice sent?

**Traditional approach:**
```
Send all 10,000 records → Bob saves them → Hope nothing went wrong
```

**Problems:**
- No integrity check (records could be modified in transit)
- No completeness check (could be missing records)
- Can't efficiently verify incremental updates

### The Vision: Content-Addressed Repository

What if the entire repository state could be summarized by a single hash?

```
Repository State = Hash of all records + their organization

Alice sends: "My repository root hash is bafyrei..."
Bob downloads records
Bob computes hash → Verifies it matches

Match? → Repository is complete and correct
Mismatch? → Something's wrong, retry
```

This is what MSTs provide: **cryptographic verification of entire repository state** using a single root CID.

---

## What is a Merkle Search Tree?

An MST combines two classic data structures:

### 1. Merkle Tree (Integrity)

```
         ┌─────────┐
         │ Root Hash│  ← Hash of all children
         └────┬────┘
              │
       ┌──────┴──────┐
       ▼              ▼
   ┌───────┐      ┌───────┐
   │ Hash A│      │ Hash B│
   └───┬───┘      └───┬───┘
       │              │
   ┌───┴───┐      ┌───┴───┐
   ▼       ▼      ▼       ▼
Data 1  Data 2  Data 3  Data 4
```

**Properties:**
- Each node's hash depends on its children
- Any change propagates up to root
- Root hash proves entire tree contents

### 2. Search Tree (Ordered Access)

```
        ┌───────┐
        │   M   │  ← Middle key
        └───┬───┘
            │
    ┌───────┴───────┐
    ▼               ▼
┌───────┐       ┌───────┐
│   E   │       │   T   │
└───────┘       └───────┘
  │                 │
  └─ Keys < M       └─ Keys > M
```

**Properties:**
- Keys are ordered (lexicographic)
- Efficient lookup: O(log n)
- Supports range queries (find all keys with prefix "app.bsky.feed.*")

### Combining Them: MST

```
        ┌─────────────────┐
        │   Root CID      │  ← Hash of entire structure
        │   Level: 2      │     AND ordered keys
        └────────┬────────┘
                 │
        ┌────────┴────────┐
        ▼                 ▼
    ┌───────┐         ┌───────┐
    │Node CID│       │Node CID│
    │Level: 1│       │Level: 1│
    └───────┘         └───────┘
        │                 │
    Sorted keys      Sorted keys
```

**MST provides:**
- ✅ Cryptographic integrity (Merkle tree)
- ✅ Efficient lookup (search tree)
- ✅ Ordered enumeration (search tree)
- ✅ Deterministic structure (same data → same tree)
- ✅ Content addressing (change anything → new root CID)

---

## The Intuition: A Probabilistic Building

### The Analogy: Multi-Story Department Store

Think of an MST like a department store with multiple floors:

```
Floor 3 (Rare):        [⭐ Premium Items]         ← Very few items
                             │
Floor 2 (Uncommon):   [📚 Specialty Goods]       ← Some items
                             │
Floor 1 (Common):     [🛒 Everyday Products]     ← Most items
                             │
Floor 0 (Ground):     [📦 All Remaining Items]   ← Everything else
```

**Rules:**
- Most products go on ground floor (common)
- Some products promoted to Floor 1 based on "random lottery"
- Even fewer reach Floor 2
- Rare few reach Floor 3

**Why this works:**
- Tall customers can see over short sections (tree isn't too deep)
- Distribution is probabilistic but balanced
- Everyone can find products quickly
- No reorganization needed when inventory changes

### How MST Applies This

Each key gets a "lottery number" based on its hash:
- Count leading zeros in hash → determines floor/level
- Most keys: 0-1 leading zeros (ground floor)
- Some keys: 2-3 leading zeros (Floor 1-2)
- Rare keys: 4+ leading zeros (higher floors)

**Example:**
```
Key: "app.bsky.feed.post/abc123"
Hash: 0x1A3F... → Starts with 0001... (3 leading zero bits)
Depth: 3 (this key goes on Floor 3)

Key: "app.bsky.feed.post/xyz789"
Hash: 0xF712... → Starts with 1111... (0 leading zero bits)
Depth: 0 (ground floor)
```

This **probabilistic balancing** ensures:
- Tree stays roughly balanced (O(log n) height)
- Deterministic (same key always gets same depth)
- No rebalancing rotations needed (simpler than red-black trees)

---

## Key Depth: The Lottery System

### Computing Depth from Hash

<script setup>
const keyDepthCode = `#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>

uint32_t keyDepth(NSString *key) {
    if (!key) return 0;
    
    // 1. Hash the key (SHA-256)
    const char *utf8 = [key UTF8String];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(utf8, (CC_LONG)strlen(utf8), hash);

    // 2. Count leading zero bits (in nibbles/half-bytes)
    uint32_t zeroCount = 0;

    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        uint8_t byte = hash[i];

        if (byte == 0) {
            zeroCount += 4; // 2 nibbles
            continue;
        }

        // First non-zero byte
        if ((byte & 0xC0) == 0) zeroCount++; // 11...
        if ((byte & 0xF0) == 0) zeroCount++; // 0011...
        // Note: simplified counting for demonstration
        // Just checking top bits for 0s
        if ((byte & 0xFC) == 0) zeroCount += 3;
        else if ((byte & 0xF0) == 0) zeroCount += 2;
        else if ((byte & 0xC0) == 0) zeroCount += 1;
        
        break;
    }
    
    return zeroCount;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray *keys = @[
            @"app.bsky.feed.post/123",
            @"app.bsky.feed.post/456",
            @"app.bsky.feed.post/789",
            @"app.bsky.feed.like/common",
            @"app.bsky.feed.like/rare"
        ];
        
        for (NSString *key in keys) {
            printf("Depth: %u  Key: %s\\n", keyDepth(key), key.UTF8String);
        }
    }
    return 0;
}`;

const prefixCompressionCode = `#import <Foundation/Foundation.h>

void compressKeys(NSArray<NSString *> *keys) {
    NSString *prevKey = @"";
    printf("Compression Analysis:\\n");
    printf("---------------------\\n");
    
    for (NSString *key in keys) {
        NSUInteger prefixLen = 0;
        NSUInteger minLen = MIN(prevKey.length, key.length);
        
        for (NSUInteger i = 0; i < minLen; i++) {
            if ([prevKey characterAtIndex:i] == [key characterAtIndex:i]) {
                prefixLen++;
            } else {
                break;
            }
        }
        
        NSString *suffix = [key substringFromIndex:prefixLen];
        printf("Key:    %s\\n", key.UTF8String);
        printf("Prefix: %lu chars shared with '%s'\\n", (unsigned long)prefixLen, prevKey.UTF8String);
        printf("Suffix: %s\\n", suffix.UTF8String);
        printf("Status: %s\\n\\n", prefixLen > 0 ? "COMPRESSED" : "FULL KEY");
        
        prevKey = key;
    }
}

int main() {
    @autoreleasepool {
        NSArray *keys = @[
            @"app.bsky.feed.post/abc",
            @"app.bsky.feed.post/xyz",
            @"app.bsky.feed.post/zzz"
        ];
        compressKeys(keys);
    }
    return 0;
}`;
</script>

<ObjcRunner :initialCode="keyDepthCode" />

### Step-by-Step Example

Let's calculate depth for key "app.bsky.feed.post/123":

```
Step 1: Hash the key
key = "app.bsky.feed.post/123"
SHA256(key) = 0x0D 0x3F 0xA1 0x5B ...
              └──┘ First byte
              0000 1101 in binary

Step 2: Count leading zero bits in first non-zero byte
0x0D = 0000 1101
       ^^^^
       4 leading zeros

But we count in half-bytes (nibbles):
0000 → 2 half-bytes (0 and 0)
1101 → stops here

Result: depth = 2
```

**Another example:**

```
key = "app.bsky.feed.like/456"
SHA256(key) = 0x00 0x00 0x1A 0x3F ...
              └──┘ └──┘ └──┘
              Full zero bytes, then 0x1A

Byte 0 (0x00): All zeros → +4 half-bytes
Byte 1 (0x00): All zeros → +4 half-bytes
Byte 2 (0x1A = 0001 1010):
  Leading zeros: 000
  Half-bytes: 2

Result: depth = 4 + 4 + 2 = 10
```

### Why This Distribution Works

**Probability of each depth:**

| Depth | Leading Zero Bits | Probability | Expected Keys (from 1024) |
|-------|-------------------|-------------|---------------------------|
| 0     | 0                 | ~50%        | ~512                      |
| 1     | 2                 | ~25%        | ~256                      |
| 2     | 4                 | ~12.5%      | ~128                      |
| 3     | 6                 | ~6.25%      | ~64                       |
| 4     | 8+                | ~6.25%      | ~64                       |

**Result:** Most keys (50%) at depth 0, exponentially fewer at higher depths → balanced tree!

💡 **Key Insight:** This is like flipping coins. The probability of getting N heads in a row decreases exponentially (1/2^N). Similarly, the probability of N leading zero bits decreases exponentially.

---

## MST Node Structure

### The Building Blocks

Every MST node contains:

```objc
@interface MSTNode : NSObject

@property (nonatomic, assign, readonly) uint32_t level;     // Node's level in tree
@property (nonatomic, strong, readonly, nullable) MSTNode *left;  // Left subtree
@property (nonatomic, copy, readonly) NSArray<MSTNodeEntry *> *entries;  // Sorted entries

@end

@interface MSTNodeEntry : NSObject

@property (nonatomic, copy) NSString *fullKey;        // e.g., "app.bsky.feed.post/123"
@property (nonatomic, strong) CID *value;             // CID of record content
@property (nonatomic, strong, nullable) MSTNode *tree;  // Right subtree (optional)

@end
```

### Visual Node Structure

```
┌─────────────────────────────────────────────────────────┐
│ MSTNode (Level: 2)                                      │
├─────────────────────────────────────────────────────────┤
│ left: → [MSTNode Level 1]                               │
│                                                         │
│ entries:                                                │
│   [0] key: "app.bsky.feed.post/abc"                     │
│       value: bafyreiabc...                              │
│       tree: → [MSTNode Level 1]                         │
│                                                         │
│   [1] key: "app.bsky.feed.post/xyz"                     │
│       value: bafyreixyz...                              │
│       tree: → [MSTNode Level 0]                         │
└─────────────────────────────────────────────────────────┘
```

### Node Invariants (Rules)

1. **Entries are sorted:** `entries[i].fullKey < entries[i+1].fullKey`

2. **Left subtree ordering:** All keys in `left` < first entry's key
   ```
   left contains: ["aaa", "bbb"]
   entries[0].key: "ccc"
   ✓ Valid: "aaa" < "ccc", "bbb" < "ccc"
   ```

3. **Right subtree ordering:** Keys in `entries[i].tree` fall between `entries[i]` and `entries[i+1]`
   ```
   entries[0].key: "app.bsky.actor.profile"
   entries[0].tree contains: ["app.bsky.actor.scene", ...]
   entries[1].key: "app.bsky.feed.post"
   ✓ Valid: "actor.profile" < "actor.scene" < "feed.post"
   ```

4. **Level ordering:** Node level ≥ all child node levels
   ```
   Parent level: 3
   Child levels: 2, 1, 0
   ✓ Valid: 3 >= 2, 3 >= 1, 3 >= 0
   ```

These invariants ensure:
- Binary search works (sorted order)
- Tree remains balanced (level constraints)
- Deterministic structure (same data → same tree)

---

## CBOR Serialization with Prefix Compression

### Why Prefix Compression?

Repository keys often share long prefixes:

```
app.bsky.feed.post/3k2j4d8f2ck2a
app.bsky.feed.post/3k2j4d8f2ck2b  ← Only last char differs!
app.bsky.feed.post/3k2j4d8f2ck2c
```

**Without compression:** Store 30+ bytes per key × thousands of keys = wasted space

**With compression:** Store shared prefix once, then just the differing suffix

### The Compression Algorithm

For each entry, calculate how many characters it shares with the **previous** entry:

```
Entry 0: "app.bsky.feed.post/abc"
         prefix_len = 0 (no previous entry)
         suffix = "app.bsky.feed.post/abc" (full key)

Entry 1: "app.bsky.feed.post/xyz"
         Common with entry 0: "app.bsky.feed.post/"
         prefix_len = 20
         suffix = "xyz" (just 3 chars!)

Savings: 20 bytes per entry (except first)
```

### Implementation

```objc
- (NSData *)serializeToCBOR:(NSMapTable<MSTNode *, CID *> *)cache {
    NSMutableArray<CBORValue *> *entriesCBOR = [NSMutableArray array];
    NSString *prevKey = @"";  // Track previous key for compression

    for (MSTNodeEntry *entry in self.entries) {
        // Calculate common prefix length with previous key
        NSUInteger prefixLen = 0;
        NSUInteger minLen = MIN(prevKey.length, entry.fullKey.length);

        for (NSUInteger i = 0; i < minLen; i++) {
            if ([prevKey characterAtIndex:i] == [entry.fullKey characterAtIndex:i]) {
                prefixLen++;
            } else {
                break;  // Stop at first difference
            }
        }

        // Extract suffix (part after common prefix)
        NSString *suffix = [entry.fullKey substringFromIndex:prefixLen];
        NSData *suffixBytes = [suffix dataUsingEncoding:NSUTF8StringEncoding];

        // Build entry map: {p, k, v, t}
        NSMutableDictionary<CBORValue *, CBORValue *> *entryDict = [NSMutableDictionary dictionary];

        // p: prefix length (unsigned integer)
        entryDict[[CBORValue textString:@"p"]] = [CBORValue unsignedInteger:prefixLen];

        // k: key suffix (byte string)
        entryDict[[CBORValue textString:@"k"]] = [CBORValue byteString:suffixBytes];

        // v: value CID (CBOR tag 42 = CID link)
        NSMutableData *valueCIDBytes = [NSMutableData dataWithBytes:"\x00" length:1];
        [valueCIDBytes appendData:entry.value.bytes];
        entryDict[[CBORValue textString:@"v"]] = [CBORValue tag:42
            value:[CBORValue byteString:valueCIDBytes]];

        // t: subtree CID (null if no subtree)
        if (entry.tree) {
            CID *treeCID = [entry.tree getCID:cache];
            NSMutableData *treeCIDBytes = [NSMutableData dataWithBytes:"\x00" length:1];
            [treeCIDBytes appendData:treeCID.bytes];
            entryDict[[CBORValue textString:@"t"]] = [CBORValue tag:42
                value:[CBORValue byteString:treeCIDBytes]];
        } else {
            entryDict[[CBORValue textString:@"t"]] = [CBORValue nilValue];
        }

        [entriesCBOR addObject:[CBORValue map:entryDict]];
        prevKey = entry.fullKey;  // Update for next iteration
    }

    // Build node map: {l, e}
    NSMutableDictionary<CBORValue *, CBORValue *> *nodeDict = [NSMutableDictionary dictionary];

    // e: entries array
    nodeDict[[CBORValue textString:@"e"]] = [CBORValue array:entriesCBOR];

    // l: left subtree CID (null if no left subtree)
    if (self.left) {
        CID *leftCID = [self.left getCID:cache];
        NSMutableData *leftCIDBytes = [NSMutableData dataWithBytes:"\x00" length:1];
        [leftCIDBytes appendData:leftCID.bytes];
        nodeDict[[CBORValue textString:@"l"]] = [CBORValue tag:42
            value:[CBORValue byteString:leftCIDBytes]];
    } else {
        nodeDict[[CBORValue textString:@"l"]] = [CBORValue nilValue];
    }

    return [[CBORValue map:nodeDict] encode];
}
```

### Serialization Example

<ObjcRunner :initialCode="prefixCompressionCode" />

```
Node:
  level: 1
  left: null
  entries:
    [0] fullKey: "app.bsky.feed.post/abc", value: CID(bafyreiabc...)
    [1] fullKey: "app.bsky.feed.post/xyz", value: CID(bafyreixyz...)

CBOR structure:
{
  "l": null,
  "e": [
    {
      "p": 0,
      "k": <bytes: "app.bsky.feed.post/abc">,
      "v": <tag 42: CID bytes>,
      "t": null
    },
    {
      "p": 20,  ← 20 chars shared with previous
      "k": <bytes: "xyz">,  ← Only 3 bytes!
      "v": <tag 42: CID bytes>,
      "t": null
    }
  ]
}
```

💡 **Key Insight:** Prefix compression is lossless—you can fully reconstruct keys by applying prefixes from left to right.

---

## Computing Node CIDs

Each node's identity is the CID of its CBOR serialization:

```objc
- (CID *)getCID:(NSMapTable<MSTNode *, CID *> *)cache {
    // 1. Check cache (avoid recomputing)
    CID *cached = [cache objectForKey:self];
    if (cached) return cached;

    // 2. Serialize node to CBOR
    NSData *cborBytes = [self serializeToCBOR:cache];

    // 3. Compute CID: dag-cbor codec (0x71) + SHA-256 multihash
    NSData *hash = [CID sha256Digest:cborBytes];
    CID *cid = [CID cidWithDigest:hash codec:0x71];

    // 4. Cache for future lookups
    [cache setObject:cid forKey:self];

    return cid;
}
```

### Complete CID Computation Example

```
Node:
  left: null
  entries: [
    {key: "app.bsky.feed.post/abc", value: bafyreiabc..., tree: null}
  ]

Step 1: Serialize to CBOR
→ CBOR bytes: [map with "l": null, "e": [entry map]]
→ Raw bytes: 0xA2 0x61 0x6C 0xF6 0x61 0x65 ... (DAG-CBOR encoding)

Step 2: SHA-256 hash
→ Hash: 0x1A2B3C4D... (32 bytes)

Step 3: Build multihash
→ Prefix: 0x12 (SHA-256 code) + 0x20 (32-byte length)
→ Multihash: [0x12] [0x20] [0x1A 0x2B 0x3C 0x4D ...]

Step 4: Build CID
→ Version: 0x01 (CIDv1)
→ Codec: 0x71 (dag-cbor)
→ CID bytes: [0x01] [0x71] [multihash bytes]

Step 5: Encode as string
→ CID string: "bafyreiga4q5trcfq..." (base32)

Result: This node's CID is bafyreiga4q5trcfq...
```

**Why this matters:**
- Any change to node → different CBOR → different CID
- Parent nodes reference children by CID
- Root CID proves entire tree structure
- Enables content-addressed storage and verification

---

## Tree Operations: Get

### Looking Up a Key

```objc
- (CID *)get:(NSString *)key {
    return [self getRecursive:self.root key:key];
}

- (CID *)getRecursive:(MSTNode *)node key:(NSString *)key {
    if (!node) return nil;

    // Binary search for key position within entries
    NSInteger idx = 0;
    while (idx < node.entries.count &&
           [node.entries[idx].fullKey compare:key] == NSOrderedAscending) {
        idx++;
    }

    // Check if we found exact match
    if (idx < node.entries.count &&
        [node.entries[idx].fullKey isEqualToString:key]) {
        return node.entries[idx].value;  // Found it!
    }

    // Not found in this node, recurse into appropriate subtree
    MSTNode *subtree = (idx == 0) ? node.left : node.entries[idx - 1].tree;
    return [self getRecursive:subtree key:key];
}
```

### Step-by-Step Get Example

```
Tree structure:
        ┌─────────────────────────┐
        │ Node (Level 2)          │
        │ entries:                │
        │   [0] "app.bsky.feed"   │
        │       tree → Node A     │
        │   [1] "app.bsky.graph"  │
        │       tree → Node B     │
        └─────────────────────────┘

Looking up: "app.bsky.feed.post/123"

Step 1: Start at root
  Compare "app.bsky.feed.post/123" with entries
  - "app.bsky.feed" < our key? YES (continue)
  - "app.bsky.graph" < our key? NO (stop)
  idx = 1 (stopped at "app.bsky.graph")

Step 2: Check for exact match
  entries[1].fullKey == "app.bsky.feed.post/123"? NO

Step 3: Recurse into subtree
  Since idx = 1, look at entries[0].tree (Node A)
  (Our key is between entries[0] and entries[1])

Step 4: Repeat in Node A
  ...eventually find the key or return nil
```

---

## Tree Operations: Put

### Insertion Algorithm

```objc
- (void)put:(NSString *)key valueCID:(CID *)valueCID {
    // Calculate this key's depth (probabilistic level)
    uint32_t depth = [MST keyDepth:key];

    // Add to tree, possibly creating new levels
    self.root = [self addRecursive:self.root
                               key:key
                             value:valueCID
                             depth:depth];
}

- (MSTNode *)addRecursive:(MSTNode *)node
                      key:(NSString *)key
                    value:(CID *)value
                    depth:(uint32_t)depth {
    // Base case: no node exists, create one
    if (!node) {
        node = [[MSTNode alloc] initWithLevel:0
                                         left:nil
                                      entries:@[]];
    }

    // Case 1: Key's depth exceeds current node's level
    if (depth > node.level) {
        // Need to create new parent node at higher level
        return [self promoteAndInsert:node key:key value:value depth:depth];
    }

    // Case 2: Key's depth matches or is below current node's level
    return [self insertIntoNode:node key:key value:value depth:depth];
}

- (MSTNode *)insertIntoNode:(MSTNode *)node
                        key:(NSString *)key
                      value:(CID *)value
                      depth:(uint32_t)depth {
    // Find insertion position via binary search
    NSInteger idx = 0;
    while (idx < node.entries.count &&
           [node.entries[idx].fullKey compare:key] == NSOrderedAscending) {
        idx++;
    }

    // Update existing entry if key already exists
    if (idx < node.entries.count &&
        [node.entries[idx].fullKey isEqualToString:key]) {

        MSTNodeEntry *oldEntry = node.entries[idx];
        MSTNodeEntry *newEntry = [[MSTNodeEntry alloc] initWithKey:key
                                                             value:value
                                                              tree:oldEntry.tree];

        // Create new node with updated entry
        NSMutableArray *newEntries = [node.entries mutableCopy];
        newEntries[idx] = newEntry;

        return [[MSTNode alloc] initWithLevel:node.level
                                         left:node.left
                                      entries:newEntries];
    }

    // Insert new entry at position idx
    MSTNodeEntry *newEntry = [[MSTNodeEntry alloc] initWithKey:key
                                                         value:value
                                                          tree:nil];

    NSMutableArray *newEntries = [node.entries mutableCopy];
    [newEntries insertObject:newEntry atIndex:idx];

    return [[MSTNode alloc] initWithLevel:node.level
                                     left:node.left
                                  entries:newEntries];
}
```

### Step-by-Step Put Example

```
Initial tree:
        ┌─────────────────────────┐
        │ Node (Level 1)          │
        │ entries:                │
        │   [0] "app.bsky.feed.post/aaa" → CID1 │
        │   [1] "app.bsky.feed.post/zzz" → CID2 │
        └─────────────────────────┘

Insert: "app.bsky.feed.post/mmm" → CID3
Depth: 0 (key hash has 0 leading zero bits)

Step 1: Calculate depth
  keyDepth("app.bsky.feed.post/mmm") = 0

Step 2: addRecursive(root, key, value, depth=0)
  node.level = 1, depth = 0
  → depth <= node.level, so insertIntoNode()

Step 3: Find insertion position
  Compare with entries:
  - "aaa" < "mmm"? YES (idx++)
  - "zzz" < "mmm"? NO (stop)
  idx = 1

Step 4: Insert at idx=1
  Create new entry: {key: "mmm", value: CID3}
  Insert at position 1

Result:
        ┌─────────────────────────┐
        │ Node (Level 1)          │
        │ entries:                │
        │   [0] "app.bsky.feed.post/aaa" → CID1 │
        │   [1] "app.bsky.feed.post/mmm" → CID3 │ ← NEW
        │   [2] "app.bsky.feed.post/zzz" → CID2 │
        └─────────────────────────┘

New root CID computed from updated node!
```

### Promoting to Higher Level

When a key's depth exceeds the current node's level, we must create a new parent:

```
Initial tree:
        ┌─────────────────────────┐
        │ Node (Level 0)          │
        │ entries: ["aaa", "zzz"] │
        └─────────────────────────┘

Insert: "mmm" with depth=2 (rare key with many leading zeros!)

Step 1: depth (2) > node.level (0)
  → Need to promote

Step 2: Split current node at "mmm"
  Left side: ["aaa"]  ← Keys < "mmm"
  Right side: ["zzz"] ← Keys > "mmm"

Step 3: Create intermediate nodes
  Level 1 node: left=["aaa"], entries=[]
  Level 1 node: left=["zzz"], entries=[]

Step 4: Create level 2 node
        ┌──────────────────────────────────┐
        │ Node (Level 2)                   │
        │ left → Level 1 node (["aaa"])    │
        │ entries:                         │
        │   [0] "mmm" → CID3               │
        │       tree → Level 1 node (["zzz"]) │
        └──────────────────────────────────┘

Result: New root at level 2!
```

This maintains tree balance—rare deep keys create taller trees, but probabilistically, most keys stay shallow.

---

## Tree Operations: Delete

### Deletion Algorithm

```objc
- (void)delete:(NSString *)key {
    self.root = [self deleteRecursive:self.root key:key];
    if (!self.root) {
        // Empty tree after deletion
        self.root = [[MSTNode alloc] initWithLevel:0];
    }
}

- (MSTNode *)deleteRecursive:(MSTNode *)node key:(NSString *)key {
    if (!node) return nil;

    // Find the entry to delete
    NSInteger idx = 0;
    while (idx < node.entries.count &&
           [node.entries[idx].fullKey compare:key] == NSOrderedAscending) {
        idx++;
    }

    // Found exact match?
    if (idx < node.entries.count &&
        [node.entries[idx].fullKey isEqualToString:key]) {

        MSTNodeEntry *entryToDelete = node.entries[idx];

        // Get left and right subtrees around this entry
        MSTNode *leftSubtree = (idx == 0) ? node.left : node.entries[idx - 1].tree;
        MSTNode *rightSubtree = entryToDelete.tree;

        // Merge the two subtrees
        MSTNode *merged = [self merge:leftSubtree and:rightSubtree];

        // Remove entry from array
        NSMutableArray *newEntries = [node.entries mutableCopy];
        [newEntries removeObjectAtIndex:idx];

        // Update references
        if (idx == 0) {
            // Deleted first entry, merged tree becomes new left
            return [[MSTNode alloc] initWithLevel:node.level
                                             left:merged
                                          entries:newEntries];
        } else {
            // Deleted middle/end entry, merged tree becomes previous entry's tree
            MSTNodeEntry *prevEntry = newEntries[idx - 1];
            MSTNodeEntry *updatedEntry = [[MSTNodeEntry alloc] initWithKey:prevEntry.fullKey
                                                                     value:prevEntry.value
                                                                      tree:merged];
            newEntries[idx - 1] = updatedEntry;

            return [[MSTNode alloc] initWithLevel:node.level
                                             left:node.left
                                          entries:newEntries];
        }
    }

    // Not found in this node, recurse into subtree
    MSTNode *subtree = (idx == 0) ? node.left : node.entries[idx - 1].tree;
    MSTNode *updatedSubtree = [self deleteRecursive:subtree key:key];

    // Update node with modified subtree
    if (idx == 0) {
        return [[MSTNode alloc] initWithLevel:node.level
                                         left:updatedSubtree
                                      entries:node.entries];
    } else {
        MSTNodeEntry *prevEntry = node.entries[idx - 1];
        MSTNodeEntry *updatedEntry = [[MSTNodeEntry alloc] initWithKey:prevEntry.fullKey
                                                                 value:prevEntry.value
                                                                  tree:updatedSubtree];

        NSMutableArray *newEntries = [node.entries mutableCopy];
        newEntries[idx - 1] = updatedEntry;

        return [[MSTNode alloc] initWithLevel:node.level
                                         left:node.left
                                      entries:newEntries];
    }
}
```

### Step-by-Step Delete Example

```
Initial tree:
        ┌─────────────────────────┐
        │ Node (Level 1)          │
        │ entries:                │
        │   [0] "app.bsky.feed.post/aaa" → CID1, tree=Node A │
        │   [1] "app.bsky.feed.post/mmm" → CID3, tree=Node B │
        │   [2] "app.bsky.feed.post/zzz" → CID2, tree=null   │
        └─────────────────────────┘

Delete: "app.bsky.feed.post/mmm"

Step 1: Find entry
  idx = 1 (found at entries[1])

Step 2: Identify subtrees
  leftSubtree = entries[0].tree (Node A)
  rightSubtree = entries[1].tree (Node B)

Step 3: Merge subtrees
  merged = merge(Node A, Node B)
  → Combined node with all entries from A and B

Step 4: Remove entry and update
  Remove entries[1]
  Update entries[0].tree = merged

Result:
        ┌─────────────────────────┐
        │ Node (Level 1)          │
        │ entries:                │
        │   [0] "app.bsky.feed.post/aaa" → CID1, tree=Merged │
        │   [1] "app.bsky.feed.post/zzz" → CID2, tree=null   │
        └─────────────────────────┘

"mmm" removed, subtrees merged!
```

---

## Walking the Tree: In-Order Traversal

```objc
- (NSArray<MSTEntry *> *)allEntries {
    NSMutableArray<MSTEntry *> *result = [NSMutableArray array];
    [self walk:self.root callback:^(MSTNodeEntry *entry) {
        [result addObject:[MSTEntry entryWithKey:entry.fullKey
                                         valueCID:entry.value]];
    }];
    return result;
}

- (void)walk:(MSTNode *)node callback:(void (^)(MSTNodeEntry *))callback {
    if (!node) return;

    // 1. Walk left subtree first (smallest keys)
    if (node.left) {
        [self walk:node.left callback:callback];
    }

    // 2. Process entries in order
    for (MSTNodeEntry *entry in node.entries) {
        // Visit this entry
        callback(entry);

        // 3. Walk right subtree of this entry
        if (entry.tree) {
            [self walk:entry.tree callback:callback];
        }
    }
}
```

### Traversal Example

```
Tree:
        ┌─────────────────────────┐
        │ Node                    │
        │ left → ["aaa"]          │
        │ entries:                │
        │   [0] "mmm", tree → ["nnn"] │
        │   [1] "zzz", tree → null    │
        └─────────────────────────┘

Traversal order:
1. Walk left → Visit "aaa"
2. Visit entries[0] → "mmm"
3. Walk entries[0].tree → Visit "nnn"
4. Visit entries[1] → "zzz"
5. No more entries

Result: ["aaa", "mmm", "nnn", "zzz"] (sorted!)
```

This in-order traversal guarantees lexicographic ordering—crucial for range queries and enumeration.

---

## Common Mistakes

### Mistake 1: Not Counting in Half-Bytes (Nibbles)

❌ **What people try:**
```objc
// WRONG: Count full zero bits
uint32_t zeroCount = 0;
for (int i = 0; i < 32; i++) {
    if (hash[i] == 0) zeroCount += 8;  // Full byte
    else break;
}
return zeroCount;  // Too coarse-grained!
```

**Why this fails:**
- Only counts full zero bytes (0, 8, 16, 24, ...)
- Misses keys with 2, 4, or 6 leading zero bits
- Tree becomes unbalanced (many keys at same depth)

✅ **Correct approach:**
```objc
// RIGHT: Count in half-bytes (4-bit chunks)
if (byte == 0) {
    zeroCount += 4;  // 2 nibbles = 4 half-bytes
} else {
    // Check individual bits for finer granularity
    if ((byte & 0xC0) == 0) zeroCount++;
    if ((byte & 0xF0) == 0) zeroCount++;
    // ...
}
```

**Why this works:**
- Finer granularity (depths: 0, 1, 2, 3, ...)
- Better distribution across levels
- More balanced tree

### Mistake 2: Not Updating prevKey in Serialization

❌ **What people do:**
```objc
// WRONG: Forget to update prevKey
for (MSTNodeEntry *entry in self.entries) {
    NSUInteger prefixLen = /* calculate with prevKey */;
    // ... serialize entry ...
    // Missing: prevKey = entry.fullKey;
}
```

**Why this fails:**
- Every entry calculates prefix with first entry
- Prefix compression ineffective
- Larger serialized size

✅ **Correct approach:**
```objc
// RIGHT: Update prevKey after each entry
for (MSTNodeEntry *entry in self.entries) {
    NSUInteger prefixLen = /* calculate */;
    // ... serialize ...
    prevKey = entry.fullKey;  // CRITICAL!
}
```

**Why this works:**
- Each entry compares with immediate predecessor
- Maximum compression achieved
- Smaller CBOR representation

### Mistake 3: Modifying Nodes In-Place

❌ **What people try:**
```objc
// WRONG: Mutate existing node
- (void)put:(NSString *)key value:(CID *)value {
    [self.root.entries addObject:newEntry];  // Mutation!
    // Old root CID still cached, but content changed!
}
```

**Why this fails:**
- Node's CID is based on its contents
- Mutating changes contents without updating CID
- Cached CIDs become invalid
- Tree integrity broken

✅ **Correct approach:**
```objc
// RIGHT: Create new nodes (immutability)
- (void)put:(NSString *)key value:(CID *)value {
    self.root = [self addRecursive:self.root key:key value:value ...];
    // Returns NEW node, old node unchanged
}
```

**Why this works:**
- Immutable nodes → CIDs remain valid
- Old tree versions still accessible (time-travel!)
- Thread-safe (no concurrent modifications)

---

## Summary

In this chapter, you learned:

- ✅ **MST combines Merkle trees and search trees:** Cryptographic integrity + efficient lookup
- ✅ **Probabilistic balancing via key depth:** SHA-256 leading zeros determine level
- ✅ **Node structure:** Level, left subtree, sorted entries with right subtrees
- ✅ **Prefix compression:** Saves space by storing shared prefixes once
- ✅ **Node CIDs:** Content-address nodes via dag-cbor + SHA-256
- ✅ **Tree operations:** Get, put, delete maintain invariants and balance
- ✅ **In-order traversal:** Enumerate all keys in sorted order

## Key Takeaways

1. **MSTs are deterministic:** Same data always produces same tree structure and root CID. This is critical for verifiable repositories.

2. **Probabilistic balancing is simpler than deterministic:** No rotations or rebalancing needed. Key hashes naturally distribute across levels.

3. **Immutability enables time-travel:** Every change creates new nodes. Old versions remain accessible via old root CIDs.

## Looking Ahead

In **Chapter 7**, we'll package MST nodes into **CAR files** (Content Addressable aRchives) and create **signed repository commits**—enabling efficient sync and cryptographic verification of repository history.

You'll learn how to:
- Serialize MST nodes into portable CAR files
- Create commit records linking snapshots
- Sign commits with secp256k1 for authenticity
- Implement repository diff and sync operations

This builds directly on MSTs—CAR files are collections of MST nodes you can share and verify!

---

**Files Referenced in This Chapter:**
- [MerkleSearchTree.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Repository/MerkleSearchTree.h)
- [MerkleSearchTree.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Repository/MerkleSearchTree.m)
- [MSTNode.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Repository/MSTNode.h)

**Further Reading:**
- [AT Protocol MST Specification](https://atproto.com/specs/data-model#merkle-search-tree) - Official spec
- [Merkle Trees Explained](https://en.wikipedia.org/wiki/Merkle_tree) - Cryptographic hash trees
- [Binary Search Trees](https://en.wikipedia.org/wiki/Binary_search_tree) - Ordered data structures
- [Probabilistic Data Structures](https://en.wikipedia.org/wiki/Probabilistic_data_structure) - Skip lists and related structures

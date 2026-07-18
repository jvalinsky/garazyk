// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file MST.h
 * @abstract Merkle Search Tree implementation for ATProto repositories.
 * @discussion This header defines the Merkle Search Tree (MST) data structure used by
 * ATProto for content-addressable record storage. The MST provides efficient
 * key-value storage with cryptographic integrity guarantees through content addressing.
 */

#import <Foundation/Foundation.h>
#import <stdint.h>
#import <stdatomic.h>

NS_ASSUME_NONNULL_BEGIN

@class CID;
@class MSTNode;
@class MSTEntry;
@class MSTNodeEntry;

/**
 * @abstract Specifies the type of an MST node.
 */
typedef NS_ENUM(NSUInteger, MSTNodeKind) {
    /** Leaf node containing key-value entries. */
    MSTNodeKindLeaf,
    /** Internal node containing subtree pointers. */
    MSTNodeKindNonLeaf
};

/**
 * @abstract Specifies the type of change in an MST diff operation.
 */
typedef NS_ENUM(NSUInteger, MSTDiffOperationType) {
    /** A new key-value pair was added. */
    MSTDiffOperationTypeAdd,
    /** An existing key's value was changed. */
    MSTDiffOperationTypeUpdate,
    /** A key-value pair was removed. */
    MSTDiffOperationTypeDelete
};

@class MSTDiffOperation;

/**
 * @abstract Represents a single change between two MST versions.
 * @discussion Used for sync operations to describe changes between commits.
 * For adds, previousCID is nil. For deletes, currentCID is nil. For updates, both are set.
 */
@interface MSTDiffOperation : NSObject

/** @abstract The key associated with the change. */
@property(nonatomic, copy) NSString *key;
/** @abstract The type of the operation. */
@property(nonatomic, assign) MSTDiffOperationType type;
/** @abstract The CID before the change. */
@property(nonatomic, strong, nullable) CID *previousCID;
/** @abstract The CID after the change. */
@property(nonatomic, strong, nullable) CID *currentCID;

/** @abstract Creates an add operation. */
+ (instancetype)addOperationWithKey:(NSString *)key
                         currentCID:(CID *)currentCID;
/** @abstract Creates an update operation. */
+ (instancetype)updateOperationWithKey:(NSString *)key
                           previousCID:(CID *)previousCID
                            currentCID:(CID *)currentCID;
/** @abstract Creates a delete operation. */
+ (instancetype)deleteOperationWithKey:(NSString *)key
                           previousCID:(CID *)previousCID;

@end

/**
 * @abstract Represents a key-value entry in the MST.
 */
@interface MSTEntry : NSObject <NSCopying>

/** @abstract The key of the entry. */
@property(nonatomic, copy, readonly) NSString *key;
/** @abstract The CID of the value. */
@property(nonatomic, strong, readonly) CID *valueCID;
/** @abstract Optional sub-key for nested entries. */
@property(nonatomic, copy, readonly, nullable) NSString *subKey;

/** @abstract Creates an entry. */
+ (instancetype)entryWithKey:(NSString *)key valueCID:(CID *)valueCID;
/** @abstract Creates an entry with a sub-key. */
+ (instancetype)entryWithKey:(NSString *)key
                    valueCID:(CID *)valueCID
                      subKey:(nullable NSString *)subKey;
/** @abstract Initializes an entry. */
- (instancetype)initWithKey:(NSString *)key
                   valueCID:(CID *)valueCID
                     subKey:(nullable NSString *)subKey;

/** @abstract Serialized key bytes. */
- (NSData *)keyBytes;
/** @abstract Length of the key. */
- (NSUInteger)keyLength;
/** @abstract Serialized entry data. */
- (NSData *)serialize;

@end

/**
 * @abstract An entry within an MST node.
 */
@interface MSTNodeEntry : NSObject

/** @abstract Length of the key prefix. */
@property(nonatomic, assign) NSUInteger prefixLen;
/** @abstract The key suffix. */
@property(nonatomic, copy) NSData *keySuffix;
/** @abstract The CID value. */
@property(nonatomic, strong) CID *value;
/** @abstract Optional CID of the subtree. */
@property(nonatomic, strong, nullable) CID *tree;

/** @abstract The full key reconstructed from prefix length and suffix. */
@property(nonatomic, copy, readonly) NSString *fullKey;

/** @abstract Creates a node entry. */
+ (instancetype)entryWithPrefixLen:(NSUInteger)prefixLen
                         keySuffix:(NSData *)keySuffix
                             value:(CID *)value
                              tree:(nullable CID *)tree;

/** @abstract Serializes the node entry. */
- (NSData *)serialize;

@end

/** @abstract Block provider type for resolving CIDs. */
typedef NSData * _Nullable (^MSTBlockProvider)(CID *cid);

/**
 * @abstract A node in the Merkle Search Tree.
 */
@interface MSTNode : NSObject

/** @abstract The node type (leaf or internal). */
@property(nonatomic, assign, readonly) MSTNodeKind kind;
/** @abstract The node hash CID. */
@property(nonatomic, strong, readonly, nullable) CID *nodeHash;
/** @abstract Entries contained in this node. */
@property(nonatomic, copy, readonly) NSArray<MSTNodeEntry *> *entries;
/** @abstract CID of the left subtree. */
@property(nonatomic, strong, readonly, nullable) CID *left;

/** @abstract Creates a leaf node. */
+ (instancetype)leafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries;
/** @abstract Creates an internal (non-leaf) node. */
+ (instancetype)nonLeafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries
                                  left:(nullable CID *)left;

/** @abstract Initializes a node. */
- (instancetype)initWithKind:(MSTNodeKind)kind
                     entries:(NSArray<MSTNodeEntry *> *)entries
                        left:(nullable CID *)left;

/** @abstract Serializes the node data. */
- (NSData *)serialize;
/** @abstract Serializes the node to CBOR, using a cache for CIDs. */
- (NSData *)serializeToCBOR:(NSMapTable<MSTNode *, CID *> *)cache;
/** @abstract Computes the CID of the node. */
- (CID *)getCID:(NSMapTable<MSTNode *, CID *> *)cache;
/** @abstract Computes the hash of the node. */
- (NSData *)computeHash;
/** @abstract Sets the node hash. */
- (void)setNodeHash:(CID *)hash;
/** @abstract Retrieves all entries in the tree rooted at this node. */
- (NSArray<MSTEntry *> *)fullEntries;

@end

/**
 * @abstract The Merkle Search Tree data structure.
 *
 * @discussion Thread safety. The `root` property is backed by a per-instance
 * `_Atomic(MSTNode *)` cell updated only via C11 acquire/release primitives,
 * *not* via Apple's `@property(atomic)` OSSpinLock-style implementation.
 * Concurrent readers and writers never tear the tree because the writer path
 * (`-put:`, `-delete:`) reproduces the tree from the existing root via
 * copy-on-write (each `addRecursive:`/`deleteRecursive:`/`split:`/`merge:`
 * returns a freshly allocated `MSTNode`; existing nodes are never mutated in
 * place). A walker captures `self.root` once at entry — the returned
 * autoreleased reference retains the published tree until the walk completes,
 * so a concurrent writer publishing a new root cannot disturb the walker's
 * view of the tree. Posts of `sync11-preorder-fixture.car` rely on this
 * guarantee end-to-end.
 *
 * Proof collection extends the atomic-publish invariant with a per-instance
 * `lazySubtreeCache` side-table (declared on the MST () class extension in
 * MST.m) that resolves `MSTNode` subtrees on demand rather than writing them
 * back into the published tree. The cache is invalidated on every
 * `-put:/-delete:` so it always tracks the currently-published root; callers
 * MUST NOT assume a cached subtree is valid across publish cycles.
 */
@interface MST : NSObject

/** @abstract The root node of the tree. */
@property(strong, readonly, nullable) MSTNode *root;
/** @abstract The CID of the root node. */
@property(nonatomic, strong, readonly, nullable) CID *rootCID;
/** @abstract Hash of an empty tree. */
@property(nonatomic, copy, readonly) NSData *emptyTreeHash;

/** @abstract Initializes an MST with a root CID. */
- (instancetype)initWithRootCID:(nullable CID *)rootCID;
/** @abstract Initializes an MST with a root node. */
- (instancetype)initWithRootNode:(nullable MSTNode *)rootNode;

/** @abstract Gets a value CID for a given key. */
- (nullable CID *)get:(NSString *)key;
/** @abstract Gets a value CID for a given key and sub-key. */
- (nullable CID *)get:(NSString *)key subKey:(nullable NSString *)subKey;
/** @abstract Puts a key-value entry into the tree. */
- (void)put:(NSString *)key valueCID:(CID *)valueCID;
/** @abstract Puts a key-value entry with a sub-key into the tree. */
- (void)put:(NSString *)key
    valueCID:(CID *)valueCID
      subKey:(nullable NSString *)subKey;
/** @abstract Deletes an entry for a key. */
- (void)delete:(NSString *)key;
/** @abstract Deletes an entry for a key and sub-key. */
- (void)delete:(NSString *)key subKey:(nullable NSString *)subKey;
/** @abstract Retrieves all entries in the tree. */
- (NSArray<MSTEntry *> *)allEntries;
/** @abstract Retrieves entries matching the prefix. */
- (NSArray<MSTEntry *> *)entriesWithPrefix:(NSString *)prefix;

/** @abstract Exports the tree as a CAR file. */
- (NSData *)exportCAR;
/** @abstract Serializes the tree to CBOR. */
- (NSData *)serializeToCBOR;
/** @abstract Deserializes an MST from CBOR (single-node only). */
+ (nullable instancetype)deserializeFromCBOR:(NSData *)data;

/**
 * @abstract Deserializes an MST from CBOR, recursively resolving child subtrees via a block provider.
 * @param data The root node's CBOR data.
 * @param blockProvider A block that resolves a CID to its CBOR data, or nil for lazy resolution.
 * @return A fully reconstructed MST, or nil if deserialization fails.
 */
+ (nullable instancetype)deserializeFromCBOR:(NSData *)data
                               blockProvider:(nullable MSTBlockProvider)blockProvider;

/**
 * @abstract Computes differences between this tree and an older version.
 * @param oldTree The older MST to compare against.
 * @return Array of MSTDiffOperation objects.
 */
- (NSArray<MSTDiffOperation *> *)diffFrom:(nullable MST *)oldTree;

/**
 * @abstract Computes the depth of a key based on its hash.
 * @param key The key string.
 * @return The computed depth (number of leading zero bits).
 */
+ (NSUInteger)keyDepthString:(NSString *)key;

/**
 * @abstract Computes the depth of a key based on its hash bytes.
 * @param keyBytes The key as raw bytes.
 * @return The computed depth (number of leading zero bits).
 */
+ (NSUInteger)keyDepthBytes:(NSData *)keyBytes;

/**
 * @abstract Computes the depth of a key.
 * @param key The key string.
 * @return The computed depth (leading zero bits divided by 2).
 */
+ (uint32_t)keyDepth:(NSString *)key;

/**
 * @abstract Gets the proof nodes path to a given key.
 * @param key The key to get proof nodes for.
 * @return Array of nodes.
 */
- (nullable NSArray<MSTNode *> *)getProofNodesForKey:(NSString *)key;
/**
 * @abstract Gets the proof nodes path using a block provider.
 */
- (nullable NSArray<MSTNode *> *)getProofNodesForKey:(NSString *)key
                                       blockProvider:(nullable MSTBlockProvider)blockProvider;

/**
 * @abstract Enumerates all nodes in depth-first, key-ordered traversal.
 */
- (void)enumerateNodesDepthFirstUsingBlock:(void (^)(MSTNode *node, NSUInteger depth, BOOL *stop))block;

/**
 * @abstract Serializes an MST node to CBOR data.
 */
- (nullable NSData *)serializeNode:(MSTNode *)node;

/**
 * @abstract Enumerates all node blocks in CAR-ready form.
 */
- (BOOL)enumerateNodeCARBlocksUsingBlock:(BOOL (^)(CID *cid, NSData *data,
                                                   NSError **error))block
                                   error:(NSError **)error;

/**
 * @abstract Exports the tree structure as a JSON dictionary for visualization.
 */
- (nullable NSDictionary *)toJSON;

/**
 * @abstract Computes tree statistics for monitoring.
 */
- (NSDictionary *)getStatistics;

/**
 * @abstract Exports the tree as a Graphviz DOT representation.
 */
- (nullable NSString *)toDOT;

@end

NS_ASSUME_NONNULL_END

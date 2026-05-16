// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

@class CID;
@class MSTNode;
@class MSTEntry;
@class MSTNodeEntry;

/*!
 @header MST.h

 @abstract Merkle Search Tree implementation for ATProto repositories.

 @discussion This header defines the Merkle Search Tree (MST) data structure
 used by ATProto for content-addressable record storage. The MST provides
 efficient key-value storage with cryptographic integrity guarantees through
 content addressing.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

/*!

 @abstract Specifies the type of an MST node.

 @constant MSTNodeKindLeaf A leaf node containing key-value entries.
 @constant MSTNodeKindNonLeaf An internal node containing subtree pointers.
 */
typedef NS_ENUM(NSUInteger, MSTNodeKind) {
  MSTNodeKindLeaf,
  MSTNodeKindNonLeaf
};

/*!

 @abstract Specifies the type of change in an MST diff operation.

 @constant MSTDiffOperationTypeAdd A new key-value pair was added.
 @constant MSTDiffOperationTypeUpdate An existing key's value was changed.
 @constant MSTDiffOperationTypeDelete A key-value pair was removed.
 */
typedef NS_ENUM(NSUInteger, MSTDiffOperationType) {
  MSTDiffOperationTypeAdd,
  MSTDiffOperationTypeUpdate,
  MSTDiffOperationTypeDelete
};

@class MSTDiffOperation;

/*!
 @class MSTDiffOperation

 @abstract Represents a single change between two MST versions.

 @discussion Used for sync operations to describe what changed between commits.
 For adds, oldCID is nil. For deletes, newCID is nil. For updates, both are set.
 */
@interface MSTDiffOperation : NSObject

@property(nonatomic, copy) NSString *key;
@property(nonatomic, assign) MSTDiffOperationType type;
@property(nonatomic, strong, nullable) CID *previousCID;
@property(nonatomic, strong, nullable) CID *currentCID;

+ (instancetype)addOperationWithKey:(NSString *)key
                         currentCID:(CID *)currentCID;
+ (instancetype)updateOperationWithKey:(NSString *)key
                           previousCID:(CID *)previousCID
                            currentCID:(CID *)currentCID;
+ (instancetype)deleteOperationWithKey:(NSString *)key
                           previousCID:(CID *)previousCID;

@end

/*!
 @class MSTEntry

 @abstract Represents a key-value entry in the MST.
 */
@interface MSTEntry : NSObject <NSCopying>

@property(nonatomic, copy, readonly) NSString *key;
@property(nonatomic, strong, readonly) CID *valueCID;
@property(nonatomic, copy, readonly, nullable) NSString *subKey;

+ (instancetype)entryWithKey:(NSString *)key valueCID:(CID *)valueCID;
+ (instancetype)entryWithKey:(NSString *)key
                    valueCID:(CID *)valueCID
                      subKey:(nullable NSString *)subKey;
- (instancetype)initWithKey:(NSString *)key
                   valueCID:(CID *)valueCID
                     subKey:(nullable NSString *)subKey;

- (NSData *)keyBytes;
- (NSUInteger)keyLength;
- (NSData *)serialize;

@end

/*!
 @class MSTNodeEntry

 @abstract An entry within an MST node.
 */
@interface MSTNodeEntry : NSObject

@property(nonatomic, assign) NSUInteger prefixLen;
@property(nonatomic, copy) NSData *keySuffix;
@property(nonatomic, strong) CID *value;
@property(nonatomic, strong, nullable) CID *tree;

/*! @abstract The full key reconstructed from prefix length and suffix. */
@property(nonatomic, copy, readonly) NSString *fullKey;

+ (instancetype)entryWithPrefixLen:(NSUInteger)prefixLen
                         keySuffix:(NSData *)keySuffix
                             value:(CID *)value
                              tree:(nullable CID *)tree;

- (NSData *)serialize;

@end

typedef NSData * _Nullable (^MSTBlockProvider)(CID *cid);

/*!
 @class MSTNode

 @abstract A node in the Merkle Search Tree.
 */
@interface MSTNode : NSObject

@property(nonatomic, assign, readonly) MSTNodeKind kind;
@property(nonatomic, strong, readonly, nullable) CID *nodeHash;
@property(nonatomic, copy, readonly) NSArray<MSTNodeEntry *> *entries;
@property(nonatomic, strong, readonly, nullable) CID *left;

+ (instancetype)leafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries;
+ (instancetype)nonLeafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries
                                  left:(nullable CID *)left;

- (instancetype)initWithKind:(MSTNodeKind)kind
                     entries:(NSArray<MSTNodeEntry *> *)entries
                        left:(nullable CID *)left;

- (NSData *)serialize;
- (NSData *)serializeToCBOR:(NSMapTable<MSTNode *, CID *> *)cache;
- (CID *)getCID:(NSMapTable<MSTNode *, CID *> *)cache;
- (NSData *)computeHash;
- (void)setNodeHash:(CID *)hash;
- (NSArray<MSTEntry *> *)fullEntries;

@end

/*!
 @class MST

 @abstract The Merkle Search Tree data structure.
 */
@interface MST : NSObject

@property(nonatomic, strong, readonly, nullable) MSTNode *root;
@property(nonatomic, strong, readonly, nullable) CID *rootCID;
@property(nonatomic, strong, readonly) NSData *emptyTreeHash;

- (instancetype)initWithRootCID:(nullable CID *)rootCID;
- (instancetype)initWithRootNode:(nullable MSTNode *)rootNode;
- (nullable CID *)get:(NSString *)key;
- (nullable CID *)get:(NSString *)key subKey:(nullable NSString *)subKey;
- (void)put:(NSString *)key valueCID:(CID *)valueCID;
- (void)put:(NSString *)key
    valueCID:(CID *)valueCID
      subKey:(nullable NSString *)subKey;
- (void)delete:(NSString *)key;
- (void)delete:(NSString *)key subKey:(nullable NSString *)subKey;
- (NSArray<MSTEntry *> *)allEntries;
- (NSArray<MSTEntry *> *)entriesWithPrefix:(NSString *)prefix;
- (NSData *)exportCAR;
- (NSData *)serializeToCBOR;
+ (nullable instancetype)deserializeFromCBOR:(NSData *)data;

/*!
 @method diffFrom:

 @abstract Computes the differences between this tree and an older version.

 @discussion Compares this MST with an older version and returns all changes
 (additions, updates, deletions). Used for sync operations to generate
 repository diffs for the firehose.

 @param oldTree The older MST to compare against (may be nil for initial state).
 @return Array of MSTDiffOperation objects describing all changes.
 */
- (NSArray<MSTDiffOperation *> *)diffFrom:(nullable MST *)oldTree;

/*!
 @method keyDepthString:

 @abstract Computes the depth of a key based on its SHA-256 hash.

 @param key The key string.
 @return The computed depth (number of leading zero bits).
 */
+ (NSUInteger)keyDepthString:(NSString *)key;

/*!
 @method keyDepthBytes:

 @abstract Computes the depth of a key based on its SHA-256 hash.

 @param keyBytes The key as raw bytes.
 @return The computed depth (number of leading zero bits).
 */
+ (NSUInteger)keyDepthBytes:(NSData *)keyBytes;

/*!
 @method keyDepth:

 @abstract Computes the depth of a key based on its SHA-256 hash.

 @param key The key string.
 @return The computed depth (number of leading zero bits divided by 2).
 */
+ (uint32_t)keyDepth:(NSString *)key;

/*!
 @method getProofNodesForKey:

 @abstract Gets the proof nodes from root to the given key.

 @param key The key to get proof nodes for.
 @return Array of MSTNode objects forming the proof path.
 */
- (nullable NSArray<MSTNode *> *)getProofNodesForKey:(NSString *)key;
- (nullable NSArray<MSTNode *> *)getProofNodesForKey:(NSString *)key
                                       blockProvider:(nullable MSTBlockProvider)blockProvider;

/*!
 @method enumerateNodesDepthFirstUsingBlock:

 @abstract Enumerates all MST nodes in strict depth-first, key-ordered traversal.

 @discussion Traverses the MST depth-first, visiting each node before its
 subtrees. For each node, the callback receives the node, its depth in the
 tree (0 at root), and a stop flag. This ordering is required by the STAR
 (Streaming Tree ARchive) format, which interleaves MST nodes and records
 in depth-first order.

 @param block Callback invoked for each node. Set *stop to YES to abort.
*/
- (void)enumerateNodesDepthFirstUsingBlock:(void (^)(MSTNode *node, NSUInteger depth, BOOL *stop))block;

/*!
 @method serializeNode:

 @abstract Serializes an MST node to CBOR data.

 @param node The node to serialize.
 @return CBOR-encoded data for the node.
 */
- (nullable NSData *)serializeNode:(MSTNode *)node;

/*!
 @method enumerateNodeCARBlocksUsingBlock:error:

 @abstract Enumerates all MST node blocks in CAR-ready form.

 @discussion Traverses the tree and invokes the callback once per unique node
 CID with its serialized DAG-CBOR bytes.

 @param block Callback invoked for each node block. Return NO to stop.
 @param error Error pointer for traversal or callback failures.
 @return YES if traversal completed, NO if aborted due to error.
 */
- (BOOL)enumerateNodeCARBlocksUsingBlock:(BOOL (^)(CID *cid, NSData *data,
                                                   NSError **error))block
                                   error:(NSError **)error;

/*!
 @method toJSON

 @abstract Exports the complete tree structure as a JSON dictionary.

 @discussion Returns a dictionary containing the tree's structure with:
 - rootCID: The root CID as a string
 - nodeCount: Total number of nodes
 - entryCount: Total number of entries
 - maxDepth: Maximum tree depth (level)
 - nodes: Array of node dictionaries with cid, level, kind, entries, left

 @return Dictionary suitable for JSON serialization, or nil if tree is empty.
 */
- (nullable NSDictionary *)toJSON;

/*!
 @method getStatistics

 @abstract Computes tree statistics for debugging and monitoring.

 @discussion Returns a dictionary with metrics including:
 - nodeCount: Total number of nodes
 - entryCount: Total number of key-value entries
 - leafNodeCount: Number of leaf nodes
 - internalNodeCount: Number of internal nodes
 - maxDepth: Maximum tree depth
 - avgDepth: Average depth across all nodes
 - rootCID: Root CID as a string
 - balanceFactor: Tree balance metric (0.0-1.0)

 @return Dictionary with tree statistics.
 */
- (NSDictionary *)getStatistics;

/*!
 @method toDOT

 @abstract Exports the tree structure in Graphviz DOT format.

 @discussion Generates a DOT language representation suitable for
 visualization with Graphviz tools. Nodes are color-coded by level
 and edges show parent-child relationships.

 @return DOT format string, or nil if tree is empty.
 */
- (nullable NSString *)toDOT;

@end

NS_ASSUME_NONNULL_END

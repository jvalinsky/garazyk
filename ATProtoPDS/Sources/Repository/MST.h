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
 @enum MSTNodeKind
 
 @abstract Specifies the type of an MST node.
 
 @constant MSTNodeKindLeaf A leaf node containing key-value entries.
 @constant MSTNodeKindNonLeaf An internal node containing subtree pointers.
 */
typedef NS_ENUM(NSUInteger, MSTNodeKind) {
    MSTNodeKindLeaf,
    MSTNodeKindNonLeaf
};

/*!
 @class MSTEntry
 
 @abstract Represents a key-value entry in the MST.
 */
@interface MSTEntry : NSObject <NSCopying>

@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, strong, readonly) CID *valueCID;
@property (nonatomic, copy, readonly, nullable) NSString *subKey;

+ (instancetype)entryWithKey:(NSString *)key valueCID:(CID *)valueCID;
+ (instancetype)entryWithKey:(NSString *)key valueCID:(CID *)valueCID subKey:(nullable NSString *)subKey;
- (instancetype)initWithKey:(NSString *)key valueCID:(CID *)valueCID subKey:(nullable NSString *)subKey;

- (NSData *)keyBytes;
- (NSUInteger)keyLength;
- (NSData *)serialize;

@end

/*!
 @class MSTNodeEntry
 
 @abstract An entry within an MST node.
 */
@interface MSTNodeEntry : NSObject

@property (nonatomic, assign) NSUInteger prefixLen;
@property (nonatomic, copy) NSData *keySuffix;
@property (nonatomic, strong) CID *value;
@property (nonatomic, strong, nullable) CID *tree;

+ (instancetype)entryWithPrefixLen:(NSUInteger)prefixLen
                         keySuffix:(NSData *)keySuffix
                             value:(CID *)value
                             tree:(nullable CID *)tree;

- (NSData *)serialize;

@end

/*!
 @class MSTNode
 
 @abstract A node in the Merkle Search Tree.
 */
@interface MSTNode : NSObject

@property (nonatomic, assign, readonly) MSTNodeKind kind;
@property (nonatomic, strong, readonly, nullable) CID *nodeHash;
@property (nonatomic, copy, readonly) NSArray<MSTNodeEntry *> *entries;
@property (nonatomic, strong, readonly, nullable) CID *left;

+ (instancetype)leafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries;
+ (instancetype)nonLeafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries left:(nullable CID *)left;

- (instancetype)initWithKind:(MSTNodeKind)kind entries:(NSArray<MSTNodeEntry *> *)entries left:(nullable CID *)left;

- (NSData *)serialize;
- (NSData *)computeHash;
- (void)setNodeHash:(CID *)hash;
- (NSArray<MSTEntry *> *)fullEntries;

@end

/*!
 @class MST
 
 @abstract The Merkle Search Tree data structure.
 */
@interface MST : NSObject

@property (nonatomic, strong, readonly, nullable) CID *rootCID;
@property (nonatomic, strong, readonly) NSData *emptyTreeHash;

- (instancetype)initWithRootCID:(nullable CID *)rootCID;
- (nullable CID *)get:(NSString *)key;
- (nullable CID *)get:(NSString *)key subKey:(nullable NSString *)subKey;
- (void)put:(NSString *)key valueCID:(CID *)valueCID;
- (void)put:(NSString *)key valueCID:(CID *)valueCID subKey:(nullable NSString *)subKey;
- (void)delete:(NSString *)key;
- (void)delete:(NSString *)key subKey:(nullable NSString *)subKey;
- (NSArray<MSTEntry *> *)allEntries;
- (NSArray<MSTEntry *> *)entriesWithPrefix:(NSString *)prefix;
- (NSData *)exportCAR;
- (NSData *)serializeToCBOR;
+ (nullable instancetype)deserializeFromCBOR:(NSData *)data;

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

/*!
 @method serializeNode:

 @abstract Serializes an MST node to CBOR data.

 @param node The node to serialize.
 @return CBOR-encoded data for the node.
 */
- (nullable NSData *)serializeNode:(MSTNode *)node;

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

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
 
 @copyright Copyright (c) 2024 Jack Myers
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

/*!
 @method getProofNodesForKey:
 
 @abstract Gets all MST nodes in the proof path from root to the specified key.
 
 @param key The key to find (format: "collection/rkey").
 @return Array of MSTNode objects from root to leaf, or nil if key not found.
 
 @discussion Each node in the returned array should be serialized and included
 in a CAR file for cryptographic verification of the record.
 */
- (nullable NSArray<MSTNode *> *)getProofNodesForKey:(NSString *)key;

/*!
 @method serializeNode:
 
 @abstract Serializes an MST node to DAG-CBOR format.
 
 @param node The node to serialize.
 @return DAG-CBOR encoded node data.
 */
- (NSData *)serializeNode:(MSTNode *)node;
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
 @method keyDepthBytes:
 
 @abstract Computes the depth of a key based on its SHA-256 hash.
 
 @param keyBytes The key as raw bytes.
 @return The computed depth (number of leading zero bits divided by 2).
 */
+ (NSUInteger)keyDepthBytes:(NSData *)keyBytes;

@end

NS_ASSUME_NONNULL_END

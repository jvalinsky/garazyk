#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class CID;
@class MSTNode;
@class MSTEntry;

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
 
 @discussion MSTEntry stores a key and its associated content CID.
 For collections, a subKey can be used to distinguish multiple values
 within the same collection namespace.
 
 @code
 // Create an entry for a record
 MSTEntry *entry = [MSTEntry entryWithKey:@"app.bsky.actor.profile"
                                valueCID:recordCID];
 @endcode
 */
@interface MSTEntry : NSObject <NSCopying>

/*! The key identifying this entry (e.g., collection/rkey format). */
@property (nonatomic, copy, readonly) NSString *key;

/*! The CID of the value associated with this key. */
@property (nonatomic, strong, readonly) CID *valueCID;

/*! Optional subKey for distinguishing entries in the same collection. */
@property (nonatomic, copy, readonly, nullable) NSString *subKey;

/*!
 @method entryWithKey:valueCID:
 
 @abstract Creates an entry with a simple key.
 
 @param key The key for this entry.
 @param valueCID The CID of the value to store.
 @return A new MSTEntry instance.
 */
+ (instancetype)entryWithKey:(NSString *)key valueCID:(CID *)valueCID;

/*!
 @method entryWithKey:valueCID:subKey:
 
 @abstract Creates an entry with a key and subKey.
 
 @param key The key for this entry.
 @param valueCID The CID of the value to store.
 @param subKey Optional subKey for collection entries.
 @return A new MSTEntry instance.
 */
+ (instancetype)entryWithKey:(NSString *)key valueCID:(CID *)valueCID subKey:(nullable NSString *)subKey;

/*!
 @method initWithKey:valueCID:subKey:
 
 @abstract Initializes an entry with all parameters.
 
 @param key The key for this entry.
 @param valueCID The CID of the value to store.
 @param subKey Optional subKey for collection entries.
 @return An initialized MSTEntry instance.
 */
- (instancetype)initWithKey:(NSString *)key valueCID:(CID *)valueCID subKey:(nullable NSString *)subKey;

/*!
 @method keyBytes
 
 @abstract Returns the key encoded as bytes.
 
 @return The key data encoded in UTF-8.
 */
- (NSData *)keyBytes;

/*!
 @method keyLength
 
 @abstract Returns the length of the key.
 
 @return The number of bytes in the key.
 */
- (NSUInteger)keyLength;

/*!
 @method serialize
 
 @abstract Serializes the entry to CBOR format.
 
 @return CBOR-encoded entry data.
 */
- (NSData *)serialize;

@end

/*!
 @class MSTNodeEntry
 
 @abstract An entry within an MST node.
 
 @discussion MSTNodeEntry represents a single entry in a node, with a
 prefix-compressed key suffix and optional subtree pointer. This internal
 structure is used for efficient tree operations.
 */
@interface MSTNodeEntry : NSObject

/*! The length of the common prefix shared with other keys. */
@property (nonatomic, assign) NSUInteger prefixLen;

/*! The remaining portion of the key after the prefix. */
@property (nonatomic, copy) NSData *keySuffix;

/*! The CID of the value for this entry. */
@property (nonatomic, strong) CID *value;

/*! The CID of a subtree for non-leaf entries, or nil for leaf entries. */
@property (nonatomic, strong, nullable) CID *tree;

/*!
 @method entryWithPrefixLen:keySuffix:value:tree:
 
 @abstract Creates a node entry with all fields.
 
 @param prefixLen The prefix length for key compression.
 @param keySuffix The key suffix data.
 @param value The value CID.
 @param tree The subtree CID, or nil for leaf entries.
 @return A new MSTNodeEntry instance.
 */
+ (instancetype)entryWithPrefixLen:(NSUInteger)prefixLen
                         keySuffix:(NSData *)keySuffix
                             value:(CID *)value
                             tree:(nullable CID *)tree;

/*!
 @method serialize
 
 @abstract Serializes the node entry to bytes.
 
 @return The serialized entry data.
 */
- (NSData *)serialize;

@end

/*!
 @class MSTNode
 
 @abstract A node in the Merkle Search Tree.
 
 @discussion MSTNode represents either a leaf or non-leaf node in the tree.
 Leaf nodes contain key-value entries, while non-leaf nodes contain
 subtree pointers. Each node can be serialized and hashed for content
 addressing.
 
 @code
 // Create a leaf node with entries
 NSArray *entries = @[entry1, entry2];
 MSTNode *leaf = [MSTNode leafNodeWithEntries:entries];
 @endcode
 */
@interface MSTNode : NSObject

/*! The type of this node (leaf or non-leaf). */
@property (nonatomic, assign, readonly) MSTNodeKind kind;

/*! The content-addressable hash of this node. */
@property (nonatomic, strong, readonly, nullable) CID *nodeHash;

/*! The entries contained in this node. */
@property (nonatomic, copy, readonly) NSArray<MSTNodeEntry *> *entries;

/*! The left subtree CID for non-leaf nodes. */
@property (nonatomic, strong, readonly, nullable) CID *left;

/*!
 @method leafNodeWithEntries:
 
 @abstract Creates a leaf node containing entries.
 
 @param entries The entries to include in this leaf node.
 @return A new leaf MSTNode instance.
 */
+ (instancetype)leafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries;

/*!
 @method nonLeafNodeWithEntries:left:
 
 @abstract Creates a non-leaf (internal) node.
 
 @param entries The entries in this node.
 @param left The CID of the left subtree.
 @return A new non-leaf MSTNode instance.
 */
+ (instancetype)nonLeafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries left:(nullable CID *)left;

/*!
 @method initWithKind:entries:left:
 
 @abstract Initializes a node with all parameters.
 
 @param kind The type of node to create.
 @param entries The entries for this node.
 @param left The left subtree CID, or nil for leaf nodes.
 @return An initialized MSTNode instance.
 */
- (instancetype)initWithKind:(MSTNodeKind)kind entries:(NSArray<MSTNodeEntry *> *)entries left:(nullable CID *)left;

/*!
 @method serialize
 
 @abstract Serializes the node to CBOR format.
 
 @return CBOR-encoded node data suitable for storage.
 */
- (NSData *)serialize;

/*!
 @method computeHash
 
 @abstract Computes the content CID of this node.
 
 @return The CID representing this node's content.
 */
- (NSData *)computeHash;

/*!
 @method setNodeHash:
 
 @abstract Sets the node's content hash.
 
 @param hash The pre-computed CID for this node.
 */
- (void)setNodeHash:(CID *)hash;

/*!
 @method fullEntries
 
 @abstract Returns all entries with full (uncompressed) keys.
 
 @discussion This method expands prefix-compressed keys to their full
 form, useful for iteration and display purposes.
 
 @return An array of MSTEntry objects with complete keys.
 */
- (NSArray<MSTEntry *> *)fullEntries;

@end

/*!
 @class MST
 
 @abstract The Merkle Search Tree data structure.
 
 @discussion MST provides a complete implementation of the Merkle Search
 Tree used by ATProto for repository storage. It supports standard
 operations like get, put, and delete, as well as tree export to CAR format
 for synchronization and backup.
 
 The MST ensures:
 <ul>
   <li>Efficient key-based lookups (O(log n) complexity)</li>
   <li>Cryptographic integrity through content addressing</li>
   <li>Atomic commits through CAR serialization</li>
 </ul>
 
 @code
 // Create an empty MST
 MST *tree = [[MST alloc] initWithRootCID:nil];
 
 // Add entries
 [tree put:@"app.bsky.actor.profile/self" valueCID:recordCID];
 
 // Get a value
 CID *result = [tree get:@"app.bsky.actor.profile/self"];
 
 // Export for synchronization
 NSData *car = [tree exportCAR];
 @endcode
 */
@interface MST : NSObject

/*! The current root CID of this tree, or nil if empty. */
@property (nonatomic, strong, readonly, nullable) CID *rootCID;

/*! The CID of an empty tree (all zeros hash). */
@property (nonatomic, strong, readonly) NSData *emptyTreeHash;

/*!
 @method initWithRootCID:
 
 @abstract Initializes an MST with an existing root CID.
 
 @param rootCID The CID of the tree root, or nil for an empty tree.
 @return An initialized MST instance.
 */
- (instancetype)initWithRootCID:(nullable CID *)rootCID;

/*!
 @method get:
 
 @abstract Retrieves a value by key.
 
 @param key The key to look up.
 @return The CID associated with the key, or nil if not found.
 */
- (nullable CID *)get:(NSString *)key;

/*!
 @method get:subKey:
 
 @abstract Retrieves a value by key and optional subKey.
 
 @param key The key to look up.
 @param subKey Optional subKey for collection entries.
 @return The CID associated with the key, or nil if not found.
 */
- (nullable CID *)get:(NSString *)key subKey:(nullable NSString *)subKey;

/*!
 @method put:valueCID:
 
 @abstract Inserts or updates a key-value pair.
 
 @param key The key to insert or update.
 @param valueCID The CID of the value to store.
 */
- (void)put:(NSString *)key valueCID:(CID *)valueCID;

/*!
 @method put:valueCID:subKey:
 
 @abstract Inserts or updates a key-value pair with subKey.
 
 @param key The key to insert or update.
 @param valueCID The CID of the value to store.
 @param subKey Optional subKey for collection entries.
 */
- (void)put:(NSString *)key valueCID:(CID *)valueCID subKey:(nullable NSString *)subKey;

/*!
 @method delete:
 
 @abstract Removes a key from the tree.
 
 @param key The key to remove.
 */
- (void)delete:(NSString *)key;

/*!
 @method delete:subKey:
 
 @abstract Removes a key with subKey from the tree.
 
 @param key The key to remove.
 @param subKey The subKey of the entry to remove.
 */
- (void)delete:(NSString *)key subKey:(nullable NSString *)subKey;

/*!
 @method allEntries
 
 @abstract Returns all entries in the tree.
 
 @return An array of MSTEntry objects for all keys.
 */
- (NSArray<MSTEntry *> *)allEntries;

/*!
 @method entriesWithPrefix:
 
 @abstract Returns entries whose keys start with the given prefix.
 
 @param prefix The key prefix to match.
 @return An array of matching MSTEntry objects.
 */
- (NSArray<MSTEntry *> *)entriesWithPrefix:(NSString *)prefix;

/*!
 @method exportCAR
 
 @abstract Exports the tree as a CAR archive.
 
 @discussion This method serializes the entire tree structure to a
 Content Addressable Records (CAR) format, suitable for storage,
 transmission, or synchronization.
 
 @return CAR-encoded tree data.
 */
- (NSData *)exportCAR;

/*!
 @method serializeToCBOR
 
 @abstract Serializes the tree to CBOR format.
 
 @return CBOR-encoded tree data.
 */
- (NSData *)serializeToCBOR;

/*!
 @method deserializeFromCBOR:
 
 @abstract Creates an MST from CBOR data.
 
 @param data The CBOR-encoded tree data.
 @return A new MST instance, or nil if deserialization failed.
 */
+ (nullable instancetype)deserializeFromCBOR:(NSData *)data;

@end

NS_ASSUME_NONNULL_END

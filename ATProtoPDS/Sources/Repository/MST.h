/**
 * @file MST.h
 * @brief Merkle Search Tree (MST) data structure implementation for the ATProto PDS.
 *
 * This header defines the core classes for implementing a Merkle Search Tree, which is
 * used by the AT Protocol (bluesky social) for repository storage. The MST is a
 * content-addressable, sorted-key-value store that provides:
 *
 * - Efficient key-value storage with O(log n) lookups
 * - Content addressing for integrity verification
 * - Sorted key ordering for prefix-based queries
 * - Atomic updates through content-addressable nodes
 *
 * The MST structure is self-certifying: each node's CID contains a hash of its contents,
 * enabling verification of the entire tree's integrity. The tree supports operations
 * including get, put, delete, and prefix-based enumeration.
 *
 * @see https://atproto.com/specs/repository
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class CID;
@class MSTNode;
@class MSTEntry;

typedef NS_ENUM(NSUInteger, MSTNodeKind) {
    MSTNodeKindLeaf,
    MSTNodeKindNonLeaf
};

/**
 * @class MSTEntry
 * @brief Represents a single key-value entry in the Merkle Search Tree.
 *
 * MSTEntry stores a key-value pair where the key is a string and the value is
 * referenced by its CID (Content Identifier). Entries can optionally have a
 * subKey for hierarchical storage patterns.
 *
 * The key is stored as a UTF-8 encoded string, and entries are sorted
 * lexicographically by key in the tree structure.
 */
@interface MSTEntry : NSObject <NSCopying>

/** The primary key for this entry, encoded as a UTF-8 string. */
@property (nonatomic, copy, readonly) NSString *key;

/** The CID referencing the value data stored elsewhere. */
@property (nonatomic, strong, readonly) CID *valueCID;

/** Optional subKey for supporting hierarchical key patterns (e.g., "collection/recordKey"). */
@property (nonatomic, copy, readonly, nullable) NSString *subKey;

/**
 * @brief Creates an entry with just a key and value CID.
 * @param key The primary key string.
 * @param valueCID The CID referencing the value.
 * @return A new MSTEntry instance.
 */
+ (instancetype)entryWithKey:(NSString *)key valueCID:(CID *)valueCID;

/**
 * @brief Creates an entry with a key, value CID, and optional subKey.
 * @param key The primary key string.
 * @param valueCID The CID referencing the value.
 * @param subKey Optional secondary key for hierarchical storage.
 * @return A new MSTEntry instance.
 */
+ (instancetype)entryWithKey:(NSString *)key valueCID:(CID *)valueCID subKey:(nullable NSString *)subKey;

/**
 * @brief Initializes a new entry with the specified components.
 * @param key The primary key string.
 * @param valueCID The CID referencing the value.
 * @param subKey Optional secondary key for hierarchical storage.
 * @return A new MSTEntry instance.
 */
- (instancetype)initWithKey:(NSString *)key valueCID:(CID *)valueCID subKey:(nullable NSString *)subKey;

/**
 * @brief Returns the raw key bytes encoded as UTF-8.
 * @return NSData containing the UTF-8 encoded key.
 */
- (NSData *)keyBytes;

/**
 * @brief Returns the length of the key in bytes.
 * @return The byte length of the key.
 */
- (NSUInteger)keyLength;

/**
 * @brief Serializes this entry to CBOR format.
 * @return NSData containing the CBOR-encoded entry.
 */
- (NSData *)serialize;

@end

/**
 * @class MSTNodeEntry
 * @brief Represents an entry within an MST node, used for internal tree structure.
 *
 * MSTNodeEntry contains the information needed to locate either a subtree or a
 * value within the MST. It includes a prefix length for efficient key comparison,
 * a key suffix for partial key storage, and references to child nodes or values.
 *
 * This is an internal structure used during tree operations.
 */
@interface MSTNodeEntry : NSObject

/** Length of the shared prefix with parent key, used for tree navigation. */
@property (nonatomic, assign) NSUInteger prefixLen;

/** The remaining portion of the key after the prefix, used for child node differentiation. */
@property (nonatomic, copy) NSData *keySuffix;

/** CID reference to a value (leaf nodes only). */
@property (nonatomic, strong) CID *value;

/** CID reference to a child subtree node (non-leaf nodes only). */
@property (nonatomic, strong, nullable) CID *tree;

/**
 * @brief Creates a new node entry with the specified components.
 * @param prefixLen Length of the shared key prefix.
 * @param keySuffix The remaining key bytes after the prefix.
 * @param value CID reference to the value (for leaf entries).
 * @param tree CID reference to a child subtree (for non-leaf entries).
 * @return A new MSTNodeEntry instance.
 */
+ (instancetype)entryWithPrefixLen:(NSUInteger)prefixLen
                         keySuffix:(NSData *)keySuffix
                             value:(CID *)value
                             tree:(nullable CID *)tree;

/**
 * @brief Serializes this node entry to CBOR format.
 * @return NSData containing the CBOR-encoded entry.
 */
- (NSData *)serialize;

@end

/**
 * @class MSTNode
 * @brief Represents a node in the Merkle Search Tree structure.
 *
 * MSTNode is the fundamental building block of the tree. Nodes are either
 * leaf nodes (containing value entries) or non-leaf nodes (containing child
 * node references). Each node has a content identifier that cryptographically
 * identifies its contents.
 *
 * Nodes maintain sorted entries for efficient traversal and content-addressable
 * storage for integrity verification.
 */
@interface MSTNode : NSObject

/** The type of this node - either leaf or non-leaf. */
@property (nonatomic, assign, readonly) MSTNodeKind kind;

/** The content identifier (CID) hash of this node's serialized contents. */
@property (nonatomic, strong, readonly, nullable) CID *nodeHash;

/** Array of entries contained in this node, sorted by key. */
@property (nonatomic, copy, readonly) NSArray<MSTNodeEntry *> *entries;

/** Reference to the left child subtree (non-leaf nodes only). */
@property (nonatomic, strong, readonly, nullable) CID *left;

/**
 * @brief Creates a leaf node with the specified entries.
 * @param entries Array of entries for this leaf node.
 * @return A new leaf MSTNode instance.
 */
+ (instancetype)leafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries;

/**
 * @brief Creates a non-leaf node with entries and left child reference.
 * @param entries Array of entries for this non-leaf node.
 * @param left CID reference to the left child subtree.
 * @return A new non-leaf MSTNode instance.
 */
+ (instancetype)nonLeafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries left:(nullable CID *)left;

/**
 * @brief Initializes a new node with the specified type and components.
 * @param kind The node type (leaf or non-leaf).
 * @param entries Array of entries for this node.
 * @param left CID reference to the left child subtree (nil for leaf nodes).
 * @return A new MSTNode instance.
 */
- (instancetype)initWithKind:(MSTNodeKind)kind entries:(NSArray<MSTNodeEntry *> *)entries left:(nullable CID *)left;

/**
 * @brief Serializes this node to CBOR format.
 * @return NSData containing the CBOR-encoded node.
 */
- (NSData *)serialize;

/**
 * @brief Computes the CID hash for this node's contents.
 * @return NSData containing the SHA-256 hash of the serialized node.
 */
- (NSData *)computeHash;

/**
 * @brief Sets the node's cached CID hash after computation.
 * @param hash The CID to assign to this node.
 */
- (void)setNodeHash:(CID *)hash;

/**
 * @brief Returns all full MSTEntry objects contained in this node's subtree.
 * @return Array of MSTEntry objects representing all values in this subtree.
 */
- (NSArray<MSTEntry *> *)fullEntries;

@end

/**
 * @class MST
 * @brief The main Merkle Search Tree class providing the complete tree interface.
 *
 * MST provides a complete implementation of a Merkle Search Tree, supporting
 * standard operations including get, put, delete, and enumeration. The tree
 * maintains a root CID that serves as a content address for the entire tree
 * state.
 *
 * Tree operations are atomic: each modification produces a new root CID
 * while preserving previous states for content addressing. This enables
 * efficient snapshot and rollback capabilities.
 */
@interface MST : NSObject

/** The CID of the current tree root, or nil for an empty tree. */
@property (nonatomic, strong, readonly, nullable) CID *rootCID;

/** The CID hash of an empty tree (singleton value for consistency). */
@property (nonatomic, strong, readonly) NSData *emptyTreeHash;

/**
 * @brief Initializes a new MST with the specified root CID.
 * @param rootCID The CID of the existing tree root, or nil for an empty tree.
 * @return A new MST instance.
 */
- (instancetype)initWithRootCID:(nullable CID *)rootCID;

/**
 * @brief Retrieves the CID for a given key.
 * @param key The key to look up.
 * @return The CID referencing the value, or nil if not found.
 */
- (nullable CID *)get:(NSString *)key;

/**
 * @brief Retrieves the CID for a key with an optional subKey.
 * @param key The primary key to look up.
 * @param subKey Optional secondary key for hierarchical lookups.
 * @return The CID referencing the value, or nil if not found.
 */
- (nullable CID *)get:(NSString *)key subKey:(nullable NSString *)subKey;

/**
 * @brief Inserts or updates a value for the given key.
 * @param key The key to insert or update.
 * @param valueCID The CID referencing the value data.
 */
- (void)put:(NSString *)key valueCID:(CID *)valueCID;

/**
 * @brief Inserts or updates a value for a key with optional subKey.
 * @param key The primary key to insert or update.
 * @param valueCID The CID referencing the value data.
 * @param subKey Optional secondary key for hierarchical storage.
 */
- (void)put:(NSString *)key valueCID:(CID *)valueCID subKey:(nullable NSString *)subKey;

/**
 * @brief Deletes the value for the given key.
 * @param key The key to delete.
 */
- (void)delete:(NSString *)key;

/**
 * @brief Deletes the value for a key with optional subKey.
 * @param key The primary key to delete.
 * @param subKey Optional secondary key for hierarchical deletion.
 */
- (void)delete:(NSString *)key subKey:(nullable NSString *)subKey;

/**
 * @brief Returns all entries in the tree.
 * @return Array of MSTEntry objects representing all values in the tree.
 */
- (NSArray<MSTEntry *> *)allEntries;

/**
 * @brief Returns all entries with keys starting with the specified prefix.
 * @param prefix The key prefix to match.
 * @return Array of MSTEntry objects with matching prefix.
 */
- (NSArray<MSTEntry *> *)entriesWithPrefix:(NSString *)prefix;

/**
 * @brief Exports the entire tree as a CAR (Content Addressable Records) file.
 * @return NSData containing the CAR-encoded tree including all nodes and values.
 */
- (NSData *)exportCAR;

/**
 * @brief Serializes the tree to CBOR format.
 * @return NSData containing the CBOR-encoded tree.
 */
- (NSData *)serializeToCBOR;

/**
 * @brief Deserializes a tree from CBOR format.
 * @param data The CBOR-encoded tree data.
 * @return A new MST instance, or nil if deserialization fails.
 */
+ (nullable instancetype)deserializeFromCBOR:(NSData *)data;

@end

NS_ASSUME_NONNULL_END

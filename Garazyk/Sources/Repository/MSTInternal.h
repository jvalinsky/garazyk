#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class CID;

/// Private interface for MSTNode - provides access to internal structure
/// Used by MSTWalker for tree traversal
/// This must be included after MST.h
@interface MSTNode (Internal)

/// Leftmost subtree pointer (may be nil)
@property (nonatomic, strong, readonly, nullable) MSTNode *internalLeft;

/// Mutable array of entries at this node
@property (nonatomic, strong, readonly) NSMutableArray<MSTNodeEntry *> *internalEntries;

/// Level of this node in the MST
@property (nonatomic, assign, readonly) uint32_t level;

/// Get CID for this node using cache
- (CID *)getCID:(NSMapTable<MSTNode *, CID *> *)cache;

@end

/// Private interface for MSTNodeEntry - provides access to subtree
@interface MSTNodeEntry (Internal)

/// Subtree pointer (may be nil for leaf entries)
@property (nonatomic, strong, readonly, nullable) MSTNode *internalTree;

/// Full key of this entry
@property (nonatomic, copy, readonly) NSString *fullKey;

@end

NS_ASSUME_NONNULL_END

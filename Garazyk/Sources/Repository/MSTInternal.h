// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file MSTInternal.h
 * @abstract Internal interfaces for Merkle Search Tree nodes.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class CID;

/**
 * @abstract Internal accessors for MSTNode.
 * @discussion Used by MSTWalker for efficient tree traversal.
 */
@interface MSTNode (Internal)

/** @abstract Leftmost subtree pointer (may be nil). */
@property (nonatomic, strong, readonly, nullable) MSTNode *internalLeft;

/** @abstract Mutable array of entries at this node. */
@property (nonatomic, strong, readonly) NSMutableArray<MSTNodeEntry *> *internalEntries;

/** @abstract Level of this node in the MST. */
@property (nonatomic, assign, readonly) uint32_t level;

/**
 * @abstract Retrieves the CID for this node, populating the cache.
 * @param cache Map table for storing node CIDs.
 * @return The node's CID.
 */
- (CID *)getCID:(NSMapTable<MSTNode *, CID *> *)cache;

@end

/**
 * @abstract Internal accessors for MSTNodeEntry.
 */
@interface MSTNodeEntry (Internal)

/** @abstract Subtree pointer (may be nil for leaf entries). */
@property (nonatomic, strong, readonly, nullable) MSTNode *internalTree;

/** @abstract Full key of this entry. */
@property (nonatomic, copy, readonly) NSString *fullKey;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file MSTInternal.h
 * @abstract Internal interfaces for Merkle Search Tree nodes.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ATProtoCID;

/**
 * @abstract Internal accessors for ATProtoMSTNode.
 * @discussion Used by ATProtoMSTWalker for efficient tree traversal.
 */
@interface ATProtoMSTNode (Internal)

/** @abstract Leftmost subtree pointer (may be nil). */
@property (nonatomic, strong, readonly, nullable) ATProtoMSTNode *internalLeft;

/** @abstract Mutable array of entries at this node. */
@property (nonatomic, strong, readonly) NSMutableArray<ATProtoMSTNodeEntry *> *internalEntries;

/** @abstract Level of this node in the ATProtoMST. */
@property (nonatomic, assign, readonly) uint32_t level;

/**
 * @abstract Retrieves the ATProtoCID for this node, populating the cache.
 * @param cache Map table for storing node CIDs.
 * @return The node's ATProtoCID.
 */
- (ATProtoCID *)getCID:(NSMapTable<ATProtoMSTNode *, ATProtoCID *> *)cache;

@end

/**
 * @abstract Internal accessors for ATProtoMSTNodeEntry.
 */
@interface ATProtoMSTNodeEntry (Internal)

/** @abstract Subtree pointer (may be nil for leaf entries). */
@property (nonatomic, strong, readonly, nullable) ATProtoMSTNode *internalTree;

/** @abstract Full key of this entry. */
@property (nonatomic, copy, readonly) NSString *fullKey;

@end

NS_ASSUME_NONNULL_END

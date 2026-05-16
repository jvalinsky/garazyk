// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file MSTWalker.h
 * @abstract Traverses an MST in key order.
 * @discussion Implements a depth-first traversal of the MST that walks entries
 * in lexicographic key order. Used by the diff algorithm to compare two trees in
 * parallel. Based on the reference atproto implementation:
 * https://github.com/bluesky-social/atproto/blob/main/packages/repo/src/mst/walker.ts
 */

#import <Foundation/Foundation.h>

@class MSTNode;
@class MSTNodeEntry;
@class CID;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Walker Status Types

/**
 * @abstract Status indicating the walker has finished traversing the tree.
 */
typedef struct MSTWalkerStatusDone {
    BOOL done;
} MSTWalkerStatusDone;

/**
 * @abstract Status indicating the walker is at a specific position.
 * @field done Always NO for progress status.
 * @field curr The current entry (leaf entry or subtree node).
 * @field walking The parent node being walked (nil if at root).
 * @field index The index within the walking node's entries.
 * @field isTreeNode YES if curr is a subtree node, NO if leaf entry.
 */
typedef struct MSTWalkerStatusProgress {
    BOOL done;
    __unsafe_unretained MSTNodeEntry * _Nullable curr;
    __unsafe_unretained MSTNode * _Nullable walking;
    NSUInteger index;
    BOOL isTreeNode;
} MSTWalkerStatusProgress;

/**
 * @abstract Tag for discriminating walker status union.
 */
typedef NS_ENUM(NSUInteger, MSTWalkerStatusTag) {
    MSTWalkerStatusTagDone,
    MSTWalkerStatusTagProgress
};

/**
 * @abstract Represents the current state of an MST walker.
 * @discussion Walker can be either "done" (finished traversing) or "in progress"
 * (at a specific node/entry in the tree). This mirrors the reference implementation's 
 * WalkerStatus union type.
 */
@interface MSTWalkerStatus : NSObject

/** @abstract Current status tag. */
@property (nonatomic, assign, readonly) MSTWalkerStatusTag tag;
/** @abstract Done status structure. */
@property (nonatomic, assign, readonly) MSTWalkerStatusDone doneStatus;
/** @abstract Progress status structure. */
@property (nonatomic, assign, readonly) MSTWalkerStatusProgress progressStatus;

/** @abstract Creates a done status instance. */
+ (instancetype)doneStatus;
/** @abstract Creates a progress status instance. */
+ (instancetype)progressWithEntry:(nullable MSTNodeEntry *)entry
                          walking:(nullable MSTNode *)walking
                            index:(NSUInteger)index
                       isTreeNode:(BOOL)isTreeNode;

/** @abstract Whether the traversal is complete. */
- (BOOL)isDone;
/** @abstract Current entry, or nil if none. */
- (nullable MSTNodeEntry *)currentEntry;
/** @abstract Current node, or nil if at root. */
- (nullable MSTNode *)walkingNode;
/** @abstract Current index. */
- (NSUInteger)index;
/** @abstract Whether the current entry is a subtree node. */
- (BOOL)isTreeNode;

@end

#pragma mark - MSTWalker

/**
 * @abstract Traverses an MST in key order.
 * @discussion Implements a depth-first traversal of the MST that walks entries
 * in lexicographic key order. Used by the diff algorithm to compare two trees in
 * parallel.
 *
 * Usage:
 * @code
 * MSTWalker *walker = [[MSTWalker alloc] initWithRootNode:root];
 * while (!walker.status.isDone) {
 *     MSTNodeEntry *entry = walker.status.currentEntry;
 *     // process entry...
 *     [walker advance];
 * }
 * @endcode
 */
@interface MSTWalker : NSObject

/** @abstract The tree root node. */
@property (nonatomic, strong, readonly) MSTNode *root;
/** @abstract Current status. */
@property (nonatomic, strong) MSTWalkerStatus *status;

/**
 * @abstract Initializes a walker starting at the given MST root node.
 * @param root The root node (may be nil for empty tree).
 * @return Initialized walker.
 */
- (instancetype)initWithRootNode:(nullable MSTNode *)root;

/**
 * @abstract Returns the current layer (depth) of the walker.
 * @discussion The layer is determined by the walking node's level.
 * If walking is nil (at root), returns root.level + 1.
 * @return Current layer number.
 * @throws NSInternalInconsistencyException if called when walk is done.
 */
- (NSUInteger)layer;

/**
 * @abstract Moves to the next sibling, skipping the current subtree.
 * @discussion If the current entry is a subtree, this skips over it entirely.
 * If at the root or last entry, marks walker as done.
 * Called when comparing two subtrees that have identical CIDs - no need to
 * descend into them.
 * @throws NSInternalInconsistencyException if walk is done.
 */
- (void)stepOver;

/**
 * @abstract Descends into the current subtree.
 * @discussion The current entry must be a subtree (not a leaf).
 * Pushes current state onto stack and moves to first entry of subtree.
 * @throws NSInternalInconsistencyException if current entry is a leaf.
 */
- (void)stepInto;

/**
 * @abstract Moves to the next node in traversal order.
 * @discussion If current is a leaf, calls stepOver. If current is a subtree,
 * calls stepInto to descend into it. This is the main method for walking.
 * @throws NSInternalInconsistencyException if walk is done.
 */
- (void)advance;

@end

NS_ASSUME_NONNULL_END

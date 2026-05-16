// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Based on https://github.com/bluesky-social/atproto (MIT OR Apache-2.0)
#import <Foundation/Foundation.h>

@class MSTNode;
@class MSTNodeEntry;
@class CID;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Walker Status Types

/*!

 @abstract Indicates the walker has finished traversing the tree.
 */
typedef struct MSTWalkerStatusDone {
    BOOL done;
} MSTWalkerStatusDone;

/*!

 @abstract Indicates the walker is at a specific position in the tree.

 @field done Always NO for progress status.
 @field curr The current entry (either a leaf entry or a subtree node).
 @field walking The parent node being walked (nil if at root).
 @field index The index within the walking node's entries.
 @field isTreeNode YES if curr is a subtree node, NO if leaf entry.
 */
typedef struct MSTWalkerStatusProgress {
    BOOL done;
    __unsafe_unretained MSTNodeEntry * _Nullable curr;
    __unsafe_unretained MSTNode * _Nullable walking;
    NSUInteger index;
    BOOL isTreeNode;
} MSTWalkerStatusProgress;

/*!

 @abstract Tag for discriminating walker status union.
 */
typedef NS_ENUM(NSUInteger, MSTWalkerStatusTag) {
    MSTWalkerStatusTagDone,
    MSTWalkerStatusTagProgress
};

/*!
 @class MSTWalkerStatus

 @abstract Represents the current state of an MST walker.

 @discussion Walker can be either "done" (finished traversing) or "in progress"
 (at a specific node/entry in the tree). This mirrors the TypeScript reference
 implementation's WalkerStatus union type.
 */
@interface MSTWalkerStatus : NSObject

@property (nonatomic, assign, readonly) MSTWalkerStatusTag tag;
@property (nonatomic, assign, readonly) MSTWalkerStatusDone doneStatus;
@property (nonatomic, assign, readonly) MSTWalkerStatusProgress progressStatus;

+ (instancetype)doneStatus;
+ (instancetype)progressWithEntry:(nullable MSTNodeEntry *)entry
                          walking:(nullable MSTNode *)walking
                            index:(NSUInteger)index
                       isTreeNode:(BOOL)isTreeNode;

- (BOOL)isDone;
- (nullable MSTNodeEntry *)currentEntry;
- (nullable MSTNode *)walkingNode;
- (NSUInteger)index;
- (BOOL)isTreeNode;

@end

#pragma mark - MSTWalker

/*!
 @class MSTWalker

 @abstract Traverses an MST in key order.

 @discussion Implements a depth-first traversal of the MST that walks entries
 in lexicographic key order. Used by the diff algorithm to compare two trees in
 parallel.

 Based on the reference implementation:
 https://github.com/bluesky-social/atproto/blob/main/packages/repo/src/mst/walker.ts

 Usage:
     MSTWalker *walker = [[MSTWalker alloc] initWithRootNode:root];
     while (!walker.status.isDone) {
         MSTNodeEntry *entry = walker.status.currentEntry;
         // process entry...
         [walker advance];
     }
 */
@interface MSTWalker : NSObject

@property (nonatomic, strong, readonly) MSTNode *root;
@property (nonatomic, strong) MSTWalkerStatus *status;

/*!
 @method initWithRootNode:

 @abstract Creates a walker starting at the given MST root node.

 @param root The root node to walk (may be nil for empty tree).
 @return A new walker positioned at the start of the tree.
 */
- (instancetype)initWithRootNode:(nullable MSTNode *)root;

/*!
 @method layer

 @abstract Returns the current layer (depth) of the walker.

 @discussion The layer is determined by the walking node's level.
 If walking is nil (at root), returns root.level + 1.

 @return The current layer number.
 @throws NSInternalInconsistencyException if called when walk is done.
 */
- (NSUInteger)layer;

/*!
 @method stepOver

 @abstract Move to the next sibling, skipping the current subtree.

 @discussion If the current entry is a subtree, this skips over it entirely.
 If at the root or last entry, marks walker as done.

 Called when comparing two subtrees that have identical CIDs - no need to
 descend into them.

 @throws NSInternalInconsistencyException if walk is done.
 */
- (void)stepOver;

/*!
 @method stepInto

 @abstract Descend into the current subtree.

 @discussion The current entry must be a subtree (not a leaf).
 Pushes current state onto stack and moves to first entry of subtree.

 @throws NSInternalInconsistencyException if current entry is a leaf.
 */
- (void)stepInto;

/*!
 @method advance

 @abstract Move to the next node in traversal order.

 @discussion If current is a leaf, calls stepOver. If current is a subtree,
 calls stepInto to descend into it. This is the main method for walking.

 @throws NSInternalInconsistencyException if walk is done.
 */
- (void)advance;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Based on https://github.com/bluesky-social/atproto (MIT OR Apache-2.0)
#import "Repository/MST.h"
#import "Repository/MSTInternal.h"
#import "Repository/MSTWalker.h"

#pragma mark - ATProtoMSTWalkerStatus

@interface ATProtoMSTWalkerStatus ()
@property (nonatomic, assign, readwrite) MSTWalkerStatusTag tag;
@property (nonatomic, assign, readwrite) MSTWalkerStatusDone doneStatus;
@property (nonatomic, assign, readwrite) MSTWalkerStatusProgress progressStatus;
@end

@implementation ATProtoMSTWalkerStatus

+ (instancetype)doneStatus {
    ATProtoMSTWalkerStatus *status = [[ATProtoMSTWalkerStatus alloc] init];
    status.tag = MSTWalkerStatusTagDone;
    status.doneStatus = (MSTWalkerStatusDone){ .done = YES };
    return status;
}

+ (instancetype)progressWithEntry:(ATProtoMSTNodeEntry *)entry
                          walking:(MSTNode *)walking
                            index:(NSUInteger)index
                       isTreeNode:(BOOL)isTreeNode {
    ATProtoMSTWalkerStatus *status = [[ATProtoMSTWalkerStatus alloc] init];
    status.tag = MSTWalkerStatusTagProgress;
    status.progressStatus = (MSTWalkerStatusProgress){
        .done = NO,
        .curr = entry,
        .walking = walking,
        .index = index,
        .isTreeNode = isTreeNode
    };
    return status;
}

- (BOOL)isDone {
    return self.tag == MSTWalkerStatusTagDone;
}

- (ATProtoMSTNodeEntry *)currentEntry {
    if (self.tag == MSTWalkerStatusTagProgress) {
        return self.progressStatus.curr;
    }
    return nil;
}

- (MSTNode *)walkingNode {
    if (self.tag == MSTWalkerStatusTagProgress) {
        return self.progressStatus.walking;
    }
    return nil;
}

- (NSUInteger)index {
    if (self.tag == MSTWalkerStatusTagProgress) {
        return self.progressStatus.index;
    }
    return NSNotFound;
}

- (BOOL)isTreeNode {
    if (self.tag == MSTWalkerStatusTagProgress) {
        return self.progressStatus.isTreeNode;
    }
    return NO;
}

@end

#pragma mark - ATProtoMSTWalker Private Interface

@interface ATProtoMSTWalker ()

/// Stack of states for backtracking when stepping out of subtrees
@property (nonatomic, strong) NSMutableArray<ATProtoMSTWalkerStatus *> *stack;
@property (nonatomic, strong) NSArray<ATProtoMSTNodeEntry *> *flatEntries;
@property (nonatomic, assign) NSUInteger flatIndex;

@end

#pragma mark - ATProtoMSTWalker Implementation

@implementation ATProtoMSTWalker

- (instancetype)initWithRootNode:(MSTNode *)root {
    self = [super init];
    if (self) {
        _root = root;
        _stack = [NSMutableArray array];
        NSMutableArray<ATProtoMSTNodeEntry *> *entries = [NSMutableArray array];
        [self collectEntriesFromNode:root into:entries];
        _flatEntries = [entries copy];
        _flatIndex = 0;
        
        if (_flatEntries.count == 0) {
            _status = [ATProtoMSTWalkerStatus doneStatus];
        } else {
            _status = [ATProtoMSTWalkerStatus progressWithEntry:_flatEntries[0]
                                                  walking:root
                                                    index:0
                                               isTreeNode:NO];
        }
    }
    return self;
}

- (void)collectEntriesFromNode:(MSTNode *)node into:(NSMutableArray<ATProtoMSTNodeEntry *> *)entries {
    if (!node) return;
    [self collectEntriesFromNode:node.internalLeft into:entries];
    for (ATProtoMSTNodeEntry *entry in node.internalEntries) {
        [entries addObject:entry];
        [self collectEntriesFromNode:entry.internalTree into:entries];
    }
}

- (NSUInteger)layer {
    if (self.status.isDone) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                     reason:@"Walk is done"
                                   userInfo:nil];
    }
    
    // If walking is set, return its level
    MSTNode *walking = self.status.walkingNode;
    if (walking != nil) {
        return walking.level;
    }
    
    // If walking is nil, we're at the root
    // Root layer is root.level + 1 (matching TypeScript implementation)
    if (self.status.isTreeNode) {
        return self.root.level + 1;
    }
    
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                 reason:@"Could not identify layer of walk"
                               userInfo:nil];
}

- (void)stepOver {
    if (self.status.isDone) return;
    
    if (self.flatEntries.count > 0) {
        self.flatIndex++;
        if (self.flatIndex >= self.flatEntries.count) {
            self.status = [ATProtoMSTWalkerStatus doneStatus];
        } else {
            self.status = [ATProtoMSTWalkerStatus progressWithEntry:self.flatEntries[self.flatIndex]
                                                      walking:self.root
                                                        index:self.flatIndex
                                                   isTreeNode:NO];
        }
        return;
    }

    MSTNode *walking = self.status.walkingNode;
    
    // If walking is nil, we're at the root - stepping over means done
    if (walking == nil) {
        self.status = [ATProtoMSTWalkerStatus doneStatus];
        return;
    }
    
    // Get entries of current walking node
    NSArray<ATProtoMSTNodeEntry *> *entries = walking.internalEntries;
    NSUInteger nextIndex = (self.status.index == NSNotFound) ? 0 : self.status.index + 1;
    
    if (nextIndex >= entries.count) {
        // No more entries at this level, pop stack
        ATProtoMSTWalkerStatus *popped = self.stack.lastObject;
        [self.stack removeLastObject];
        
        if (popped == nil) {
            // Nothing to pop, we're done
            self.status = [ATProtoMSTWalkerStatus doneStatus];
        } else {
            // Restore previous state and step over there too
            self.status = popped;
            [self stepOver]; // Recursive step over at parent level
        }
    } else {
        // Move to next entry at this level
        ATProtoMSTNodeEntry *nextEntry = entries[nextIndex];
        BOOL isTree = (nextEntry.internalTree != nil);
        self.status = [ATProtoMSTWalkerStatus progressWithEntry:nextEntry
                                                  walking:walking
                                                    index:nextIndex
                                               isTreeNode:isTree];
    }
}

- (void)stepInto {
    if (self.status.isDone) return;
    
    MSTNode *walking = self.status.walkingNode;
    
    // Edge case: at root with walking = nil
    if (walking == nil) {
        // Current is the root tree
        if (!self.status.isTreeNode) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                         reason:@"The root of the tree cannot be a leaf"
                                       userInfo:nil];
        }
        
        // Step into root: get first entry
        NSArray<ATProtoMSTNodeEntry *> *entries = self.root.internalEntries;
        
        // Also need to consider internalLeft first
        if (self.root.internalLeft != nil) {
            // Root has a left subtree - start there
            self.status = [ATProtoMSTWalkerStatus progressWithEntry:nil
                                                      walking:self.root
                                                        index:NSNotFound
                                                   isTreeNode:YES];
            // Actually we need to descend into internalLeft
            [self pushStateAndDescendInto:self.root.internalLeft];
            return;
        }
        
        ATProtoMSTNodeEntry *first = entries.firstObject;
        if (first == nil) {
            self.status = [ATProtoMSTWalkerStatus doneStatus];
        } else {
            BOOL isTree = (first.internalTree != nil);
            self.status = [ATProtoMSTWalkerStatus progressWithEntry:first
                                                      walking:self.root
                                                        index:0
                                                   isTreeNode:isTree];
        }
        return;
    }
    
    // Normal case: need to step into current entry's subtree
    ATProtoMSTNodeEntry *currentEntry = self.status.currentEntry;
    
    // Current must be a tree to step into
    if (currentEntry == nil || !self.status.isTreeNode) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                     reason:@"No tree at pointer, cannot step into"
                                   userInfo:nil];
    }
    
    if (currentEntry.internalTree == nil) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                     reason:@"Current entry has no subtree"
                                   userInfo:nil];
    }
    
    [self pushStateAndDescendInto:currentEntry.internalTree];
}

- (void)pushStateAndDescendInto:(MSTNode *)subtree {
    // Validate subtree has content
    if (subtree.internalEntries.count == 0 && subtree.internalLeft == nil) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                     reason:@"Tried to step into a node with 0 entries"
                                   userInfo:nil];
    }
    
    // Push current state
    [self.stack addObject:self.status];
    
    // Check for left subtree first
    if (subtree.internalLeft != nil) {
        // Start by walking into left subtree
        self.status = [ATProtoMSTWalkerStatus progressWithEntry:nil
                                                  walking:subtree
                                                    index:NSNotFound
                                                   isTreeNode:YES];
        // Descend into internalLeft recursively
        [self pushStateAndDescendInto:subtree.internalLeft];
        return;
    }
    
    // No left subtree, start at first entry
    ATProtoMSTNodeEntry *first = subtree.internalEntries.firstObject;
    if (first == nil) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                     reason:@"Tried to step into a node with 0 entries"
                                   userInfo:nil];
    }
    
    BOOL isTree = (first.internalTree != nil);
    self.status = [ATProtoMSTWalkerStatus progressWithEntry:first
                                              walking:subtree
                                                index:0
                                           isTreeNode:isTree];
}

- (void)advance {
    if (self.status.isDone) return;
    
    if (self.status.isTreeNode) {
        // Current is a tree: step into it
        [self stepInto];
    } else {
        // Current is a leaf: step over to next
        [self stepOver];
    }
}

@end

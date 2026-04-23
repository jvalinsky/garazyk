#import "Repository/MST.h"
#import "Repository/MSTInternal.h"
#import "Repository/MSTWalker.h"

#pragma mark - MSTWalkerStatus

@interface MSTWalkerStatus ()
@property (nonatomic, assign, readwrite) MSTWalkerStatusTag tag;
@property (nonatomic, assign, readwrite) MSTWalkerStatusDone doneStatus;
@property (nonatomic, assign, readwrite) MSTWalkerStatusProgress progressStatus;
@end

@implementation MSTWalkerStatus

+ (instancetype)doneStatus {
    MSTWalkerStatus *status = [[MSTWalkerStatus alloc] init];
    status.tag = MSTWalkerStatusTagDone;
    status.doneStatus = (MSTWalkerStatusDone){ .done = YES };
    return status;
}

+ (instancetype)progressWithEntry:(MSTNodeEntry *)entry
                          walking:(MSTNode *)walking
                            index:(NSUInteger)index
                       isTreeNode:(BOOL)isTreeNode {
    MSTWalkerStatus *status = [[MSTWalkerStatus alloc] init];
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

- (MSTNodeEntry *)currentEntry {
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

#pragma mark - MSTWalker Private Interface

@interface MSTWalker ()

/// Stack of states for backtracking when stepping out of subtrees
@property (nonatomic, strong) NSMutableArray<MSTWalkerStatus *> *stack;

@end

#pragma mark - MSTWalker Implementation

@implementation MSTWalker

- (instancetype)initWithRootNode:(MSTNode *)root {
    self = [super init];
    if (self) {
        _root = root;
        _stack = [NSMutableArray array];
        
        if (root == nil) {
            _status = [MSTWalkerStatus doneStatus];
        } else {
            // At root: walking is nil, curr is the root node treated as tree entry
            _status = [MSTWalkerStatus progressWithEntry:nil
                                                  walking:nil
                                                    index:0
                                               isTreeNode:YES];
            // We need a way to represent "at root tree"
            // Store the root as a special case - curr is nil but we know we're at tree
        }
    }
    return self;
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
    
    MSTNode *walking = self.status.walkingNode;
    
    // If walking is nil, we're at the root - stepping over means done
    if (walking == nil) {
        self.status = [MSTWalkerStatus doneStatus];
        return;
    }
    
    // Get entries of current walking node
    NSArray<MSTNodeEntry *> *entries = walking.internalEntries;
    NSUInteger nextIndex = (self.status.index == NSNotFound) ? 0 : self.status.index + 1;
    
    if (nextIndex >= entries.count) {
        // No more entries at this level, pop stack
        MSTWalkerStatus *popped = self.stack.lastObject;
        [self.stack removeLastObject];
        
        if (popped == nil) {
            // Nothing to pop, we're done
            self.status = [MSTWalkerStatus doneStatus];
        } else {
            // Restore previous state and step over there too
            self.status = popped;
            [self stepOver]; // Recursive step over at parent level
        }
    } else {
        // Move to next entry at this level
        MSTNodeEntry *nextEntry = entries[nextIndex];
        BOOL isTree = (nextEntry.internalTree != nil);
        self.status = [MSTWalkerStatus progressWithEntry:nextEntry
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
        NSArray<MSTNodeEntry *> *entries = self.root.internalEntries;
        
        // Also need to consider internalLeft first
        if (self.root.internalLeft != nil) {
            // Root has a left subtree - start there
            self.status = [MSTWalkerStatus progressWithEntry:nil
                                                      walking:self.root
                                                        index:NSNotFound
                                                   isTreeNode:YES];
            // Actually we need to descend into internalLeft
            [self pushStateAndDescendInto:self.root.internalLeft];
            return;
        }
        
        MSTNodeEntry *first = entries.firstObject;
        if (first == nil) {
            self.status = [MSTWalkerStatus doneStatus];
        } else {
            BOOL isTree = (first.internalTree != nil);
            self.status = [MSTWalkerStatus progressWithEntry:first
                                                      walking:self.root
                                                        index:0
                                                   isTreeNode:isTree];
        }
        return;
    }
    
    // Normal case: need to step into current entry's subtree
    MSTNodeEntry *currentEntry = self.status.currentEntry;
    
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
        self.status = [MSTWalkerStatus progressWithEntry:nil
                                                  walking:subtree
                                                    index:NSNotFound
                                                   isTreeNode:YES];
        // Descend into internalLeft recursively
        [self pushStateAndDescendInto:subtree.internalLeft];
        return;
    }
    
    // No left subtree, start at first entry
    MSTNodeEntry *first = subtree.internalEntries.firstObject;
    if (first == nil) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                     reason:@"Tried to step into a node with 0 entries"
                                   userInfo:nil];
    }
    
    BOOL isTree = (first.internalTree != nil);
    self.status = [MSTWalkerStatus progressWithEntry:first
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

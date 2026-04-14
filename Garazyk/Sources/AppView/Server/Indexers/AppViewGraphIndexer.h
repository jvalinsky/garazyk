/*!
 @file AppViewGraphIndexer.h

 @abstract Indexes app.bsky.graph.* records: follows, blocks, lists, list items,
 starter packs, and follow-blocks.

 Handles:
  - app.bsky.graph.follow
  - app.bsky.graph.block
  - app.bsky.graph.list
  - app.bsky.graph.listitem
  - app.bsky.graph.listblock
  - app.bsky.graph.starterpack

 Also writes follows of seed DIDs into the relevance set.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "AppViewIndexer.h"

NS_ASSUME_NONNULL_BEGIN

@class AppViewDatabase;
@class AppViewRelevanceSet;

@interface AppViewGraphIndexer : NSObject <AppViewIndexer>

- (instancetype)initWithDatabase:(AppViewDatabase *)database
                    relevanceSet:(nullable AppViewRelevanceSet *)relevanceSet;

@end

NS_ASSUME_NONNULL_END

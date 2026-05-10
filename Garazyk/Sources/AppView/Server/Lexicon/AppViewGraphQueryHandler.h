/*!
 @file AppViewGraphQueryHandler.h

 @abstract Custom query handler for app.bsky.graph XRPC endpoints.

 @discussion Handles domain-specific graph queries that require the
 GraphService rather than the generic record lookup:
 - app.bsky.graph.getStarterPack (single starter pack by URI)
 - app.bsky.graph.getStarterPacks (batch starter packs by URIs)
 - app.bsky.graph.getActorStarterPacks (actor's starter packs)

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

#import "AppViewCustomQueryRegistry.h"

@class GraphService;

NS_ASSUME_NONNULL_BEGIN

@interface AppViewGraphQueryHandler : NSObject <AppViewLexiconQueryHandler>

- (instancetype)initWithGraphService:(GraphService *)graphService;

@end

NS_ASSUME_NONNULL_END

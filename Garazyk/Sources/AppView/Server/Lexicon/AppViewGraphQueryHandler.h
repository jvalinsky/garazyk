// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZAppViewGraphQueryHandler.h

 @abstract Custom query handler for app.bsky.graph XRPC endpoints.

 @discussion Handles domain-specific graph queries that require the
 PDSGraphService rather than the generic record lookup:
 - app.bsky.graph.getStarterPack (single starter pack by URI)
 - app.bsky.graph.getStarterPacks (batch starter packs by URIs)
 - app.bsky.graph.getActorStarterPacks (actor's starter packs)

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

#import "AppViewCustomQueryRegistry.h"

@class PDSGraphService;

NS_ASSUME_NONNULL_BEGIN

@interface GZAppViewGraphQueryHandler : NSObject <AppViewLexiconQueryHandler>

- (instancetype)initWithGraphService:(PDSGraphService *)graphService;

@end

NS_ASSUME_NONNULL_END

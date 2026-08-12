// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class GZAppViewBackfillOrchestrator;
@class GZAppViewIngestEngine;
@class GZAppViewDatabase;
@class ATProtoLexiconRegistry;
@class GZAppViewIndexHookRegistry;
@class GZAppViewCustomQueryRegistry;
@class GZAppViewLexiconEndpointGenerator;
@class ATProtoHttpServer;

NS_ASSUME_NONNULL_BEGIN

@interface GZAppViewAdminRoutePack : NSObject

- (instancetype)initWithOrchestrator:(nullable GZAppViewBackfillOrchestrator *)orchestrator
                        ingestEngine:(GZAppViewIngestEngine *)ingestEngine
                            database:(GZAppViewDatabase *)database
                         adminSecret:(nullable NSString *)adminSecret;

- (void)registerRoutesWithServer:(ATProtoHttpServer *)server;

/*!
 @method setLexiconRegistry:

 @abstract Set the lexicon registry for lexicon admin endpoints.
 */
- (void)setLexiconRegistry:(nullable ATProtoLexiconRegistry *)registry;

/*!
 @method setHookRegistry:

 @abstract Set the index hook registry for hook admin endpoints.
 */
- (void)setHookRegistry:(nullable GZAppViewIndexHookRegistry *)hookRegistry;

/*!
 @method setCustomQueryRegistry:

 @abstract Set the custom query registry for handler admin endpoints.
 */
- (void)setCustomQueryRegistry:(nullable GZAppViewCustomQueryRegistry *)customQueryRegistry;

/*!
 @method setLexiconEndpointGenerator:

 @abstract Set the lexicon endpoint generator for endpoint admin endpoints.
 */
- (void)setLexiconEndpointGenerator:(nullable GZAppViewLexiconEndpointGenerator *)generator;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class AppViewBackfillOrchestrator;
@class AppViewIngestEngine;
@class AppViewDatabase;
@class ATProtoLexiconRegistry;
@class AppViewIndexHookRegistry;
@class AppViewCustomQueryRegistry;
@class AppViewLexiconEndpointGenerator;
@class HttpServer;

NS_ASSUME_NONNULL_BEGIN

@interface AppViewAdminRoutePack : NSObject

/**
 * @abstract Performs the initWithOrchestrator operation.
 */
- (instancetype)initWithOrchestrator:(nullable AppViewBackfillOrchestrator *)orchestrator
                        ingestEngine:(AppViewIngestEngine *)ingestEngine
                            database:(AppViewDatabase *)database
                         adminSecret:(nullable NSString *)adminSecret;

/**
 * @abstract Performs the registerRoutesWithServer operation.
 */
- (void)registerRoutesWithServer:(HttpServer *)server;

/*!
 @method setLexiconRegistry:

 @abstract Set the lexicon registry for lexicon admin endpoints.
 */
- (void)setLexiconRegistry:(nullable ATProtoLexiconRegistry *)registry;

/*!
 @method setHookRegistry:

 @abstract Set the index hook registry for hook admin endpoints.
 */
- (void)setHookRegistry:(nullable AppViewIndexHookRegistry *)hookRegistry;

/*!
 @method setCustomQueryRegistry:

 @abstract Set the custom query registry for handler admin endpoints.
 */
- (void)setCustomQueryRegistry:(nullable AppViewCustomQueryRegistry *)customQueryRegistry;

/*!
 @method setLexiconEndpointGenerator:

 @abstract Set the lexicon endpoint generator for endpoint admin endpoints.
 */
- (void)setLexiconEndpointGenerator:(nullable AppViewLexiconEndpointGenerator *)generator;

@end

NS_ASSUME_NONNULL_END

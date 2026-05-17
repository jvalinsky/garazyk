// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewLexiconEndpointGenerator.h

 @abstract Registers XRPC routes from loaded lexicon schemas.

 @discussion Iterates all loaded schemas in the ATProtoLexiconRegistry
 and registers dynamic XRPC endpoints for query and procedure definitions.
 Domain-specific routes (app.bsky.*) registered by AppViewXRpcRoutePack
 take priority via the HttpRouteTrie's exact-match-first behavior.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Lexicon/ATProtoLexiconSchema.h"

NS_ASSUME_NONNULL_BEGIN

@class ATProtoLexiconRegistry;
@class AppViewDatabase;
@class AppViewCustomQueryRegistry;
@class AppViewGenericQueryHandler;
@class HttpServer;

extern NSErrorDomain const AppViewLexiconEndpointGeneratorErrorDomain;

/*!
 @class AppViewLexiconEndpointGenerator

 @abstract Generates and registers XRPC routes from loaded lexicon schemas.
 */
@interface AppViewLexiconEndpointGenerator : NSObject

/*!
 @method initWithRegistry:database:httpServer:customHandlers:

 @abstract Initialize the generator with all required dependencies.

 @param registry        The lexicon registry (already loaded with schemas).
 @param database        The AppView database for record queries.
 @param httpServer      The HTTP server to register routes on.
 @param customHandlers  The custom handler registry for per-NSID overrides.
 */
- (instancetype)initWithRegistry:(ATProtoLexiconRegistry *)registry
                         database:(AppViewDatabase *)database
                      httpServer:(HttpServer *)httpServer
                 customHandlers:(AppViewCustomQueryRegistry *)customHandlers;

/*!
 @method registerDynamicEndpointsWithError:

 @abstract Scan all loaded schemas and register XRPC routes.

 @discussion For each schema:
 - Query definitions → GET /xrpc/{nsid}
 - Procedure definitions → POST /xrpc/{nsid}
 - Record definitions → noted for generic indexing

 Routes are registered after domain-specific routes, so the trie's
 exact-match takes priority over the generic handler.

 @param error Output parameter for registration errors.
 @return YES if all routes registered successfully, NO on failure.
 */
/**
 * @abstract Performs the registerDynamicEndpointsWithError operation.
 */
- (BOOL)registerDynamicEndpointsWithError:(NSError **)error;

/*!
 @method registerEndpointsForSchema:error:

 @abstract Register routes for a single schema.

 @param schema The lexicon schema to register routes for.
 @param error  Output parameter for errors.

 @return YES if routes registered successfully, NO on failure.
 */
- (BOOL)registerEndpointsForSchema:(ATProtoLexiconSchema *)schema
                             error:(NSError **)error;

/*!
 @method registeredEndpointCount

 @abstract Return the number of dynamic endpoints registered.

 @return Count of registered dynamic routes.
 */
- (NSUInteger)registeredEndpointCount;

/*!
 @method queryHandler

 @abstract Return the generic query handler (for testing or direct use).

 @return The AppViewGenericQueryHandler instance.
 */
- (AppViewGenericQueryHandler *)queryHandler;

@end

NS_ASSUME_NONNULL_END

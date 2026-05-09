/*!
 @file AppViewGenericQueryHandler.h

 @abstract Generic query and procedure handler for lexicon-driven endpoints.

 @discussion Handles XRPC requests for NSIDs that don't have a domain-specific
 handler. Validates parameters against the lexicon schema, queries the
 records table, and returns results in the lexicon-specified output shape.

 Routing priority:
 1. Custom handler registry (AppViewCustomQueryRegistry)
 2. Generic CRUD (this class)

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ATProtoLexiconRegistry;
@class AppViewDatabase;
@class AppViewCustomQueryRegistry;
@class HttpRequest;
@class HttpResponse;

extern NSErrorDomain const AppViewGenericQueryHandlerErrorDomain;

/*!
 @class AppViewGenericQueryHandler

 @abstract Handles generic query and procedure requests for lexicon-driven endpoints.
 */
@interface AppViewGenericQueryHandler : NSObject

/*!
 @method initWithRegistry:database:customHandlers:

 @abstract Initialize with the lexicon registry, database, and custom handler registry.

 @param registry        The lexicon registry for schema lookups.
 @param database        The AppView database for record queries.
 @param customHandlers  The custom handler registry (takes priority over generic).
 */
- (instancetype)initWithRegistry:(ATProtoLexiconRegistry *)registry
                         database:(AppViewDatabase *)database
                  customHandlers:(AppViewCustomQueryRegistry *)customHandlers;

/*!
 @method handleQuery:response:nsid:

 @abstract Handle a GET query request for the given NSID.

 @param request  The HTTP request.
 @param response The HTTP response to populate.
 @param nsid     The NSID of the query endpoint.
 */
- (void)handleQuery:(HttpRequest *)request
            response:(HttpResponse *)response
               nsid:(NSString *)nsid;

/*!
 @method handleProcedure:response:nsid:

 @abstract Handle a POST procedure request for the given NSID.

 @param request  The HTTP request.
 @param response The HTTP response to populate.
 @param nsid     The NSID of the procedure endpoint.
 */
- (void)handleProcedure:(HttpRequest *)request
                response:(HttpResponse *)response
                   nsid:(NSString *)nsid;

@end

NS_ASSUME_NONNULL_END

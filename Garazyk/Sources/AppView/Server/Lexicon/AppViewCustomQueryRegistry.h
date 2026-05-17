// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewCustomQueryRegistry.h

 @abstract Registry for custom ObjC query handlers per-NSID.

 @discussion Custom handlers take priority over the generic CRUD handler
 for their registered NSID. This follows the same pattern as AppViewIndexer
 with canIndexCollection: routing — domain-specific logic wins over generic.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AppViewDatabase;
@class HttpRequest;
@class HttpResponse;

extern NSErrorDomain const AppViewCustomQueryRegistryErrorDomain;

/*!
 @protocol AppViewLexiconQueryHandler

 @abstract Custom query handler for a specific NSID.

 @discussion Implement this protocol to provide domain-specific query logic
 for a lexicon-driven endpoint. The handler receives parsed parameters and
 the database, and returns a result dictionary.

 Handlers are called on the HTTP server's request queue. All methods must
 be safe to call from any thread.
 */
@protocol AppViewLexiconQueryHandler <NSObject>

/*!
 @method handleQueryWithParams:input:database:callerDID:result:error:

 @abstract Handle a query or procedure request for this handler's NSID.

 @param params    Parsed query parameters from the request URL.
 @param input     Parsed JSON body (nil for GET queries).
 @param database  The AppView database for querying records.
 @param callerDID  The authenticated caller's DID (nil if unauthenticated).
 @param result    Output parameter for the response body dictionary.
 @param error     Output parameter for errors.

 @return YES if the handler produced a result, NO on error.
 */
/**
 * @abstract Performs the handleQueryWithParams operation.
 */
- (BOOL)handleQueryWithParams:(NSDictionary<NSString *, NSString *> *)params
                        input:(nullable NSDictionary *)input
                     database:(AppViewDatabase *)database
                    callerDID:(nullable NSString *)callerDID
                       result:(NSDictionary *_Nullable *_Nullable)result
                        error:(NSError **)error;

@optional

/*!
 @method nsid

 @abstract The NSID this handler is registered for.

 @discussion If nil, the registration key is used instead.
 Override this to return the NSID rather than passing it at registration time.
 */
- (nullable NSString *)nsid;

/*!
 @method requiresAuth

 @abstract Whether this handler requires authentication.

 @discussion If YES, the generic handler will extract the caller DID
 before dispatching to this handler. Default is NO.
 */
- (BOOL)requiresAuth;

@end

/*!
 @class AppViewCustomQueryRegistry

 @abstract Registry for per-NSID custom query handlers.
 */
@interface AppViewCustomQueryRegistry : NSObject

/*!
 @method registerHandler:forNSID:

 @abstract Register a custom handler for a specific NSID.

 @param handler The handler to register.
 @param nsid    The NSID to register it for (e.g., "com.shinolabs.pinksea.getRecent").
 */
- (void)registerHandler:(id<AppViewLexiconQueryHandler>)handler forNSID:(NSString *)nsid;

/*!
 @method handlerForNSID:

 @abstract Look up a custom handler for the given NSID.

 @param nsid The NSID to look up.

 @return The registered handler, or nil if none exists.
 */
- (nullable id<AppViewLexiconQueryHandler>)handlerForNSID:(NSString *)nsid;

/*!
 @method hasHandlerForNSID:

 @abstract Check if a custom handler exists for the given NSID.

 @param nsid The NSID to check.

 @return YES if a handler is registered, NO otherwise.
 */
- (BOOL)hasHandlerForNSID:(NSString *)nsid;

/*!
 @method registeredNSIDs

 @abstract Return all NSIDs with registered custom handlers.

 @return Array of NSID strings.
 */
- (NSArray<NSString *> *)registeredNSIDs;

/*!
 @method unregisterHandlerForNSID:

 @abstract Remove a custom handler for the given NSID.

 @param nsid The NSID to unregister.
 */
- (void)unregisterHandlerForNSID:(NSString *)nsid;

@end

NS_ASSUME_NONNULL_END

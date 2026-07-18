// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;
@class JWTMinter;
@class PDSDatabasePool;
/**
 * @abstract Defines the XrpcMiddleware protocol contract.
 */
@protocol XrpcMiddleware;

/*!
 @header XrpcHandler.h
 
 @abstract XRPC dispatcher for ATProto RPC methods.
 
 @discussion This header defines the XrpcDispatcher class for handling
 ATProto XRPC method calls. XRPC is the remote procedure call protocol
 used by ATProto for API requests.
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

/*!
 
 @abstract Block type for handling XRPC method calls.
 
 @param request The incoming HTTP request containing the XRPC call.
 @param response The response object to populate with results.
 */
typedef void (^XrpcMethodHandler)(HttpRequest *request, HttpResponse *response);

/*!

 @abstract Optional pre-dispatch interceptor for XRPC requests.

 @discussion Invoked after method extraction and handler lookup, but before
 normal dispatch/default handling. Return YES to indicate the interceptor
 handled the request and no further dispatch should occur.
 */
typedef BOOL (^XrpcRequestInterceptor)(HttpRequest *request,
                                       HttpResponse *response,
                                       NSString *methodId,
                                       BOOL hasLocalHandler);

/*!
 @class XrpcDispatcher
 
 @abstract Dispatches XRPC method calls to handlers.
 
 @discussion XrpcDispatcher routes incoming XRPC requests to registered
 handlers based on the method NSID. Use registerMethod:handler: with
 generated NSID constants (GZXrpcNSID.h) for type-safe registration.
 
 @code
 XrpcDispatcher *dispatcher = [XrpcDispatcher sharedDispatcher];
 
 [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_createSession handler:^(HttpRequest *req, HttpResponse *resp) {
     // Handle createSession call
 }];
 
 [dispatcher handleRequest:request response:response];
 @endcode
 */
/**
 * @abstract Declares the XrpcDispatcher public API.
 */
@interface XrpcDispatcher : NSObject

/*! Default handler for unrecognized methods. */
@property (nonatomic, copy) void (^defaultHandler)(HttpRequest *, HttpResponse *);

/*! Optional pre-dispatch interceptor for proxying/fallback behavior. */
@property (nonatomic, copy, nullable) XrpcRequestInterceptor requestInterceptor;

/*! Upstream AppView URL for proxying unregistered app.bsky.* methods. */
@property (nonatomic, copy, nullable) NSURL *proxyURL;

/*! Upstream AppView DID for service-to-service auth. */
@property (nonatomic, copy, nullable) NSString *upstreamDID;

/*! Minter for service-to-service auth tokens. */
@property (nonatomic, strong, nullable) JWTMinter *jwtMinter;

/*! Upstream Ozone moderation service URL for proxying unregistered tools.ozone.* methods. */
@property (nonatomic, copy, nullable) NSURL *ozoneURL;

/*! Upstream Ozone moderation service DID for service-to-service auth. */
@property (nonatomic, copy, nullable) NSString *ozoneDID;

/*! Upstream Chat service URL for proxying chat.bsky.* methods. */
@property (nonatomic, copy, nullable) NSURL *chatURL;

/*! Upstream Chat service DID for service-to-service auth. */
@property (nonatomic, copy, nullable) NSString *chatDID;

/*! User database pool for resolving actor signing keys during service auth. */
@property (nonatomic, strong, nullable) PDSDatabasePool *userDatabasePool;

/*!
 @method sharedDispatcher
  
 @abstract Returns the shared dispatcher instance.
  
 @return The singleton XrpcDispatcher.
 */
+ (instancetype)sharedDispatcher;

/*!
 @method resetSharedDispatcher
 
 @abstract Resets the shared dispatcher instance.
 */
+ (void)resetSharedDispatcher;


/*!
 @method registerMethod:handler:
 
 @abstract Registers a handler for an XRPC method.
 
 @param methodId The method NSID (e.g., com.atproto.server.createSession).
 @param handler The handler to invoke for this method.

 @throws NSInternalInconsistencyException if a handler is already registered
 for the method ID. A method has one owner for the lifetime of a dispatcher.
 */
- (void)registerMethod:(NSString *)methodId handler:(XrpcMethodHandler)handler;

/*! Returns YES when a handler has already been registered for methodId. */
- (BOOL)hasRegisteredMethod:(NSString *)methodId;

/*! Clears all registered XRPC method handlers before a complete registry rebuild. */
- (void)resetRegisteredMethods;

/*!
 @method handleRequest:response:
 
 @abstract Dispatches an XRPC request to the appropriate handler.
 
 @param request The incoming request.
 @param response The response object to populate.
 */
- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;

// MARK: - Middleware Support

/*!
 @method registerMethod:middlewares:handler:
 
 @abstract Registers a handler with middleware chain.
 
 @discussion The middleware chain is executed before the handler. If any middleware
 returns NO, the chain stops and the response is returned immediately.
 
 @param methodId The method NSID.
 @param middlewares Array of middleware to execute before handler (can be nil).
 @param handler The handler to invoke if all middleware pass.
 */
/**
 * @abstract Performs the registerMethod operation.
 */
- (void)registerMethod:(NSString *)methodId
           middlewares:(nullable NSArray<id<XrpcMiddleware>> *)middlewares
               handler:(XrpcMethodHandler)handler;

@end

NS_ASSUME_NONNULL_END

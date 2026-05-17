// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

/**
 * @abstract Defines the PDSActorKeyManager protocol contract.
 */
@protocol PDSActorKeyManager;

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;
@class JWTMinter;

/*!
 
 @abstract Block that resolves a user DID to their actor key manager
 for signing service auth JWTs.
 
 @param userDID The DID of the user whose signing key is needed.
 @param error On return, contains an error if resolution failed.
 @return The actor key manager, or nil on failure.
 */
typedef _Nullable id<PDSActorKeyManager> (^ServiceAuthSigningKeyResolver)(NSString *userDID, NSError **error);

/*!
 @class XrpcProxyHandler
 
 @abstract Handles proxying XRPC requests to an upstream service.
 
 @discussion When proxying requests, the handler mints a service auth JWT
 per the AT Protocol XRPC spec: signed with the user's repo signing key,
 with iss=userDID, aud=serviceDID#fragment, lxm=method, exp=60s, jti=nonce.
 */
@interface XrpcProxyHandler : NSObject

/*! Upstream service URL (e.g., AppView URL). */
@property (nonatomic, readonly, copy) NSURL *proxyURL;

/*! Upstream service DID for service-to-service auth (with optional fragment). */
@property (nonatomic, readonly, copy) NSString *upstreamDID;

/*! Minter for creating service-to-service tokens. */
@property (nonatomic, readonly, strong) JWTMinter *minter;

/*! Resolver that provides the user's actor key manager for signing service auth JWTs. */
@property (nonatomic, copy, nullable) ServiceAuthSigningKeyResolver signingKeyResolver;

/*!
 @method initWithMinter:
 
 @abstract Initializes a new proxy handler with just a minter.
 */
- (instancetype)initWithMinter:(JWTMinter *)minter;

/*!
 @method initWithProxyURL:upstreamDID:minter:
 
 @abstract Initializes a new proxy handler with a fixed target.
 */
- (instancetype)initWithProxyURL:(NSURL *)proxyURL
                     upstreamDID:(NSString *)upstreamDID
                          minter:(JWTMinter *)minter;

/*!
 @method handleRequest:response:
 
 @abstract Forwards the request to the fixed target.
 */
- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;

/*!
 @method handleRequest:response:baseURL:upstreamDID:
 
 @abstract Forwards the request to a dynamic target.
 */
- (void)handleRequest:(HttpRequest *)request
             response:(HttpResponse *)response
              baseURL:(NSURL *)baseURL
          upstreamDID:(NSString *)upstreamDID;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Repository/STAR.h"

NS_ASSUME_NONNULL_BEGIN

/// Error domain for federation operations
extern NSErrorDomain const FederationErrorDomain;

/// Federation operation error codes
/**
 * @abstract Defines FederationErrorCode values exposed by this API.
 */
typedef NS_ENUM(NSInteger, FederationErrorCode) {
    FederationErrorDIDResolutionFailed = 1,
    FederationErrorNetworkError = 2,
    FederationErrorRemoteServerError = 3,
    FederationErrorInvalidResponse = 4,
    FederationErrorUnsupportedMethod = 5
};

/// Client for forwarding requests to remote PDS instances
/**
 * @abstract Declares the FederationClient public API.
 */
@interface FederationClient : NSObject

/**
 * @abstract Exposes the did resolver value.
 */
@property (nonatomic, strong, nullable) id didResolver;

/*! Preferred repository format for sync requests (getRepo, getCheckout).
    Defaults to PDSRepoFormatCAR. When set to STAR-L0 or STAR-lite, the
    FederationClient sends the appropriate Accept header to request STAR
    format from remote PDS instances that support it. */
@property (nonatomic, assign) PDSRepoFormat preferredRepoFormat;

/// Forward an XRPC request to the appropriate remote PDS based on DID resolution
/// @param method The XRPC method name (e.g., "com.atproto.repo.getRecord")
/// @param parameters Query parameters for GET requests or JSON body for POST requests
/// @param did The DID to resolve for finding the target PDS
/// @param completion Completion block with response data or error
/**
 * @abstract Performs the forwardXrpcRequest operation.
 */
- (void)forwardXrpcRequest:(NSString *)method
                parameters:(nullable NSDictionary *)parameters
                       did:(NSString *)did
                completion:(void (^)(NSDictionary * _Nullable response, NSError * _Nullable error))completion;

/// Forward an XRPC request that returns binary data
/// @param method The XRPC method name (e.g., "com.atproto.sync.getRepo")
/// @param parameters Query parameters for the request
/// @param did The DID to resolve for finding the target PDS
/// @param completion Completion block with binary response data or error
/**
 * @abstract Performs the forwardXrpcBinaryRequest operation.
 */
- (void)forwardXrpcBinaryRequest:(NSString *)method
                      parameters:(nullable NSDictionary *)parameters
                             did:(NSString *)did
                      completion:(void (^)(NSData * _Nullable data, NSError * _Nullable error))completion;

/// Forward a raw HTTP request to a remote PDS
/// @param url The remote PDS URL
/// @param method HTTP method
/// @param headers HTTP headers
/// @param body Request body data
/// @param completion Completion block with response data or error
/**
 * @abstract Performs the forwardHttpRequest operation.
 */
- (void)forwardHttpRequest:(NSURL *)url
                    method:(NSString *)method
                   headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                      body:(nullable NSData *)body
                completion:(void (^)(NSData * _Nullable data, NSHTTPURLResponse * _Nullable response, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;
@class JWTMinter;

/*!
 @class XrpcProxyHandler
 
 @abstract Handles proxying XRPC requests to an upstream service.
 */
@interface XrpcProxyHandler : NSObject

/*! Upstream service URL (e.g., AppView URL). */
@property (nonatomic, readonly, copy) NSURL *proxyURL;

/*! Upstream service DID for service-to-service auth. */
@property (nonatomic, readonly, copy) NSString *upstreamDID;

/*! Minter for creating service-to-service tokens. */
@property (nonatomic, readonly, strong) JWTMinter *minter;

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

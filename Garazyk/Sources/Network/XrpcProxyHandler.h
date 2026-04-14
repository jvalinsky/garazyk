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
 @method initWithProxyURL:upstreamDID:minter:
 
 @abstract Initializes a new proxy handler.
 */
- (instancetype)initWithProxyURL:(NSURL *)proxyURL 
                     upstreamDID:(NSString *)upstreamDID 
                          minter:(JWTMinter *)minter;

/*!
 @method handleRequest:response:
 
 @abstract Forwards the request to the upstream service and populates the response.
 */
- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END

/*!
 @file RelayXRPCMethods.h

 @abstract XRPC endpoints for relay operation.

 @discussion
    RelayXRPCMethods exposes the relay's XRPC interface for:
    - Getting repo head (getHead)
    - Getting repository data (getRepo)
    - Requesting crawl (requestCrawl)
    - Listing known hosts (listHosts)
    
    These mirror com.atproto.sync.* but are specific to relay operation,
    potentially with different auth requirements or behavior.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class HttpRequest;
@class HttpResponse;
@class XrpcDispatcher;
@class RelayConfiguration;
@class RelayRepoStateManager;
@class RelayEventBuffer;

NS_ASSUME_NONNULL_BEGIN

@interface RelayXRPCMethods : NSObject

@property (nonatomic, strong, readonly) RelayConfiguration *configuration;
@property (nonatomic, strong, readonly) RelayRepoStateManager *repoStateManager;
@property (nonatomic, strong, readonly) RelayEventBuffer *eventBuffer;

- (instancetype)initWithConfiguration:(RelayConfiguration *)configuration
                     repoStateManager:(RelayRepoStateManager *)repoStateManager
                          eventBuffer:(RelayEventBuffer *)eventBuffer NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                   configuration:(RelayConfiguration *)configuration
                repoStateManager:(RelayRepoStateManager *)repoStateManager
                     eventBuffer:(RelayEventBuffer *)eventBuffer;

- (void)handleGetRepo:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleListHosts:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleRequestCrawl:(HttpRequest *)request response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoCAMirrorHTTPSFetcher.h

 @abstract Composition-friendly HTTPS fetcher for @c ATProtoCAMirrorResolver (WS12 Phase 10).

 @discussion Lives in MediaCore and takes an injected synchronous HTTP client so
 MediaCore never links Network. Jelcz wraps @c ATProtoSafeHTTPClient at the
 composition root.
 */

#import <Foundation/Foundation.h>
#import "MediaCore/ATProtoCAMirrorResolver.h"

@class ATProtoCID;

NS_ASSUME_NONNULL_BEGIN

/** Synchronous HTTP surface injected by the composition root (mirrors RASL). */
@protocol ATProtoCAMirrorHTTPClient <NSObject>
- (nullable NSData *)sendSynchronousRequest:(NSURLRequest *)request
                                    options:(nullable id)options
                                   response:(NSHTTPURLResponse * _Nullable * _Nullable)response
                                      error:(NSError * _Nullable * _Nullable)error;
@end

FOUNDATION_EXPORT NSErrorDomain const ATProtoCAMirrorHTTPSFetcherErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoCAMirrorHTTPSFetcherErrorCode) {
    ATProtoCAMirrorHTTPSFetcherErrorInvalidArgument = 1,
    ATProtoCAMirrorHTTPSFetcherErrorAllProvidersFailed = 2,
};

/**
 Fetches @c /.well-known/rasl/{cid} from each provider base URL until one
 returns HTTP 200 with a body. Does not verify bytes — the resolver does.
 */
@interface ATProtoCAMirrorHTTPSFetcher : NSObject <ATProtoCAMirrorFetching>

@property (nonatomic, strong, readonly) id<ATProtoCAMirrorHTTPClient> httpClient;
@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, assign) NSUInteger maxResponseBytes;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithHTTPClient:(id<ATProtoCAMirrorHTTPClient>)httpClient
    NS_DESIGNATED_INITIALIZER;

/** Builds @c https://host/.well-known/rasl/{cid} from a provider base URL. */
+ (nullable NSURL *)raslURLForCID:(ATProtoCID *)cid
                    providerBaseURL:(NSString *)providerBaseURL;

@end

NS_ASSUME_NONNULL_END

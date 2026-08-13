// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoCARASLWellKnown.h

 @abstract Serves @c /.well-known/rasl/{cid} from a CA object store (WS12).

 @discussion Unlike PDS RASL (SHA-256 only), this route accepts Big DASL
 BLAKE3 CIDs used by VOD objects and re-verifies digests before serving.
 */
#import <Foundation/Foundation.h>

@class ATProtoCAObjectStore;
@class ATProtoHttpRequest;
@class ATProtoHttpResponse;
@class ATProtoCID;

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoCARASLWellKnown : NSObject

@property (nonatomic, strong, readonly) ATProtoCAObjectStore *objectStore;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithObjectStore:(ATProtoCAObjectStore *)objectStore
    NS_DESIGNATED_INITIALIZER;

- (void)registerRoutesOnServer:(id)server;

/**
 Serves one RASL request. @c includeBody is NO for HEAD.
 Returns YES when status is 200/OK path (including empty HEAD).
 */
- (BOOL)handleRequest:(ATProtoHttpRequest *)request
             response:(ATProtoHttpResponse *)response
          includeBody:(BOOL)includeBody;

/** Parses a path or path-parameter CID string (base or big DASL). */
+ (nullable ATProtoCID *)cidFromRASLParameter:(nullable NSString *)cidParam;

@end

NS_ASSUME_NONNULL_END

// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoCAWatchService.h

 @abstract Content-addressed /watch serving from MASL + CA object store (WS12 Phase 5).

 @discussion Resolves @c /watch/{did}/{manifestCid}/… through the MASL bundle
 path map only — never the filesystem — then streams bytes from
 @c ATProtoCAObjectStore with HTTP Range support and a local moderation denylist.
 */

#import <Foundation/Foundation.h>

@class ATProtoCAObjectStore;
@class ATProtoCAMirrorResolver;
@class ATProtoHttpRequest;
@class ATProtoHttpResponse;
@class ATProtoCID;
@protocol ATProtoCAMediaDenylist;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const ATProtoCAWatchServiceErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoCAWatchServiceErrorCode) {
    ATProtoCAWatchServiceErrorInvalidArgument = 1,
    ATProtoCAWatchServiceErrorNotFound = 2,
    ATProtoCAWatchServiceErrorDenied = 3,
    ATProtoCAWatchServiceErrorRange = 4,
};

/**
 Serves CA VOD resources for @c /watch/{did}/{manifestCid}[/path…] URLs.
 */
@interface ATProtoCAWatchService : NSObject

@property (nonatomic, strong, readonly) ATProtoCAObjectStore *objectStore;
@property (nonatomic, strong, readonly, nullable) id<ATProtoCAMediaDenylist> denylist;
/**
 Optional local-first mirror resolver (WS12 Phase 10). When set, missing
 objects are fetched through it using @c mirrorProviders.
 */
@property (nonatomic, strong, nullable) ATProtoCAMirrorResolver *mirrorResolver;
/** Absolute HTTPS base URLs for mirror fetch (origin watch / RASL hosts). */
@property (nonatomic, copy, nullable) NSArray<NSString *> *mirrorProviders;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithObjectStore:(ATProtoCAObjectStore *)objectStore
                           denylist:(nullable id<ATProtoCAMediaDenylist>)denylist
    NS_DESIGNATED_INITIALIZER;

/**
 Maps the path remainder after @c /watch/{did}/{manifestCid}/ to a MASL bundle path.

 Returns @c @"/" for empty remainder or @c playlist.m3u8. Returns nil when the
 remainder is unsafe (e.g. contains @c .. after percent-decoding) — callers MUST
 respond 404 without touching storage.
 */
+ (nullable NSString *)bundlePathFromWatchRemainder:(nullable NSString *)remainder;

/**
 Parses @c /watch/{did}/{manifestCid}[/…] into did, manifest CID string, and
 bundle path. Returns NO (and leaves out-params untouched) when the URL shape is
 invalid or the bundle path is unsafe.
 */
+ (BOOL)parseWatchPath:(NSString *)path
                 outDID:(NSString * _Nullable * _Nullable)outDID
      outManifestCIDStr:(NSString * _Nullable * _Nullable)outManifestCIDStr
          outBundlePath:(NSString * _Nullable * _Nullable)outBundlePath;

/** Registers GET/OPTIONS/HEAD watch wildcard routes on @c server. */
- (void)registerRoutesOnServer:(id)server;

/** Handles one request (also used by unit tests without a live socket). */
- (void)handleRequest:(ATProtoHttpRequest *)request
             response:(ATProtoHttpResponse *)response;

/**
 Core serve path used by tests: resolve manifest → resource → optional range.
 Does not write a body when denied or not found.
 */
- (BOOL)serveManifestCID:(ATProtoCID *)manifestCID
              bundlePath:(NSString *)bundlePath
             rangeHeader:(nullable NSString *)rangeHeader
                response:(ATProtoHttpResponse *)response
                   error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

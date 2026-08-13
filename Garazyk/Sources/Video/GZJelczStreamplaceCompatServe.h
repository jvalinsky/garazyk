// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZJelczStreamplaceCompatServe.h

 @abstract Flag-gated place.stream.playback.getVideoBlob serve against CA store.
 */

#import <Foundation/Foundation.h>

@class ATProtoCAObjectStore;
@class ATProtoHttpRequest;
@class ATProtoHttpResponse;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const GZJelczStreamplaceCompatServeErrorDomain;

typedef NS_ENUM(NSInteger, GZJelczStreamplaceCompatServeErrorCode) {
    GZJelczStreamplaceCompatServeErrorInvalidArgument = 1,
    GZJelczStreamplaceCompatServeErrorNotFound = 2,
    GZJelczStreamplaceCompatServeErrorRange = 3,
};

/**
 Serves local CA objects in the Streamplace getVideoBlob shape (WS15 Phase 4).

 Registration uses the generated NSID constant at the jelcz composition root
 so VideoService does not take a PUBLIC ATProtoXRPC edge.
 */
@interface GZJelczStreamplaceCompatServe : NSObject

@property (nonatomic, strong, readonly) ATProtoCAObjectStore *objectStore;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithObjectStore:(ATProtoCAObjectStore *)objectStore
    NS_DESIGNATED_INITIALIZER;

/**
 Handles a getVideoBlob-shaped request (query did+cid, optional Range).

 @c did is accepted for lexicon shape / accounting logs but not used for ACL.
 */
- (BOOL)handleRequest:(ATProtoHttpRequest *)request
             response:(ATProtoHttpResponse *)response
                error:(NSError * _Nullable * _Nullable)error;

/** Builds an origin attestation record for a stored CID (publish is operator-owned). */
- (nullable NSDictionary *)originAttestationForCIDString:(NSString *)cidString
                                                   error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END

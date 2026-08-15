// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZJelczStreamplaceIrohBridge.h

 @abstract Receive-only composition boundary for an optional local Streamplace iroh bridge.

 @discussion This Objective-C boundary deliberately does not implement or link an iroh
 protocol.  An independently managed local bridge owns that protocol and exposes one
 HTTP IPC endpoint.  Accepted bytes are returned to the caller only; this class never
 writes Track B segments into Jelcz's CA/VOD store.
 */

#import <Foundation/Foundation.h>
#import "MediaCore/ATProtoCAMirrorHTTPSFetcher.h"

@class GZJelczPeerProviderEntry;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const GZJelczStreamplaceIrohBridgeErrorDomain;

typedef NS_ENUM(NSInteger, GZJelczStreamplaceIrohBridgeErrorCode) {
    GZJelczStreamplaceIrohBridgeErrorDisabled = 1,
    GZJelczStreamplaceIrohBridgeErrorDenied = 2,
    GZJelczStreamplaceIrohBridgeErrorInvalidOrigin = 3,
    GZJelczStreamplaceIrohBridgeErrorStaleOrigin = 4,
    GZJelczStreamplaceIrohBridgeErrorBridgeFailed = 5,
    GZJelczStreamplaceIrohBridgeErrorBodyTooLarge = 6,
    GZJelczStreamplaceIrohBridgeErrorInvalidMUXL = 7,
    /** Successful subscription did not carry a bounded bridge session header. */
    GZJelczStreamplaceIrohBridgeErrorMissingSession = 8,
    /** The bridge rejected, expired, or could not persist Jelcz's attestation. */
    GZJelczStreamplaceIrohBridgeErrorAttestationRejected = 9,
};

/**
 Nonsecret evidence bound to one successful local bridge subscription.

 The ticket fingerprint is SHA-256 over the exact UTF-8 ticket submitted to the
 bridge. It permits scenario correlation without revealing the ticket or media.
 */
@interface GZJelczStreamplaceIrohBridgeEvidence : NSObject

@property (nonatomic, copy, readonly) NSString *sessionID;
@property (nonatomic, copy, readonly) NSString *ticketFingerprint;
/** SHA-256 of the exact structurally valid subscription response bytes. */
@property (nonatomic, copy, readonly) NSString *contentSHA256;
@property (nonatomic, assign, readonly) NSUInteger contentBytes;
@property (nonatomic, assign, readonly, getter=isStructurallyValid) BOOL structurallyValid;

@end

/**
 Local-only, opt-in adapter for one `POST /v1/subscribe` request to an external
 Streamplace iroh bridge.  The bridge receives the iroh ticket and streamer DID;
 it returns exactly one pushed MUXL segment as the response body.
 */
@interface GZJelczStreamplaceIrohBridge : NSObject

@property (nonatomic, strong, readonly) id<ATProtoCAMirrorHTTPClient> httpClient;
/** Loopback HTTP base URL, without a trailing slash. */
@property (nonatomic, copy, readonly) NSString *bridgeBaseURL;
/** Capability presented only to the local bridge; never returned by demo APIs. */
@property (nonatomic, copy, readonly) NSString *capabilityToken;
@property (nonatomic, copy, readonly) NSSet<NSString *> *allowedStreamers;
/** Maximum accepted age of a broadcast-origin `updatedAt` timestamp. */
@property (nonatomic, assign) NSTimeInterval maximumOriginAge;
/** Maximum returned segment body size; a response beyond this is discarded. */
@property (nonatomic, assign) NSUInteger maximumSegmentBytes;
@property (nonatomic, assign) NSTimeInterval timeout;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (nullable instancetype)initWithHTTPClient:(id<ATProtoCAMirrorHTTPClient>)httpClient
                              bridgeBaseURL:(NSString *)bridgeBaseURL
                            capabilityToken:(NSString *)capabilityToken
                                   trustLAN:(BOOL)trustLAN
                           allowedStreamers:(NSSet<NSString *> *)allowedStreamers
    NS_DESIGNATED_INITIALIZER;

/** Default-off `JELCZ_STREAMPLACE_IROH_BRIDGE` configuration switch. */
+ (BOOL)isEnabledInEnvironment:(NSDictionary<NSString *, NSString *> *)environment;

/** Whether the explicit Docker-lab private-service exception is enabled. */
+ (BOOL)trustLANInEnvironment:(NSDictionary<NSString *, NSString *> *)environment;

/**
 Normalizes `JELCZ_STREAMPLACE_IROH_BRIDGE_URL`. Loopback HTTP is the default;
 private service-name HTTP requires the explicit lab-only
 `JELCZ_STREAMPLACE_IROH_BRIDGE_TRUST_LAN=1` setting and bearer capability.
 */
+ (nullable NSString *)bridgeHTTPBaseURLFromEnvironment:
    (NSDictionary<NSString *, NSString *> *)environment;

/** Parses a bounded positive integer env value, otherwise returns @c fallback. */
+ (NSUInteger)boundedByteLimitFromEnvironment:(NSDictionary<NSString *, NSString *> *)environment
                                           key:(NSString *)key
                                      fallback:(NSUInteger)fallback
                                       maximum:(NSUInteger)maximum;

/**
 Performs a single bridge subscription after validating explicit streamer consent,
 broadcast-origin shape, a fresh `updatedAt`, and an iroh ticket.  Its returned
 bytes passed MUXL catalog and fragment validation and remain caller-owned.
 */
- (nullable NSData *)receiveSegmentFromOrigin:(GZJelczPeerProviderEntry *)origin
                                     now:(NSDate *)now
                                   error:(NSError **)error;

/**
 As above, additionally returns evidence only after the bridge accepted Jelcz's
 capability-protected attestation of the structurally valid response bytes.
 */
- (nullable NSData *)receiveSegmentFromOrigin:(GZJelczPeerProviderEntry *)origin
                                          now:(NSDate *)now
                                     evidence:(GZJelczStreamplaceIrohBridgeEvidence * _Nullable * _Nullable)evidence
                                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

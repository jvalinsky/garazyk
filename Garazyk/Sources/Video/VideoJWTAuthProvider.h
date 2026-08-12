// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Video/VideoAuthProvider.h"

@class ATProtoDIDResolver;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Provides authentication using ATProtoJWT (JSON Web Tokens) for video services.
 */
@interface GZVideoJWTAuthProvider : NSObject <VideoAuthProvider>

/**
 * @abstract The expected audience (aud) claim for validated JWTs.
 */
@property (nonatomic, copy, readonly) NSString *audience;

/**
 * @abstract The signing key as a JWK dictionary, if verification is key-based.
 */
@property (nonatomic, copy, nullable, readonly) NSDictionary *signingKeyJWK;

/**
 * @abstract The DID resolver instance for key-based authentication.
 */
@property (nonatomic, strong, nullable, readonly) ATProtoDIDResolver *didResolver;

/**
 * @abstract Initializes with an expected audience and static JWK.
 * @param audience Expected ATProtoJWT audience.
 * @param signingKeyJWK Optional signing key JWK for verification.
 */
- (instancetype)initWithExpectedAudience:(NSString *)audience
                            signingKeyJWK:(nullable NSDictionary *)signingKeyJWK;

/**
 * @abstract Initializes with an expected audience and PDS endpoint for DID resolution.
 * @param audience Expected ATProtoJWT audience.
 * @param pdsURL Base URL for PDS-based DID resolution.
 * @param plcURL Optional PLC directory URL.
 */
- (instancetype)initWithExpectedAudience:(NSString *)audience
                                 pdsURL:(NSString *)pdsURL
                                 plcURL:(nullable NSString *)plcURL;

@end

NS_ASSUME_NONNULL_END

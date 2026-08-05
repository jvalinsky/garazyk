// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Video/VideoAuthProvider.h"

@class ATProtoJWTMinter;
/**
 * @abstract Defines the PDSAdminController protocol contract.
 */
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Provides PDS-based authentication for video services.
 */
@interface VideoPDSAuthProvider : NSObject <VideoAuthProvider>

/**
 * @abstract The ATProtoJWT minter instance for issuing tokens.
 */
@property (nonatomic, strong, readonly) ATProtoJWTMinter *jwtMinter;

/**
 * @abstract Optional PDS admin controller interface.
 */
@property (nonatomic, weak, nullable, readonly) id<PDSAdminController> adminController;

/**
 * @abstract Initializes a new PDS auth provider.
 * @param jwtMinter The ATProtoJWTMinter to use for token operations.
 * @param adminController Optional admin controller reference.
 */
- (instancetype)initWithJwtMinter:(ATProtoJWTMinter *)jwtMinter
                   adminController:(nullable id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END

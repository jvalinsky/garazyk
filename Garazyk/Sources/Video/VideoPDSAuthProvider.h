// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Video/VideoAuthProvider.h"

@class JWTMinter;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@interface VideoPDSAuthProvider : NSObject <VideoAuthProvider>

@property (nonatomic, strong, readonly) JWTMinter *jwtMinter;
@property (nonatomic, weak, nullable, readonly) id<PDSAdminController> adminController;

- (instancetype)initWithJwtMinter:(JWTMinter *)jwtMinter
                   adminController:(nullable id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END

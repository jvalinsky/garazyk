// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/XrpcRoutePack.h"

NS_ASSUME_NONNULL_BEGIN

@class ATProtoHttpRequest;

/**
 * Binary-fixture controls for exercising permissioned-space recovery paths.
 * This pack is deliberately unlexiconed and is registered only when all test
 * environment gates are enabled; it is never part of production routing.
 */
@interface ATProtoXrpcSpaceRecoveryTestPack : NSObject <XrpcRoutePack>

+ (BOOL)isEnabledForEnvironment:(NSDictionary<NSString *, NSString *> *)environment;
+ (BOOL)isAuthorizedRequest:(ATProtoHttpRequest *)request
                environment:(NSDictionary<NSString *, NSString *> *)environment;
+ (BOOL)isFixtureSpaceURI:(NSString *)space;

@end

NS_ASSUME_NONNULL_END

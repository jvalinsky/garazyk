// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

@class GZAdminUIServiceConfig;

NS_ASSUME_NONNULL_BEGIN

/** @abstract Admin UI pack for the Lab surface. */
@interface GZAdminUILabPack : NSObject <GZAdminUIPack>

/** @abstract Renders the lab shell with the response CSP nonce. */
+ (NSString *)labShellHTMLWithNonce:(nullable NSString *)nonce configuration:(GZAdminUIServiceConfig *)configuration;
/** @abstract Serializes safe client metadata for the lab shell. */
+ (NSString *)labClientMetadataJSONWithConfiguration:(GZAdminUIServiceConfig *)configuration;

@end

NS_ASSUME_NONNULL_END

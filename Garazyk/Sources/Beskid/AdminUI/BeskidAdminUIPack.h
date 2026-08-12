// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

@class GZAdminUIHost;
@class GZBeskidAdminSnapshot;

NS_ASSUME_NONNULL_BEGIN

/** Beskid-owned embedded admin pack. */
@interface GZBeskidAdminUIPack : NSObject <GZAdminUIPack>

+ (void)configureHost:(GZAdminUIHost *)host snapshot:(GZBeskidAdminSnapshot *)snapshot;

@end

NS_ASSUME_NONNULL_END

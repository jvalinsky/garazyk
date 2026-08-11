// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

@class GZAdminUIHost;
@class GZPLCAdminSnapshot;

NS_ASSUME_NONNULL_BEGIN

/** PLC-owned embedded admin pack. */
@interface GZPLCAdminUIPack : NSObject <GZAdminUIPack>
+ (void)configureHost:(GZAdminUIHost *)host snapshot:(GZPLCAdminSnapshot *)snapshot;
@end

NS_ASSUME_NONNULL_END

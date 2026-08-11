// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"
@class GZAdminUIHost;
@class GZRelayAdminSnapshot;
NS_ASSUME_NONNULL_BEGIN
@interface GZRelayAdminUIPack : NSObject <GZAdminUIPack>
+ (void)configureHost:(GZAdminUIHost *)host snapshot:(GZRelayAdminSnapshot *)snapshot;
@end
NS_ASSUME_NONNULL_END

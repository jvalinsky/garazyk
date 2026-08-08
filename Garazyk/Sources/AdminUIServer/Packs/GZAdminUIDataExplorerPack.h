// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

NS_ASSUME_NONNULL_BEGIN

/** @abstract Admin UI pack for the Data Explorer surface. */
@interface GZAdminUIDataExplorerPack : NSObject <GZAdminUIPack>

/** @abstract Renders PDS repository metadata. */
+ (NSString *)renderDescribeRepoPartial:(NSDictionary *)result;
/** @abstract Renders a PDS record-list result. */
+ (NSString *)renderListRecordsPartial:(NSDictionary *)result;
/** @abstract Renders a single PDS record result. */
+ (NSString *)renderGetRecordPartial:(NSDictionary *)result;

@end

NS_ASSUME_NONNULL_END
